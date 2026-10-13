--[[
	Ice Dash (FFA, race)
	Everyone slides forward down a frozen track on their own; you only steer left and right.
	It's ice, so you drift: momentum carries you sideways after you let go. Snow drifts and
	puddles slow you, bumpers and walls bounce you, and some stretches have no side walls -
	slide off and you restart from the last checkpoint.
	First over the finish line wins. Everyone else is ranked by how far they got.

	The server runs the sliding itself (position + velocity per racer) and places the
	characters every frame, so players and bots go through exactly the same physics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local IceDash = {}

-- Tuning ----------------------------------------------------------------------------------

local ROUND_DURATION = 40

-- Ice physics
local MAX_SPEED = 34 -- forward speed cap (studs/s)
local FORWARD_ACCEL = 16 -- how quickly you get back up to speed
local STEER_ACCEL = 42 -- sideways push while a steer button is held (studs/s^2)
local ICE_FRICTION = 1.3 -- sideways speed lost per second (fraction); lower = more drift
local MAX_SIDE_SPEED = 18
local SLOW_DRAG = 4 -- how hard a snow drift / puddle pulls you down to its speed cap

-- Obstacles
local SNOW_SLOW = 0.45 -- speed cap multiplier inside a snow drift
local PUDDLE_SLOW = 0.65 -- speed cap multiplier inside a puddle
local PUDDLE_STEER = 0.3 -- steering multiplier inside a puddle (you aquaplane)
local BUMPER_BOUNCE = 0.9 -- bounciness of a bumper hit (0 = dead stop, 1 = perfect bounce)
local BUMPER_KICK = 14 -- extra speed a bumper adds along the bounce direction
local WALL_BOUNCE = 0.6 -- bounciness of side walls and barrier blocks
local RACER_BOUNCE = 0.7 -- bounciness when two racers slide into each other

-- Track layout
local TRACK_LENGTH = 800
local TRACK_WIDTH = 36
local OBSTACLE_SPACING = 30 -- studs between obstacle rows
local FIRST_OBSTACLE = 55 -- clear run-up after the start line
local CHECKPOINT_SPACING = 160
local RESPAWN_DELAY = 1.1 -- seconds between sliding off and reappearing at the checkpoint

local RACER_RADIUS = 1.6
local BUMPER_RADIUS = 2.6
local SNOW_SIZE = Vector2.new(13, 11) -- width, length
local PUDDLE_RADIUS = 5.5
local START_LANES = { -9, -3, 3, 9 }

IceDash.Info = {
	Name = "Ice Dash",
	Description = "Slide down the ice ❄! You move on your own, so just steer. Dodge bumpers and snow, don't slip off the edge. First to the flag wins!",
	Duration = ROUND_DURATION,
	Layout = Config.Layouts.FFA,
	Camera = { Mode = "FollowBehind", Height = 12, Distance = 22, Smooth = 12 },
	Controls = {
		Move = false, -- the server slides you; you only steer
		Jump = false,
		Actions = {
			{ Action = "Left", Label = "◀", Keys = { "A", "Left" }, Gamepad = "DPadLeft", Hold = true, Side = "Left" },
			{ Action = "Right", Label = "▶", Keys = { "D", "Right" }, Gamepad = "DPadRight", Hold = true },
		},
	},
	ProgressLabel = "Progress",
	ProgressBar = true,
}

local HALF_WIDTH = TRACK_WIDTH / 2

-- Track building ----------------------------------------------------------------------------

function IceDash:_part(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in properties do
		part[key] = value
	end
	part.Parent = self.Arena.Folder
	return part
end

-- Track space: x = sideways (+ is the racer's right), s = distance from the start line.
function IceDash:_at(x: number, y: number, s: number): CFrame
	return self.Frame * CFrame.new(x, y, -s)
end

function IceDash:_buildTrack(rng)
	self.Snow = {} -- { X, S } centres of slow rectangles
	self.Puddles = {} -- { X, S }
	self.Bumpers = {} -- { X, S }
	self.Barriers = {} -- { X0, X1, S0, S1 }
	self.Open = {} -- { S0, S1 } stretches with no side walls
	self.Checkpoints = {}

	-- Ice sheet, with a run-off area past the finish.
	local total = TRACK_LENGTH + 60
	self:_part({
		Name = "Ice",
		Size = Vector3.new(TRACK_WIDTH, 1, total),
		CFrame = self:_at(0, 0, total / 2 - 10),
		Material = Enum.Material.Ice,
		Color = Color3.fromRGB(190, 235, 255),
		CanCollide = true,
	})

	local lanes = { -13, -8, -3, 3, 8, 13 }
	local s = FIRST_OBSTACLE
	while s < TRACK_LENGTH - 30 do
		local roll = rng:NextNumber()
		if roll < 0.24 then
			local x = rng:NextNumber(-HALF_WIDTH + 7, HALF_WIDTH - 7)
			table.insert(self.Snow, { X = x, S = s })
			self:_part({
				Name = "SnowDrift",
				Size = Vector3.new(SNOW_SIZE.X, 0.8, SNOW_SIZE.Y),
				CFrame = self:_at(x, 0.7, s),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(255, 255, 255),
			})
		elseif roll < 0.42 then
			local x = rng:NextNumber(-HALF_WIDTH + 6, HALF_WIDTH - 6)
			table.insert(self.Puddles, { X = x, S = s })
			self:_part({
				Name = "Puddle",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, PUDDLE_RADIUS * 2, PUDDLE_RADIUS * 2),
				CFrame = self:_at(x, 0.56, s) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(40, 110, 220),
				Transparency = 0.25,
			})
		elseif roll < 0.68 then
			-- Two bumpers in different lanes.
			local first = rng:NextInteger(1, #lanes)
			local second = (first + rng:NextInteger(2, 4) - 1) % #lanes + 1
			for _, lane in { first, second } do
				local x = lanes[lane]
				table.insert(self.Bumpers, { X = x, S = s })
				self:_part({
					Name = "Bumper",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(3, BUMPER_RADIUS * 2, BUMPER_RADIUS * 2),
					CFrame = self:_at(x, 2, s) * CFrame.Angles(0, 0, math.rad(90)),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255, 80, 140),
				})
			end
		elseif roll < 0.84 then
			-- A wall block sticking out from one side, or sitting in the middle.
			local width = TRACK_WIDTH * rng:NextNumber(0.3, 0.42)
			local kind = rng:NextInteger(1, 3)
			local x0 = if kind == 1 then -HALF_WIDTH elseif kind == 2 then HALF_WIDTH - width else -width / 2
			table.insert(self.Barriers, { X0 = x0, X1 = x0 + width, S0 = s - 1.5, S1 = s + 1.5 })
			self:_part({
				Name = "Barrier",
				Size = Vector3.new(width, 4, 3),
				CFrame = self:_at(x0 + width / 2, 2.5, s),
				Material = Enum.Material.Brick,
				Color = Color3.fromRGB(255, 170, 60),
			})
		else
			-- No side walls here, and a bumper in the middle to make it interesting.
			table.insert(self.Open, { S0 = s - OBSTACLE_SPACING / 2, S1 = s + OBSTACLE_SPACING / 2 })
			table.insert(self.Bumpers, { X = 0, S = s })
			self:_part({
				Name = "Bumper",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(3, BUMPER_RADIUS * 2, BUMPER_RADIUS * 2),
				CFrame = self:_at(0, 2, s) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 80, 140),
			})
			for _, side in { -1, 1 } do
				self:_part({
					Name = "EdgeWarning",
					Size = Vector3.new(2, 0.2, OBSTACLE_SPACING),
					CFrame = self:_at(side * (HALF_WIDTH - 1), 0.56, s),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255, 60, 60),
				})
			end
		end
		s += OBSTACLE_SPACING
	end

	-- Side walls everywhere except the open stretches.
	local wallStart = -10
	local function wall(s0: number, s1: number)
		if s1 - s0 < 1 then
			return
		end
		for _, side in { -1, 1 } do
			self:_part({
				Name = "SideWall",
				Size = Vector3.new(1.5, 4, s1 - s0),
				CFrame = self:_at(side * (HALF_WIDTH + 0.75), 2.5, (s0 + s1) / 2),
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(120, 200, 255),
				Transparency = 0.45,
			})
		end
	end
	for _, open in self.Open do
		wall(wallStart, open.S0)
		wallStart = open.S1
	end
	wall(wallStart, TRACK_LENGTH + 50)

	-- Start line, checkpoints and the finish arch.
	local function gate(at: number, color: Color3, name: string)
		self:_part({
			Name = name,
			Size = Vector3.new(TRACK_WIDTH, 0.2, 2),
			CFrame = self:_at(0, 0.58, at),
			Material = Enum.Material.Neon,
			Color = color,
		})
		for _, side in { -1, 1 } do
			self:_part({
				Name = name .. "Post",
				Size = Vector3.new(1.5, 14, 1.5),
				CFrame = self:_at(side * (HALF_WIDTH + 0.75), 7.5, at),
				Material = Enum.Material.Neon,
				Color = color,
			})
		end
		self:_part({
			Name = name .. "Beam",
			Size = Vector3.new(TRACK_WIDTH + 3, 1.5, 1.5),
			CFrame = self:_at(0, 14.5, at),
			Material = Enum.Material.Neon,
			Color = color,
		})
	end
	gate(0, Color3.fromRGB(255, 255, 255), "StartLine")
	local checkpoint = CHECKPOINT_SPACING
	while checkpoint < TRACK_LENGTH - 40 do
		table.insert(self.Checkpoints, checkpoint)
		gate(checkpoint, Color3.fromRGB(90, 255, 140), "Checkpoint")
		checkpoint += CHECKPOINT_SPACING
	end
	gate(TRACK_LENGTH, Color3.fromRGB(255, 220, 60), "FinishLine")
end

function IceDash:Setup(arena, participants, round)
	-- The track runs along the arena's +Z (away from the lobby); racers face down it.
	self.Frame = arena.Origin * CFrame.Angles(0, math.pi, 0)
	self.Connections = {}
	self.Racers = {}
	self.Anchored = {}
	self.FinishCount = 0
	self:_buildTrack(round.Rng)

	local spawns = {}
	for index, participant in participants do
		local lane = START_LANES[(index - 1) % #START_LANES + 1]
		self.Racers[participant] = {
			X = lane,
			S = 3,
			VX = 0,
			VS = 0,
			Left = false,
			Right = false,
			Lane = lane,
			Checkpoint = 3,
			State = "Racing", -- "Racing" | "Falling" | "Finished"
			FallTime = 0,
			RideHeight = 3.5,
			FinishTime = nil,
		}
		spawns[index] = self:_at(lane, 4, 3)
	end
	return spawns
end

-- Physics -----------------------------------------------------------------------------------

function IceDash:_hasWall(s: number): boolean
	for _, open in self.Open do
		if s >= open.S0 and s <= open.S1 then
			return false
		end
	end
	return true
end

-- Speed-cap and steering multipliers for whatever the racer is sliding over.
function IceDash:_surface(x: number, s: number): (number, number)
	local slow, steer = 1, 1
	for _, snow in self.Snow do
		if math.abs(x - snow.X) <= SNOW_SIZE.X / 2 and math.abs(s - snow.S) <= SNOW_SIZE.Y / 2 then
			slow = math.min(slow, SNOW_SLOW)
		end
	end
	for _, puddle in self.Puddles do
		local dx, ds = x - puddle.X, s - puddle.S
		if dx * dx + ds * ds <= PUDDLE_RADIUS * PUDDLE_RADIUS then
			slow = math.min(slow, PUDDLE_SLOW)
			steer = math.min(steer, PUDDLE_STEER)
		end
	end
	return slow, steer
end

-- Bounces the racer's velocity off a surface with normal (nx, ns).
local function bounce(racer, nx: number, ns: number, bounciness: number, kick: number)
	local into = racer.VX * nx + racer.VS * ns
	if into < 0 then
		racer.VX -= (1 + bounciness) * into * nx
		racer.VS -= (1 + bounciness) * into * ns
	end
	racer.VX += nx * kick
	racer.VS += ns * kick
end

function IceDash:_respawn(racer)
	racer.State = "Racing"
	racer.X = racer.Lane
	racer.S = racer.Checkpoint
	racer.VX = 0
	racer.VS = 0
	racer.FallTime = 0
end

function IceDash:_step(participant, racer, dt: number, elapsed: number)
	if racer.State == "Falling" then
		racer.FallTime += dt
		racer.X += racer.VX * dt
		racer.S += racer.VS * dt * 0.5
		if racer.FallTime >= RESPAWN_DELAY then
			self:_respawn(racer)
		end
		return
	end
	if racer.State == "Finished" then
		-- Glide to a stop in the run-off area.
		racer.VS *= math.exp(-2.5 * dt)
		racer.VX *= math.exp(-3 * dt)
		racer.X = math.clamp(racer.X + racer.VX * dt, -HALF_WIDTH + RACER_RADIUS, HALF_WIDTH - RACER_RADIUS)
		racer.S = math.min(racer.S + racer.VS * dt, TRACK_LENGTH + 40)
		return
	end

	local slow, steerGrip = self:_surface(racer.X, racer.S)
	local steer = (if racer.Right then 1 else 0) - (if racer.Left then 1 else 0)

	-- Sideways: push from steering, a little friction, lots of drift.
	racer.VX += steer * STEER_ACCEL * steerGrip * dt
	racer.VX *= math.exp(-ICE_FRICTION * dt)
	racer.VX = math.clamp(racer.VX, -MAX_SIDE_SPEED, MAX_SIDE_SPEED)

	-- Forward: always accelerating up to the cap of the surface you're on.
	local cap = MAX_SPEED * slow
	if racer.VS < cap then
		racer.VS = math.min(cap, racer.VS + FORWARD_ACCEL * dt)
	else
		racer.VS = cap + (racer.VS - cap) * math.exp(-SLOW_DRAG * dt)
	end

	racer.X += racer.VX * dt
	racer.S += racer.VS * dt

	-- Bumpers: round, bouncy, and they kick.
	for _, bumper in self.Bumpers do
		local dx, ds = racer.X - bumper.X, racer.S - bumper.S
		local reach = BUMPER_RADIUS + RACER_RADIUS
		local distanceSquared = dx * dx + ds * ds
		if distanceSquared < reach * reach then
			local distance = math.sqrt(distanceSquared)
			local nx, ns = 0, -1
			if distance > 0.01 then
				nx, ns = dx / distance, ds / distance
			end
			racer.X = bumper.X + nx * reach
			racer.S = bumper.S + ns * reach
			bounce(racer, nx, ns, BUMPER_BOUNCE, BUMPER_KICK)
		end
	end

	-- Barrier blocks: bounce off whichever face you hit.
	for _, barrier in self.Barriers do
		local nearestX = math.clamp(racer.X, barrier.X0, barrier.X1)
		local nearestS = math.clamp(racer.S, barrier.S0, barrier.S1)
		local dx, ds = racer.X - nearestX, racer.S - nearestS
		local distanceSquared = dx * dx + ds * ds
		if distanceSquared < RACER_RADIUS * RACER_RADIUS then
			local distance = math.sqrt(distanceSquared)
			local nx, ns
			if distance > 0.01 then
				nx, ns = dx / distance, ds / distance
			else
				nx, ns = 0, -1 -- somehow inside: shove back the way you came
			end
			racer.X = nearestX + nx * RACER_RADIUS
			racer.S = nearestS + ns * RACER_RADIUS
			bounce(racer, nx, ns, WALL_BOUNCE, 0)
		end
	end
	racer.VS = math.max(racer.VS, -MAX_SPEED * 0.6)
	racer.S = math.max(racer.S, 1)

	-- Edges: a wall bounces you back; no wall means a long drop.
	local limit = HALF_WIDTH - RACER_RADIUS
	if math.abs(racer.X) > limit then
		if self:_hasWall(racer.S) then
			local side = math.sign(racer.X)
			racer.X = side * limit
			if racer.VX * side > 0 then
				racer.VX = -racer.VX * WALL_BOUNCE
			end
		elseif math.abs(racer.X) > HALF_WIDTH + 0.5 then
			racer.State = "Falling"
			racer.FallTime = 0
			self.Round:Toast(("❄ %s slid off the edge"):format(participant.Name))
			return
		end
	end

	for _, checkpoint in self.Checkpoints do
		if racer.S >= checkpoint and racer.Checkpoint < checkpoint then
			racer.Checkpoint = checkpoint
		end
	end

	if racer.S >= TRACK_LENGTH then
		racer.State = "Finished"
		racer.FinishTime = elapsed
		self.FinishCount += 1
		self.Round:Toast(("🏁 %s finished in %.1fs"):format(participant.Name, elapsed))
		self.Round:ReportProgress(participant, self:_progressText(racer))
	end
end

-- Racers are solid to each other: overlapping pairs are pushed apart and trade momentum.
function IceDash:_collideRacers(alive)
	local reach = RACER_RADIUS * 2
	for i = 1, #alive do
		local a = self.Racers[alive[i]]
		for j = i + 1, #alive do
			local b = self.Racers[alive[j]]
			if a.State == "Racing" and b.State == "Racing" then
				local dx, ds = b.X - a.X, b.S - a.S
				local distanceSquared = dx * dx + ds * ds
				if distanceSquared < reach * reach then
					local distance = math.sqrt(distanceSquared)
					local nx, ns = 1, 0
					if distance > 0.01 then
						nx, ns = dx / distance, ds / distance
					end
					local overlap = (reach - distance) / 2
					a.X -= nx * overlap
					a.S -= ns * overlap
					b.X += nx * overlap
					b.S += ns * overlap
					-- Equal masses: swap (most of) the speed along the line between them.
					local closing = (a.VX - b.VX) * nx + (a.VS - b.VS) * ns
					if closing > 0 then
						local impulse = closing * (1 + RACER_BOUNCE) / 2
						a.VX -= impulse * nx
						a.VS -= impulse * ns
						b.VX += impulse * nx
						b.VS += impulse * ns
					end
				end
			end
		end
	end
end

-- Puts the character where the simulation says it is, leaning into the slide.
function IceDash:_place(participant, racer)
	local character = participant:GetCharacter()
	if not character then
		return
	end
	local drop = if racer.State == "Falling" then math.min(18, 40 * racer.FallTime * racer.FallTime) else 0
	-- Lean sideways into the slide. No turning: the chase camera follows the way the body
	-- faces, and it should keep looking straight down the track.
	local lean = math.clamp(racer.VX / MAX_SIDE_SPEED, -1, 1) * 0.3
	character:PivotTo(self:_at(racer.X, racer.RideHeight - drop, racer.S) * CFrame.Angles(0, 0, -lean))
end

function IceDash:_progressText(racer): string
	if racer.FinishTime then
		return ("🏁 %.1fs"):format(racer.FinishTime)
	end
	return ("%d%%"):format(math.clamp(racer.S / TRACK_LENGTH, 0, 0.99) * 100)
end

-- Interface -----------------------------------------------------------------------------

function IceDash:Start()
	local round = self.Round
	local startedAt = os.clock()
	local nextReport = 0

	-- Take over the bodies: anchored, and moved by the simulation from here on.
	for _, participant in self.Participants do
		local racer = self.Racers[participant]
		local character = participant:GetCharacter()
		local root = participant:GetRoot()
		if character and root then
			racer.RideHeight = self.Frame:PointToObjectSpace(character:GetPivot().Position).Y
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			table.insert(self.Anchored, root)
		end
	end
	round:SetStatus("Steer! ◀ ▶")

	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function(dt)
			if round.Ended then
				return
			end
			dt = math.min(dt, 0.05)
			local clock = os.clock()
			local elapsed = clock - startedAt
			local alive = round:GetAlive()
			for _, participant in alive do
				self:_step(participant, self.Racers[participant], dt, elapsed)
			end
			self:_collideRacers(alive)
			for _, participant in alive do
				self:_place(participant, self.Racers[participant])
			end

			if clock >= nextReport then
				nextReport = clock + 0.1
				for _, participant in self.Participants do
					round:ReportProgress(participant, self:_progressText(self.Racers[participant]))
				end
			end

			if self.FinishCount >= #round:GetAlive() then
				round:End("Finish")
			end
		end)
	)
end

function IceDash:OnInput(participant, action)
	local racer = self.Racers[participant]
	if not racer then
		return
	end
	if action == "Left" then
		racer.Left = true
	elseif action == "LeftStop" then
		racer.Left = false
	elseif action == "Right" then
		racer.Right = true
	elseif action == "RightStop" then
		racer.Right = false
	end
end

--[[
	Bot behaviour: look a little way down the track, score a handful of lines across it
	(bumpers and walls are terrible, snow and puddles are bad, the edge of an open stretch is
	scary), pick the cheapest and steer for it, allowing for drift. Sloppier bots look less
	far ahead, misjudge their drift, re-plan less often and sometimes just pick a bad line.
]]
function IceDash:_lineCost(me, x: number, fromS: number, toS: number): number
	local cost = 0
	local margin = RACER_RADIUS + 1.2
	-- Don't tuck in right behind (or drive into) another racer.
	for _, other in self.Racers do
		if other ~= me and other.State == "Racing" and other.S > fromS - 3 and other.S < fromS + 14 then
			if math.abs(x - other.X) < RACER_RADIUS * 2 + 0.5 then
				cost += 45
			end
		end
	end
	for _, bumper in self.Bumpers do
		if bumper.S > fromS and bumper.S < toS and math.abs(x - bumper.X) < BUMPER_RADIUS + margin then
			cost += 120
		end
	end
	for _, barrier in self.Barriers do
		if barrier.S1 > fromS and barrier.S0 < toS and x > barrier.X0 - margin and x < barrier.X1 + margin then
			cost += 150
		end
	end
	for _, snow in self.Snow do
		if snow.S > fromS - 4 and snow.S < toS and math.abs(x - snow.X) < SNOW_SIZE.X / 2 + 1 then
			cost += 35
		end
	end
	for _, puddle in self.Puddles do
		if puddle.S > fromS - 4 and puddle.S < toS and math.abs(x - puddle.X) < PUDDLE_RADIUS + 1 then
			cost += 28
		end
	end
	for _, open in self.Open do
		if open.S1 > fromS and open.S0 < toS and math.abs(x) > HALF_WIDTH - 6 then
			cost += 70
		end
	end
	return cost
end

function IceDash:UpdateBot(bot, _dt)
	local racer = self.Racers[bot.Participant]
	if not racer or racer.State ~= "Racing" then
		return
	end
	local memory = bot.Memory
	local clock = os.clock()

	if clock >= (memory.PlanAt or 0) then
		memory.PlanAt = clock + 0.2 + (1 - bot.Skill) * 0.45
		local lookAhead = 24 + bot.Skill * 30
		if math.random() < (1 - bot.Skill) * 0.07 then
			-- Brain fart: commit to a random line for a moment.
			memory.TargetX = (math.random() - 0.5) * (TRACK_WIDTH - 6)
			memory.PlanAt = clock + 0.7
		else
			local best, bestCost = racer.X, math.huge
			for x = -HALF_WIDTH + 3, HALF_WIDTH - 3, 3 do
				local cost = self:_lineCost(racer, x, racer.S + 1, racer.S + lookAhead)
					+ math.abs(x - racer.X) * 0.7 -- don't cross the whole track for nothing
					+ math.abs(x) * 0.2 -- the middle leaves the most options
					+ math.random() * (1 - bot.Skill) * 25 -- sloppy judgement
				if cost < bestCost then
					best, bestCost = x, cost
				end
			end
			memory.TargetX = best
		end
	end

	-- Steer for the line, allowing for how far the current drift will carry me.
	local anticipation = 0.15 + bot.Skill * 0.45
	local miss = (memory.TargetX or racer.X) - (racer.X + racer.VX * anticipation)
	local wantLeft, wantRight = miss < -1.3, miss > 1.3
	if wantLeft ~= memory.Left then
		memory.Left = wantLeft
		bot:Input(if wantLeft then "Left" else "LeftStop")
	end
	if wantRight ~= memory.Right then
		memory.Right = wantRight
		bot:Input(if wantRight then "Right" else "RightStop")
	end
end

function IceDash:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		local racer = self.Racers[participant]
		-- Finishers beat everyone still on the track; earlier finish = better.
		return if racer.FinishTime then 1e6 - racer.FinishTime else racer.S
	end)
end

function IceDash:Cleanup()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, root in self.Anchored do
		if root.Parent then
			root.Anchored = false
		end
	end
	-- The track lives in arena.Folder, which the framework destroys.
end

return IceDash
