--[[
	Kernel Catch (FFA, score)
	Popcorn and rocks rain from the sky. Every drop shows a shadow on the floor about a
	second before it lands. Stand under popcorn to catch it in your head bucket (+1);
	a rock knocks kernels out of the bucket and stuns you for a moment.
	Most popcorn when the timer runs out wins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local KernelCatch = {}

-- Tuning ----------------------------------------------------------------------------------

local ROUND_DURATION = 30
-- Seconds between drops: { at GO, at the buzzer }. Smaller = more stuff falling.
local DROP_INTERVAL = { 0.45, 0.15 }
-- Chance that a drop is a rock instead of popcorn: { at GO, at the buzzer }.
local ROCK_RATIO = { 0.22, 0.38 }
local WARNING_TIME = 1.0 -- the shadow shows up this long before impact
local AIMED_POPCORN_CHANCE = 0.3 -- share of kernels aimed near a random player instead of anywhere
local AIMED_ROCK_CHANCE = 0.7 -- share of rocks aimed near a random player
local AIM_SPREAD = 6 -- studs of scatter around the player an aimed drop targets

local POPCORN_POINTS = 1
local ROCK_PENALTY = 4 -- kernels lost per rock hit (score never goes below 0)
local STUN_TIME = 1.2 -- seconds a rock hit roots you (you can't catch while stunned)
local STUN_IMMUNITY = 0.6 -- extra seconds after a stun before another rock can hit you

local CATCH_RADIUS = 3.2 -- how close (flat distance) your bucket must be to a landing kernel
local ROCK_RADIUS = 3.6 -- how close a landing rock must be to hit you
local ARENA_RADIUS = 26
-- Nothing lands in this strip along the edge nearest the camera, where a falling drop would
-- fill the screen and cross the HUD.
local NEAR_EDGE_MARGIN = 9
local DROP_HEIGHT = 30
local WALK_SPEED = 18

KernelCatch.Info = {
	Name = "Kernel Catch",
	Description = "It's raining popcorn 🍿! Stand on the shadows to catch kernels in your head bucket. Dodge the rocks or lose your snacks!",
	Duration = ROUND_DURATION,
	Layout = Config.Layouts.FFA,
	Camera = { Mode = "AngledOverhead", Height = 42, Distance = 32 },
	Controls = { Move = true, Jump = true, WalkSpeed = WALK_SPEED },
	ProgressLabel = "Popcorn",
}

local POPCORN_COLOR = Color3.fromRGB(255, 244, 190)
local ROCK_COLOR = Color3.fromRGB(110, 110, 120)

local function now()
	return Workspace:GetServerTimeNow()
end

local function lerp(range, alpha: number): number
	return range[1] + (range[2] - range[1]) * alpha
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Setup ---------------------------------------------------------------------------------

-- A striped popcorn bucket welded on top of the head. It lives in `parent` (the arena folder),
-- not in the character, so Highlights on the character (the stun flash) don't tint it.
local function makeBucket(character: Model, parent: Instance): Model?
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local bucket = Instance.new("Model")
	bucket.Name = "KernelBucket"

	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, shape)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0) * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
		part.Parent = bucket
		return part
	end

	-- Cylinders lie along X, so stand them upright.
	local upright = CFrame.Angles(0, 0, math.rad(90))
	piece("Tub", Vector3.new(1.6, 2.4, 2.4), CFrame.new(0, 0.8, 0) * upright, Color3.fromRGB(230, 60, 60), Enum.PartType.Cylinder)
	piece("Stripe", Vector3.new(0.5, 2.5, 2.5), CFrame.new(0, 0.8, 0) * upright, Color3.fromRGB(255, 255, 255), Enum.PartType.Cylinder)
	piece("Rim", Vector3.new(0.25, 2.8, 2.8), CFrame.new(0, 1.6, 0) * upright, Color3.fromRGB(255, 255, 255), Enum.PartType.Cylinder)
	local kernels = piece("Kernels", Vector3.new(2.2, 2.2, 2.2), CFrame.new(0, 1.5, 0), POPCORN_COLOR, Enum.PartType.Ball)
	kernels.Transparency = 1 -- shown once there is popcorn in the bucket

	bucket.Parent = parent
	return bucket
end

function KernelCatch:Setup(arena, participants, _round)
	local origin = arena.Origin
	self.Connections = {}
	self.Score = {}
	self.StunnedUntil = {}
	self.Buckets = {}
	self.Highlights = {}
	self.Drops = {}

	-- Round floor (cylinder parts lie along X, so rotate it flat).
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Shape = Enum.PartType.Cylinder
	floor.Size = Vector3.new(2, ARENA_RADIUS * 2, ARENA_RADIUS * 2)
	floor.CFrame = origin * CFrame.Angles(0, 0, math.rad(90))
	floor.Anchored = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(120, 60, 160)
	floor.Parent = arena.Folder

	-- Ring of see-through walls so nobody runs off the edge.
	local segments = 24
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Size = Vector3.new(2, 8, ARENA_RADIUS * 2 * math.pi / segments + 1)
		wall.CFrame = origin * CFrame.Angles(0, -angle, 0) * CFrame.new(ARENA_RADIUS, 5, 0)
		wall.Transparency = 0.6
		wall.Color = Color3.fromRGB(255, 220, 90)
		wall.Material = Enum.Material.ForceField
		wall.Parent = arena.Folder
	end

	local spawns = {}
	for index, participant in participants do
		self.Score[participant] = 0
		self.StunnedUntil[participant] = 0
		local angle = (index / #participants) * math.pi * 2
		local position = (origin * CFrame.new(math.cos(angle) * 12, 4, math.sin(angle) * 12)).Position
		spawns[index] = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))

		local character = participant:GetCharacter()
		if character then
			self.Buckets[participant] = makeBucket(character, arena.Folder)
		end
	end
	return spawns
end

-- Scoring -------------------------------------------------------------------------------

function KernelCatch:_setScore(participant, score: number)
	self.Score[participant] = score
	self.Round:ReportProgress(participant, ("🍿 %d"):format(score))
	local bucket = self.Buckets[participant]
	local kernels = bucket and bucket:FindFirstChild("Kernels")
	if kernels then
		kernels.Transparency = if score > 0 then 0 else 1
	end
end

function KernelCatch:_isStunned(participant): boolean
	return now() < self.StunnedUntil[participant]
end

function KernelCatch:_hitByRock(participant, position: Vector3)
	local stunEnds = now() + STUN_TIME
	self.StunnedUntil[participant] = stunEnds + STUN_IMMUNITY
	self:_setScore(participant, math.max(0, self.Score[participant] - ROCK_PENALTY))
	participant:SetMovement(0, false)
	self.Round:Toast(("💥 %s got bonked!"):format(participant.Name))

	-- Hit effect: a puff at the impact point and a red flash on the victim while stunned.
	local burst = Instance.new("Explosion")
	burst.Position = position
	burst.BlastPressure = 0
	burst.DestroyJointRadiusPercent = 0
	burst.Parent = self.Arena.Folder

	local character = participant:GetCharacter()
	local highlight
	if character then
		highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 40, 40)
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.35
		highlight.Parent = character
		self.Highlights[highlight] = true
	end

	task.delay(STUN_TIME, function()
		if highlight then
			self.Highlights[highlight] = nil
			highlight:Destroy()
		end
		if not self.Cleaned and not self.Round.Ended then
			participant:SetMovement(WALK_SPEED, true)
		end
	end)
end

-- Drops ---------------------------------------------------------------------------------

function KernelCatch:_spawnDrop(progress: number)
	local round = self.Round
	local origin = self.Arena.Origin

	local isRock = round.Rng:NextNumber() < lerp(ROCK_RATIO, progress)

	-- Where it lands (arena-local X/Z): near a random player, or anywhere on the floor.
	local offset
	local alive = round:GetAlive()
	local aimedChance = if isRock then AIMED_ROCK_CHANCE else AIMED_POPCORN_CHANCE
	if #alive > 0 and round.Rng:NextNumber() < aimedChance then
		local target = alive[round.Rng:NextInteger(1, #alive)]
		local position = target:GetPosition()
		if position then
			local angle = round.Rng:NextNumber() * math.pi * 2
			offset = flat(origin:PointToObjectSpace(position))
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * round.Rng:NextNumber() * AIM_SPREAD
		end
	end
	if not offset then
		local angle = round.Rng:NextNumber() * math.pi * 2
		local radius = math.sqrt(round.Rng:NextNumber()) * (ARENA_RADIUS - 3)
		offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	if offset.Magnitude > ARENA_RADIUS - 3 then
		offset = offset.Unit * (ARENA_RADIUS - 3)
	end
	-- The overhead camera sits on the arena's +Z side: keep drops out of the strip closest to it.
	local nearLimit = ARENA_RADIUS - 3 - NEAR_EDGE_MARGIN
	if offset.Z > nearLimit then
		offset = Vector3.new(offset.X, 0, nearLimit)
	end
	local landing = origin:PointToWorldSpace(Vector3.new(offset.X, 1, offset.Z))

	local size = if isRock then 3.4 else 1.8

	local object = Instance.new("Part")
	object.Name = if isRock then "Rock" else "Popcorn"
	object.Shape = Enum.PartType.Ball
	object.Size = Vector3.new(size, size, size)
	object.Color = if isRock then ROCK_COLOR else POPCORN_COLOR
	object.Material = if isRock then Enum.Material.Slate else Enum.Material.SmoothPlastic
	object.Anchored = true
	object.CanCollide = false
	object.CanQuery = false
	object.CanTouch = false
	object.Position = landing + Vector3.new(0, DROP_HEIGHT, 0)
	object.Parent = self.Arena.Folder

	-- Shadow: a flat disc that grows as the drop gets closer. Rocks cast a darker, redder one.
	local shadow = Instance.new("Part")
	shadow.Name = "Shadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.Material = Enum.Material.Neon
	shadow.Color = if isRock then Color3.fromRGB(60, 0, 10) else Color3.fromRGB(255, 225, 90)
	shadow.Transparency = 0.6
	shadow.Size = Vector3.new(0.1, 1, 1)
	shadow.CFrame = CFrame.new(landing + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Parent = self.Arena.Folder

	table.insert(self.Drops, {
		IsRock = isRock,
		Position = landing,
		LandsAt = now() + WARNING_TIME,
		Object = object,
		Shadow = shadow,
		ShadowSize = if isRock then ROCK_RADIUS * 2 else CATCH_RADIUS * 2,
	})
end

function KernelCatch:_land(drop)
	drop.Shadow:Destroy()
	local caught = false

	if drop.IsRock then
		for _, participant in self.Round:GetAlive() do
			local position = participant:GetPosition()
			if
				position
				and now() >= self.StunnedUntil[participant]
				and flat(position - drop.Position).Magnitude <= ROCK_RADIUS
			then
				self:_hitByRock(participant, drop.Position)
			end
		end
	else
		-- The closest bucket in reach gets the kernel.
		local best, bestDistance = nil, CATCH_RADIUS
		for _, participant in self.Round:GetAlive() do
			local position = participant:GetPosition()
			if position and not self:_isStunned(participant) then
				local distance = flat(position - drop.Position).Magnitude
				if distance <= bestDistance then
					best, bestDistance = participant, distance
				end
			end
		end
		if best then
			caught = true
			self:_setScore(best, self.Score[best] + POPCORN_POINTS)
		end
	end

	if caught then
		drop.Object:Destroy()
	else
		-- Missed kernels and rocks sit on the floor for a moment, then vanish.
		local object = drop.Object
		object.Position = drop.Position + Vector3.new(0, object.Size.Y / 2, 0)
		object.Transparency = 0.4
		task.delay(0.5, function()
			object:Destroy()
		end)
	end
end

-- Interface -----------------------------------------------------------------------------

function KernelCatch:Start()
	local round = self.Round
	local startedAt = now()
	local nextDropAt = startedAt + 0.5
	for _, participant in self.Participants do
		self:_setScore(participant, 0)
	end
	round:SetStatus("Catch the popcorn! 🍿")

	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function()
			if round.Ended then
				return
			end
			local clock = now()
			local progress = math.clamp((clock - startedAt) / ROUND_DURATION, 0, 1)

			while clock >= nextDropAt do
				nextDropAt += lerp(DROP_INTERVAL, progress)
				self:_spawnDrop(progress)
			end

			for index = #self.Drops, 1, -1 do
				local drop = self.Drops[index]
				local remaining = drop.LandsAt - clock
				if remaining <= 0 then
					table.remove(self.Drops, index)
					self:_land(drop)
				else
					local alpha = 1 - remaining / WARNING_TIME -- 0 = just spawned, 1 = impact
					local height = DROP_HEIGHT * (1 - alpha * alpha) -- speeds up as it falls
					drop.Object.Position = drop.Position + Vector3.new(0, height + drop.Object.Size.Y / 2, 0)
					local diameter = drop.ShadowSize * (0.35 + 0.65 * alpha)
					drop.Shadow.Size = Vector3.new(0.1, diameter, diameter)
					drop.Shadow.Transparency = 0.6 - 0.35 * alpha
				end
			end
		end)
	)
end

--[[
	Bot behaviour: step out from under any rock that is about to land, otherwise run to the
	best popcorn shadow it can still reach. Sloppier bots notice rocks later, re-think less
	often and sometimes run for kernels that have a rock coming down beside them.
]]
function KernelCatch:UpdateBot(bot, _dt)
	local me = bot.Participant
	local myPosition = bot:GetPosition()
	if not myPosition or self:_isStunned(me) then
		return
	end
	local memory = bot.Memory
	local clock = now()
	local center = self.Arena.Origin.Position

	local function inside(goal: Vector3): Vector3
		local fromCenter = flat(goal - center)
		if fromCenter.Magnitude > ARENA_RADIUS - 4 then
			fromCenter = fromCenter.Unit * (ARENA_RADIUS - 4)
		end
		return Vector3.new(center.X + fromCenter.X, myPosition.Y, center.Z + fromCenter.Z)
	end

	-- Dodge: a rock landing on top of me soon wins over everything else.
	local noticeTime = 0.2 + bot.Skill * 0.5
	local dodge = Vector3.zero
	for _, drop in self.Drops do
		if drop.IsRock and drop.LandsAt - clock < noticeTime then
			local away = flat(myPosition - drop.Position)
			if away.Magnitude < ROCK_RADIUS + 1.5 then
				if away.Magnitude < 0.1 then
					away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
				end
				dodge += away.Unit
			end
		end
	end
	if dodge.Magnitude > 0.05 then
		memory.Goal = nil
		bot:MoveTo(inside(myPosition + dodge.Unit * 8))
		return
	end

	-- Keep the current plan for a beat instead of re-deciding every tick.
	if memory.Goal and clock < (memory.DecideAt or 0) and memory.Goal.LandsAt > clock then
		bot:MoveTo(inside(memory.Goal.Position))
		return
	end
	memory.DecideAt = clock + 0.15 + (1 - bot.Skill) * 0.35 + math.random() * 0.15

	local carefulness = 0.35 + bot.Skill * 0.65
	local best, bestCost = nil, math.huge
	for _, drop in self.Drops do
		if not drop.IsRock then
			local distance = flat(drop.Position - myPosition).Magnitude
			local timeLeft = drop.LandsAt - clock
			local reachable = distance - CATCH_RADIUS * 0.6 <= WALK_SPEED * timeLeft
			-- Skip kernels with a rock coming down right beside them (if this bot is paying attention).
			local risky = false
			for _, other in self.Drops do
				if
					other.IsRock
					and math.abs(other.LandsAt - drop.LandsAt) < 0.7
					and flat(other.Position - drop.Position).Magnitude < ROCK_RADIUS + 1
				then
					risky = true
					break
				end
			end
			-- Leave kernels that someone else is clearly going to reach first, so the pack spreads out.
			local cost = distance
			for _, other in self.Round:GetAlive() do
				local position = other ~= me and other:GetPosition()
				local claimed = other.IsBot and other.Bot.Memory.Goal == drop
				if position and (claimed or flat(drop.Position - position).Magnitude < distance - 1) then
					cost += 25
				end
			end
			if reachable and not (risky and math.random() < carefulness) and cost < bestCost then
				best, bestCost = drop, cost
			end
		end
	end

	-- Only fight over a contested kernel when it is right next to me.
	if best and bestCost >= 25 and bestCost - 25 > CATCH_RADIUS * 2 then
		best = nil
	end
	memory.Goal = best
	if best then
		bot:MoveTo(inside(best.Position))
	elseif not memory.Wander or clock >= (memory.WanderUntil or 0) then
		-- Nothing worth chasing: patrol my own side of the ring so the bots cover the floor.
		memory.HomeAngle = memory.HomeAngle or math.random() * math.pi * 2
		local angle = memory.HomeAngle + (math.random() - 0.5) * 1.6
		local radius = ARENA_RADIUS * (0.25 + math.random() * 0.4)
		memory.Wander = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		memory.WanderUntil = clock + 1 + math.random()
		bot:MoveTo(inside(memory.Wander))
	end
end

function KernelCatch:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		return self.Score[participant]
	end)
end

function KernelCatch:Cleanup()
	self.Cleaned = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, bucket in self.Buckets do
		bucket:Destroy()
	end
	for highlight in self.Highlights do
		highlight:Destroy()
	end
	-- Drops, shadows and the map live in arena.Folder, which the framework destroys.
end

return KernelCatch
