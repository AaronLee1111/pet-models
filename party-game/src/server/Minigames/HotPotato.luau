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
local PASS_COOLDOWN = 1.0 -- holder can't pass again this soon after receiving
local NO_TAG_BACKS = 3.0 -- can't pass straight back to whoever just gave it to you
local RECEIVE_STUN = 0.9 -- "hot hands": a new holder is rooted this long, so everyone else can scatter
local FUSE_RANGE = { 8, 14 } -- seconds, re-rolled for every new potato
local HOLDER_SPEED = 21 -- holder is a bit faster so they can actually catch people
local NEW_POTATO_DELAY = 2

-- Bot feel. Reaction times are { sloppiest bot, sharpest bot } in seconds, plus random jitter.
local BOT_PASS_REACTION = { 1.4, 0.25 } -- in range of a victim -> actually pressing Pass
local BOT_FLEE_REACTION = { 0.55, 0.12 } -- potato changes hands -> noticing and changing direction
local BOT_COMFORT_DISTANCE = { 16, 26 } -- each bot stops running once it is this far from the holder
local BOT_PERSONAL_SPACE = 13 -- non-holders steer apart when closer than this to each other

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

	-- Rooted for a beat, then faster than everyone else.
	participant:SetMovement(0, false)
	local receivedAt = self.ReceivedAt
	task.delay(RECEIVE_STUN, function()
		if not self.Cleaned and not self.Round.Ended and self.Holder == participant and self.ReceivedAt == receivedAt then
			participant:SetMovement(HOLDER_SPEED, true)
		end
	end)
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
	Bot behaviour: if I have the potato, chase the nearest player I'm allowed to pass to and
	hand it over after a human-ish reaction delay. Otherwise keep my distance from the holder
	and from the other runners, so the pack spreads around the ring instead of clumping.
]]
local function reaction(range, skill: number): number
	return (range[1] + (range[2] - range[1]) * skill) * (0.7 + math.random() * 0.6)
end

function HotPotato:UpdateBot(bot, _dt)
	local me = bot.Participant
	local myPosition = bot:GetPosition()
	if not myPosition then
		return
	end
	local memory = bot.Memory
	local clock = now()
	local center = self.Arena.Origin.Position

	if self.Holder == me then
		if clock - self.ReceivedAt < RECEIVE_STUN then
			return
		end
		-- Chase whoever is closest, but not the player I can't tag back yet (unless nobody else is left).
		local target, targetDistance = nil, math.huge
		local fallback, fallbackDistance = nil, math.huge
		for _, other in self.Round:GetAlive() do
			local position = other:GetPosition()
			if other ~= me and position then
				local distance = (position - myPosition).Magnitude
				local blocked = other == self.PreviousHolder and clock - self.ReceivedAt < NO_TAG_BACKS
				if blocked then
					if distance < fallbackDistance then
						fallback, fallbackDistance = other, distance
					end
				elseif distance < targetDistance then
					target, targetDistance = other, distance
				end
			end
		end
		if not target then
			target, targetDistance = fallback, fallbackDistance
		end
		if not target then
			return
		end
		-- Each time it gets the potato a bot picks who to go after. Usually the closest
		-- player, sometimes someone further away, so the chases aren't all the same length.
		if memory.VictimFor ~= self.ReceivedAt then
			memory.VictimFor = self.ReceivedAt
			memory.Victim = target
			if math.random() > 0.45 + bot.Skill * 0.35 then
				local others = {}
				for _, other in self.Round:GetAlive() do
					if other ~= me and other ~= self.PreviousHolder and other:GetPosition() then
						table.insert(others, other)
					end
				end
				if #others > 0 then
					memory.Victim = others[math.random(1, #others)]
				end
			end
		end
		local victim = memory.Victim
		local victimPosition = victim and not self.Round:IsEliminated(victim) and victim:GetPosition()
		bot:MoveTo(victimPosition or target:GetPosition())
		-- Whoever wanders into reach gets it, victim or not.
		if targetDistance <= PASS_RANGE * 0.9 then
			memory.PassAt = memory.PassAt or (clock + reaction(BOT_PASS_REACTION, bot.Skill))
			if clock >= memory.PassAt then
				memory.PassAt = nil
				bot:Input("Pass")
			end
		else
			memory.PassAt = nil
		end
		return
	end
	memory.PassAt = nil

	local holder = self.Holder
	local holderPosition = holder and holder:GetPosition()
	if not holderPosition then
		-- Nobody has it right now: wander to my own spot instead of bunching up in the middle.
		if not memory.IdleSpot or clock >= (memory.IdleUntil or 0) then
			local angle = math.random() * math.pi * 2
			local radius = 6 + math.random() * (ARENA_RADIUS - 14)
			memory.IdleSpot = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			memory.IdleUntil = clock + 1.5 + math.random() * 1.5
		end
		bot:MoveTo(Vector3.new(memory.IdleSpot.X, myPosition.Y, memory.IdleSpot.Z))
		memory.SeenHolder = nil
		return
	end

	-- It takes a moment to notice the potato changed hands.
	if memory.SeenHolder ~= holder then
		memory.SeenHolder = holder
		memory.ReactAt = clock + reaction(BOT_FLEE_REACTION, bot.Skill)
	end
	if clock < (memory.ReactAt or 0) then
		return
	end
	memory.Comfort = memory.Comfort
		or (BOT_COMFORT_DISTANCE[1] + math.random() * (BOT_COMFORT_DISTANCE[2] - BOT_COMFORT_DISTANCE[1]))

	local away = myPosition - holderPosition
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end

	-- Push away from the other runners too.
	local spread = Vector3.zero
	for _, other in self.Round:GetAlive() do
		local position = other ~= me and other ~= holder and other:GetPosition()
		if position then
			local apart = Vector3.new(myPosition.X - position.X, 0, myPosition.Z - position.Z)
			if apart.Magnitude < 0.1 then
				apart = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			if apart.Magnitude < BOT_PERSONAL_SPACE then
				spread += apart.Unit * (1 - apart.Magnitude / BOT_PERSONAL_SPACE)
			end
		end
	end

	if away.Magnitude > memory.Comfort and spread.Magnitude < 0.15 then
		bot:Stop() -- far enough and not crowded: catch a breath
		return
	end

	-- Each bot leans to one side for a while, so they don't all flee in the same straight line.
	if clock >= (memory.SwerveUntil or 0) then
		memory.Swerve = (math.random() - 0.5) * 1.2
		memory.SwerveUntil = clock + 0.8 + math.random() * 1.4
	end
	local urgency = math.clamp(1.6 - away.Magnitude / memory.Comfort, 0.2, 1.6)
	local direction = away.Unit * urgency
		+ Vector3.new(-away.Unit.Z, 0, away.Unit.X) * memory.Swerve
		+ spread * 1.4
	if direction.Magnitude < 0.05 then
		direction = away.Unit
	end
	local goal = myPosition + direction.Unit * 12
	local fromCenter = Vector3.new(goal.X - center.X, 0, goal.Z - center.Z)
	if fromCenter.Magnitude > ARENA_RADIUS - 5 then
		-- Cornered against the wall: slide around the ring instead, away from the holder.
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
