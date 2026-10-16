--[[
	Quick Draw (Duel: exactly two players, played from board Duel spaces)
	A reaction duel. "Wait for it..." then the light turns green: first to press DRAW wins
	the point. Press before the light and you lose the point (false start). First to 2.

	Server-authoritative: the server picks the moment, and judges presses by when it
	receives them. Bots react after a skill-based delay and sometimes jump the gun.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local QuickDraw = {}

QuickDraw.Info = {
	Name = "Quick Draw",
	Description = "Wait for the light to turn green, then press DRAW first. Too early and you lose the point! First to 2.",
	Duration = 40,
	Layout = Config.Layouts.Duel,
	Camera = { Mode = "SideView", Distance = 36, Height = 6 },
	Controls = {
		Move = false,
		Jump = false,
		Actions = {
			{ Action = "Draw", Label = "DRAW!", Key = "Space", Gamepad = "ButtonA" },
		},
	},
	ProgressLabel = "Points",
}

-- Tuning ----------------------------------------------------------------------------------
QuickDraw.POINTS_TO_WIN = 2
QuickDraw.WAIT_RANGE = { 1.5, 4 } -- seconds before the light turns green
QuickDraw.BETWEEN_POINTS = 2 -- pause after each point
QuickDraw.BOT_REACTION = { 0.22, 0.6 } -- fastest (skill 1) .. slowest (skill 0), seconds
QuickDraw.BOT_FALSE_START = 0.12 -- chance per point a skill-0 bot jumps the gun (less with skill)
local GAP = 16

local COLORS = { Wait = Color3.fromRGB(220, 60, 60), Draw = Color3.fromRGB(60, 220, 90), Idle = Color3.fromRGB(90, 90, 110) }

function QuickDraw:Setup(arena, participants, round)
	self.Points = {}
	self.State = "Idle" -- Idle | Waiting | Draw
	self.Now = self.Now or os.clock
	self.Rng = round.Rng
	for _, participant in participants do
		self.Points[participant] = 0
	end

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(GAP + 12, 1, 10)
	floor.CFrame = arena.Origin
	floor.Color = Color3.fromRGB(200, 170, 120)
	floor.Parent = arena.Folder

	local light = Instance.new("Part")
	light.Name = "Light"
	light.Anchored = true
	light.Shape = Enum.PartType.Ball
	light.Size = Vector3.new(4, 4, 4)
	light.Material = Enum.Material.Neon
	light.Color = COLORS.Idle
	light.CFrame = arena.Origin * CFrame.new(0, 9, 0)
	light.Parent = arena.Folder
	self.Light = light

	local spawns = {}
	for index, participant in participants do
		local side = if index == 1 then -1 else 1
		local position = (arena.Origin * CFrame.new(side * GAP / 2, 4, 0)).Position
		spawns[index] = CFrame.lookAt(position, (arena.Origin * CFrame.new(0, 4, 0)).Position)
		participant.QuickDrawSide = side
	end
	return spawns
end

function QuickDraw:_setLight(state: string)
	self.State = state
	if self.Light then
		self.Light.Color = COLORS[if state == "Draw" then "Draw" elseif state == "Waiting" then "Wait" else "Idle"]
	end
end

function QuickDraw:_report()
	for participant, points in self.Points do
		self.Round:ReportProgress(participant, points)
	end
end

-- Starts a point: red light, then green after a random wait.
function QuickDraw:_arm()
	self:_setLight("Waiting")
	self.Round:SetStatus("Wait for it...")
	self.PointId = (self.PointId or 0) + 1
	local pointId = self.PointId
	local wait = self.Rng:NextNumber(QuickDraw.WAIT_RANGE[1], QuickDraw.WAIT_RANGE[2])
	self.DrawAt = self.Now() + wait
	task.delay(wait, function()
		if self.PointId == pointId and self.State == "Waiting" and not self.Round.Ended then
			self:_setLight("Draw")
			self.Round:SetStatus("DRAW!")
		end
	end)
end

-- Awards the point and starts the next one (or ends the duel).
function QuickDraw:_award(winner, why: string)
	self:_setLight("Idle")
	self.Points[winner] += 1
	self:_report()
	self.Round:Toast(("%s %s"):format(winner.Name, why))
	if self.Points[winner] >= QuickDraw.POINTS_TO_WIN then
		self.Round:End("Winner")
		return
	end
	task.delay(QuickDraw.BETWEEN_POINTS, function()
		if not self.Round.Ended then
			self:_arm()
		end
	end)
end

function QuickDraw:_other(participant)
	for _, other in self.Participants do
		if other ~= participant then
			return other
		end
	end
	return nil
end

-- A DRAW press. Judged on the server's clock.
function QuickDraw:Press(participant)
	if self.State == "Waiting" then
		local other = self:_other(participant)
		if other then
			self:_award(other, ("wins the point: %s jumped the gun"):format(participant.Name))
		end
	elseif self.State == "Draw" then
		self:_award(participant, "drew first!")
	end
end

function QuickDraw:Start()
	self:_report()
	self:_arm()
end

function QuickDraw:OnInput(participant, action)
	if action == "Draw" then
		self:Press(participant)
	end
end

function QuickDraw:UpdateBot(bot, _dt)
	local memory = bot.Memory
	if memory.Point ~= self.PointId then
		memory.Point = self.PointId
		local reaction = QuickDraw.BOT_REACTION[2] - (QuickDraw.BOT_REACTION[2] - QuickDraw.BOT_REACTION[1]) * bot.Skill
		memory.PressAt = (self.DrawAt or math.huge) + reaction * (0.85 + math.random() * 0.3)
		if math.random() < QuickDraw.BOT_FALSE_START * (1 - bot.Skill) then
			memory.PressAt = (self.DrawAt or math.huge) - 0.4 -- jumps the gun
		end
	end
	if self.State ~= "Idle" and memory.PressAt and self.Now() >= memory.PressAt then
		memory.PressAt = nil
		bot:Input("Draw")
	end
end

function QuickDraw:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		return self.Points[participant] or 0
	end)
end

function QuickDraw:Cleanup()
	self.PointId = -1
	self.State = "Idle"
end

return QuickDraw
