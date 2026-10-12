--[[
	BotService
	Owns the AI players that fill empty seats.

	  BotService.getBots(count)    returns `count` bots with living bodies, creating/despawning as needed
	  BotService.setBrain(fn)      fn(bot, dt) runs every Config.BotThinkInterval for each live bot;
	                               the MinigameManager points this at the active minigame's UpdateBot
	  BotService.setActionHandler  how bot:Input(action) reaches the server (same path as player input)

	The Bot object a minigame's UpdateBot(bot, dt) receives:
	  bot.Participant              the bot's Participant for this round
	  bot.Memory                   scratch table, wiped every round - store your per-bot state here
	  bot.Skill                    0..1, use it to make some bots sloppier than others
	  bot:GetPosition()            Vector3?
	  bot:MoveTo(position)         walk towards a point
	  bot:Stop()
	  bot:Jump()
	  bot:Input(actionName)        press a minigame action exactly like a player would
	  bot:IsAlive()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)

local BotService = {}

local rng = Random.new()
local bots = {} -- every bot we currently own, in seat order
local nextBotNumber = 0
local brain: ((any, number) -> ())? = nil
local actionHandler: ((any, string) -> ())? = nil
local botFolder: Folder? = nil

-- Bot ------------------------------------------------------------------------------

local Bot = {}
Bot.__index = Bot

function Bot:IsAlive(): boolean
	local model = self.Model
	local humanoid = self.Humanoid
	return model ~= nil and model.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

function Bot:GetPosition(): Vector3?
	return if self:IsAlive() then self.Root.Position else nil
end

function Bot:MoveTo(position: Vector3)
	if self:IsAlive() then
		self.Humanoid:MoveTo(position)
	end
end

function Bot:Stop()
	if self:IsAlive() then
		self.Humanoid:MoveTo(self.Root.Position)
	end
end

function Bot:Jump()
	if self:IsAlive() then
		self.Humanoid.Jump = true
	end
end

function Bot:Input(action: string)
	if actionHandler and self.Participant then
		actionHandler(self.Participant, action)
	end
end

-- Bodies -----------------------------------------------------------------------------

local function getFolder(): Folder
	if not botFolder or not botFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "PartyBots"
		folder.Parent = Workspace
		botFolder = folder
	end
	return botFolder :: Folder
end

-- Plain blocky rig, only used if Roblox can't build an avatar (e.g. asset service hiccup).
local function buildFallbackRig(color: Color3): Model
	local model = Instance.new("Model")

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = color
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.Color = color
	head.CFrame = root.CFrame * CFrame.new(0, 1.8, 0)
	head.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

local function buildBody(name: string): Model
	local color = Color3.fromHSV(rng:NextNumber(), 0.6, 1)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.3)
	description.RightLegColor = color:Lerp(Color3.new(0, 0, 0), 0.3)

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[BotService] Avatar build failed, using fallback rig:", model)
		model = buildFallbackRig(color)
	end

	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = "🤖 " .. name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	return model
end

-- Gives the bot a fresh body at `cframe`, replacing a dead or missing one.
local function respawn(bot, cframe: CFrame)
	if bot.Model then
		bot.Model:Destroy()
	end
	local model = buildBody(bot.Name)
	model:PivotTo(cframe)
	model.Parent = getFolder()

	bot.Model = model
	bot.Humanoid = model:FindFirstChildOfClass("Humanoid")
	bot.Root = model:FindFirstChild("HumanoidRootPart")
	-- Server owns bot physics so MoveTo is smooth and nobody can hijack bots.
	bot.Root:SetNetworkOwner(nil)
end

local function pickName(): string
	local used = {}
	for _, bot in bots do
		used[bot.Name] = true
	end
	local candidates = {}
	for _, name in Config.BotNames do
		if not used[name] then
			table.insert(candidates, name)
		end
	end
	if #candidates == 0 then
		return "Bot " .. nextBotNumber
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function createBot()
	nextBotNumber += 1
	local bot = setmetatable({
		Id = "bot_" .. nextBotNumber,
		Name = pickName(),
		Skill = rng:NextNumber(0.3, 1),
		Memory = {},
		Participant = nil,
		Model = nil,
		Humanoid = nil,
		Root = nil,
	}, Bot)
	return bot
end

-- Public API -------------------------------------------------------------------------

--[[
	Returns exactly `count` bots, each with a living body somewhere near `spawnAt(index)`.
	Extra bots from a previous round (e.g. a real player joined) are removed.
]]
function BotService.getBots(count: number, spawnAt: (number) -> CFrame)
	while #bots > count do
		local bot = table.remove(bots) :: any
		if bot.Model then
			bot.Model:Destroy()
		end
	end
	while #bots < count do
		table.insert(bots, createBot())
	end

	for index, bot in bots do
		bot.Memory = {}
		bot.Participant = nil
		if not bot:IsAlive() then
			respawn(bot, spawnAt(index))
		end
	end
	return table.clone(bots)
end

-- Respawns any bot whose body died during the round.
function BotService.reviveAll(spawnAt: (number) -> CFrame)
	for index, bot in bots do
		if not bot:IsAlive() then
			respawn(bot, spawnAt(index))
		end
	end
end

function BotService.setBrain(fn: ((any, number) -> ())?)
	brain = fn
	for _, bot in bots do
		bot.Memory = {}
	end
end

function BotService.setActionHandler(fn: (any, string) -> ())
	actionHandler = fn
end

-- Think loop -------------------------------------------------------------------------

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < Config.BotThinkInterval then
		return
	end
	local step = accumulated
	accumulated = 0

	local currentBrain = brain
	if not currentBrain then
		return
	end
	for _, bot in bots do
		if bot.Participant and bot:IsAlive() then
			local ok, err = pcall(currentBrain, bot, step)
			if not ok then
				warn(("[BotService] %s's brain errored: %s"):format(bot.Name, tostring(err)))
			end
		end
	end
end)

return BotService
