--[[
	Hot Potato (FFA, elimination)
	One player holds a burning potato with a hidden fuse. Get next to someone and press
	Pass to hand it over. Whoever holds it when it explodes is out. Last one standing wins.
	If time runs out, the current holder explodes and everyone left ties for 1st.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local HotPotato = {}

HotPotato.Info = {
	Name = "Hot Potato",
	Description = "Someone's holding a spicy potato 🥔🔥. Get close and pass it before it goes BOOM. Last one standing wins!",
	Duration = 90,
	Layout = Config.Layouts.FFA,
	Camera = { Mode = "AngledOverhead", Height = 50, Distance = 38 },
	Controls = {
		Move = true,
		Jump = true,
		Actions = {
			{ Action = "Pass", Label = "Pass!", Key = "E", Gamepad = "ButtonX" },
		},
	},
	ProgressLabel = "Potato",
}

local ARENA_RADIUS = 30
local PASS_RANGE = 9 -- studs between root parts
local PASS_COOLDOWN = 0.6 -- holder can't pass again this soon after receiving
local NO_TAG_BACKS = 1.5 -- can't pass straight back to whoever just gave it to you
local FUSE_RANGE = { 8, 14 } -- seconds, re-rolled for every new potato
local HOLDER_SPEED = 21 -- holder is a bit faster so they can actually catch people
local NEW_POTATO_DELAY = 2

local function now()
	return Workspace:GetServerTimeNow()
end

-- Setup ---------------------------------------------------------------------------------

function HotPotato:Setup(arena, participants, _round)
	local origin = arena.Origin

	-- Round floor (cylinder parts lie along X, so rotate it flat).
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Shape = Enum.PartType.Cylinder
	floor.Size = Vector3.new(2, ARENA_RADIUS * 2, ARENA_RADIUS * 2)
	floor.CFrame = origin * CFrame.Angles(0, 0, math.rad(90))
	floor.Anchored = true
	floor.Material = Enum.Material.Sand
	floor.Color = Color3.fromRGB(255, 200, 120)
	floor.Parent = arena.Folder

	-- Ring of see-through walls so nobody runs off the edge.
	local segments = 24
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Size = Vector3.new(2, 8, ARENA_RADIUS * 2 * math.pi / segments + 1)
		wall.CFrame = origin
			* CFrame.Angles(0, -angle, 0)
			* CFrame.new(ARENA_RADIUS, 5, 0)
		wall.Transparency = 0.6
		wall.Color = Color3.fromRGB(255, 120, 60)
		wall.Material = Enum.Material.ForceField
		wall.Parent = arena.Folder
	end

	-- The potato itself. Anchored and moved every frame above the holder's head.
	local potato = Instance.new("Part")
	potato.Name = "Potato"
	potato.Shape = Enum.PartType.Ball
	potato.Size = Vector3.new(2.5, 2.5, 2.5)
	potato.Color = Color3.fromRGB(160, 110, 60)
	potato.Material = Enum.Material.Slate
	potato.Anchored = true
	potato.CanCollide = false
	potato.CanQuery = false
	potato.CanTouch = false
	potato.Transparency = 1
	potato.CFrame = origin
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 8
	fire.Parent = potato
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 40)
	light.Range = 12
	light.Parent = potato
	potato.Parent = arena.Folder

	self.Potato = potato
	self.Fire = fire
	self.Holder = nil
	self.PreviousHolder = nil
	self.ReceivedAt = 0
	self.FuseEndsAt = math.huge
	self.Connections = {}
	self.Highlight = nil

	-- Spawns: evenly around a circle, facing the middle.
	local spawns = {}
	for index = 1, #participants do
		local angle = (index / #participants) * math.pi * 2
		local position = (origin * CFrame.new(math.cos(angle) * 14, 4, math.sin(angle) * 14)).Position
		spawns[index] = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))
	end
	return spawns
end

-- Potato handling -----------------------------------------------------------------------

-- Player chips: who's holding it, who's safe, who's toast.
function HotPotato:_refreshChips()
	for _, participant in self.Participants do
		local value = if self.Round:IsEliminated(participant)
			then "💥 cooked"
			elseif participant == self.Holder then "🥔 HOT!"
			else "😎 safe"
		self.Round:ReportProgress(participant, value)
	end
end

function HotPotato:_setHolder(participant)
	local previous = self.Holder
	if previous then
		previous:SetMovement(Config.DefaultWalkSpeed, true)
	end
	if self.Highlight then
		self.Highlight:Destroy()
		self.Highlight = nil
	end

	self.PreviousHolder = previous
	self.Holder = participant
	self.ReceivedAt = now()
	if not participant then
		self.Potato.Transparency = 1
		self.Fire.Enabled = false
		self:_refreshChips()
		return
	end

	participant:SetMovement(HOLDER_SPEED, true)
	local character = participant:GetCharacter()
	if character then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 80, 0)
		highlight.OutlineColor = Color3.fromRGB(255, 230, 0)
		highlight.FillTransparency = 0.5
		highlight.Parent = character
		self.Highlight = highlight
	end
	self.Potato.Transparency = 0
	self.Fire.Enabled = true
	self.Round:SetStatus(("🥔 %s has the potato!"):format(participant.Name))
	self:_refreshChips()
end

-- Hands a fresh potato (new fuse) to a random survivor.
function HotPotato:_newPotato()
	local round = self.Round
	if round.Ended then
		return
	end
	local alive = round:GetAlive()
	if #alive <= 1 then
		round:End("LastStanding")
		return
	end
	self.FuseEndsAt = now() + round.Rng:NextNumber(FUSE_RANGE[1], FUSE_RANGE[2])
	self:_setHolder(alive[round.Rng:NextInteger(1, #alive)])
	round:Toast(("🔥 New potato! %s is holding it"):format(self.Holder.Name))
end

function HotPotato:_explode(spawnNext: boolean)
	local holder = self.Holder
	if not holder then
		return
	end
	self:_setHolder(nil)
	self.FuseEndsAt = math.huge

	local position = holder:GetPosition()
	if position then
		-- Visual only: no flinging and no joint breaking.
		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastPressure = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.Parent = self.Arena.Folder
	end
	self.Round:Toast(("💥 BOOM! %s got cooked"):format(holder.Name))
	self.Round:Eliminate(holder, true)
	self:_refreshChips()

	if spawnNext then
		if #self.Round:GetAlive() <= 1 then
			self.Round:End("LastStanding")
		else
			self.Round:SetStatus("🥔 Reheating the potato...")
			task.delay(NEW_POTATO_DELAY, function()
				if not self.Cleaned then
					self:_newPotato()
				end
			end)
		end
	end
end

-- Closest eligible survivor in pass range, or nil.
function HotPotato:_passTarget(from)
	local fromPosition = from:GetPosition()
	if not fromPosition then
		return nil
	end
	local best, bestDistance = nil, PASS_RANGE
	for _, other in self.Round:GetAlive() do
		local position = other:GetPosition()
		local isTagBack = other == self.PreviousHolder and now() - self.ReceivedAt < NO_TAG_BACKS
		if other ~= from and position and not isTagBack then
			local distance = (position - fromPosition).Magnitude
			if distance <= bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

function HotPotato:_tryPass(from)
	if from ~= self.Holder or now() - self.ReceivedAt < PASS_COOLDOWN then
		return
	end
	local target = self:_passTarget(from)
	if target then
		self:_setHolder(target)
	end
end

-- Interface -----------------------------------------------------------------------------

function HotPotato:Start()
	self:_refreshChips()
	self:_newPotato()
	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function()
			if self.Round.Ended or not self.Holder then
				return
			end
			-- Keep the potato floating above the holder's head.
			local position = self.Holder:GetPosition()
			if position then
				self.Potato.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
					* CFrame.Angles(0, os.clock() * 4, 0)
			end
			-- Flicker harder as the fuse gets short (we never show the real number).
			local remaining = self.FuseEndsAt - now()
			self.Fire.Size = if remaining < 3 then 7 + math.sin(os.clock() * 30) * 2 else 4
			if remaining <= 0 then
				self:_explode(true)
			end
		end)
	)
end

function HotPotato:OnInput(participant, action)
	if action == "Pass" then
		self:_tryPass(participant)
	end
end

-- Someone died or left: if they had the potato, hand out a new one.
function HotPotato:OnParticipantLost(participant)
	if participant == self.Holder then
		self:_setHolder(nil)
		task.delay(NEW_POTATO_DELAY, function()
			if not self.Cleaned then
				self:_newPotato()
			end
		end)
	elseif #self.Round:GetAlive() <= 1 then
		self.Round:End("LastStanding")
	end
end

-- Time's up: whoever is holding it explodes on the buzzer.
function HotPotato:OnRoundEnding(reason)
	if reason == "TimeUp" then
		self:_explode(false)
	end
end

--[[
	Bot behaviour: if I have the potato, chase the nearest player and pass when close.
	Otherwise run away from the holder while staying inside the ring.
]]
function HotPotato:UpdateBot(bot, _dt)
	local me = bot.Participant
	local myPosition = bot:GetPosition()
	if not myPosition then
		return
	end
	local center = self.Arena.Origin.Position

	if self.Holder == me then
		local target, targetDistance = nil, math.huge
		for _, other in self.Round:GetAlive() do
			local position = other:GetPosition()
			if other ~= me and position then
				local distance = (position - myPosition).Magnitude
				if distance < targetDistance then
					target, targetDistance = other, distance
				end
			end
		end
		if target then
			bot:MoveTo(target:GetPosition())
			-- Sloppier bots sometimes hesitate before passing.
			if targetDistance <= PASS_RANGE * 0.9 and math.random() < 0.4 + bot.Skill * 0.6 then
				bot:Input("Pass")
			end
		end
		return
	end

	local holderPosition = self.Holder and self.Holder:GetPosition()
	if not holderPosition then
		-- Nobody has it right now: drift back towards the middle.
		bot:MoveTo(center + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6)))
		return
	end

	local away = myPosition - holderPosition
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	if away.Magnitude > 22 and math.random() < 0.7 then
		return -- far enough, catch a breath
	end
	-- Run away with a sideways wobble so bots don't all flee in straight lines.
	local direction = away.Unit + Vector3.new(-away.Unit.Z, 0, away.Unit.X) * (math.random() - 0.5)
	local goal = myPosition + direction.Unit * 12
	local fromCenter = Vector3.new(goal.X - center.X, 0, goal.Z - center.Z)
	if fromCenter.Magnitude > ARENA_RADIUS - 5 then
		-- Cornered against the wall: slide around the ring instead.
		local tangent = Vector3.new(-fromCenter.Z, 0, fromCenter.X).Unit
		if tangent:Dot(away) < 0 then
			tangent = -tangent
		end
		goal = center + fromCenter.Unit * (ARENA_RADIUS - 7) + tangent * 8
	end
	bot:MoveTo(Vector3.new(goal.X, myPosition.Y, goal.Z))
end

function HotPotato:GetResults()
	return ResultsUtil.fromElimination(self.Participants, self.Round)
end

function HotPotato:Cleanup()
	self.Cleaned = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	if self.Highlight then
		self.Highlight:Destroy()
	end
	-- The potato and map live in arena.Folder, which the framework destroys.
end

return HotPotato
