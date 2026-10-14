--[[
	IceDashSim
	The Ice Dash track layout and sliding physics, shared by server and client so both run
	exactly the same rules:

	  * the server uses it to move bots and to know what a legal move looks like
	  * each client uses it to move its own racer instantly (no waiting on the network)

	Nothing in here touches Instances; it is plain numbers.

	Track space: X = sideways (+ is the racer's right), S = distance from the start line.
]]

local Sim = {}

-- Tuning ----------------------------------------------------------------------------------

-- Ice physics
Sim.MAX_SPEED = 34 -- forward speed cap (studs/s)
Sim.FORWARD_ACCEL = 16 -- how quickly you get back up to speed
Sim.STEER_ACCEL = 42 -- sideways push while a steer button is held (studs/s^2)
Sim.ICE_FRICTION = 1.3 -- sideways speed lost per second (fraction); lower = more drift
Sim.MAX_SIDE_SPEED = 18
Sim.SLOW_DRAG = 4 -- how hard a snow drift / puddle pulls you down to its speed cap

-- Obstacles
Sim.SNOW_SLOW = 0.45 -- speed cap multiplier inside a snow drift
Sim.PUDDLE_SLOW = 0.65 -- speed cap multiplier inside a puddle
Sim.PUDDLE_STEER = 0.3 -- steering multiplier inside a puddle (you aquaplane)
Sim.BUMPER_BOUNCE = 0.9 -- bounciness of a bumper hit (0 = dead stop, 1 = perfect bounce)
Sim.BUMPER_KICK = 14 -- extra speed a bumper adds along the bounce direction
Sim.WALL_BOUNCE = 0.6 -- bounciness of side walls and barrier blocks
Sim.RACER_BOUNCE = 0.7 -- bounciness when two racers slide into each other

-- Track layout
Sim.TRACK_LENGTH = 800
Sim.TRACK_WIDTH = 36
Sim.OBSTACLE_SPACING = 30 -- studs between obstacle rows
Sim.FIRST_OBSTACLE = 55 -- clear run-up after the start line
Sim.CHECKPOINT_SPACING = 160
Sim.RESPAWN_DELAY = 1.1 -- seconds between sliding off and reappearing at the checkpoint

Sim.RACER_RADIUS = 1.6
Sim.BUMPER_RADIUS = 2.6
Sim.SNOW_SIZE = Vector2.new(13, 11) -- width, length
Sim.PUDDLE_RADIUS = 5.5
Sim.START_LANES = { -9, -3, 3, 9 }
Sim.START_S = 3

Sim.HALF_WIDTH = Sim.TRACK_WIDTH / 2

-- Layout ------------------------------------------------------------------------------------

-- Random obstacle course. Plain tables only, so it can be sent to clients as-is.
function Sim.generateLayout(rng)
	local half = Sim.HALF_WIDTH
	local layout = {
		Snow = {}, -- { X, S } centres of slow rectangles
		Puddles = {}, -- { X, S }
		Bumpers = {}, -- { X, S }
		Barriers = {}, -- { X0, X1, S0, S1 }
		Open = {}, -- { S0, S1 } stretches with no side walls
		Checkpoints = {}, -- S of each checkpoint gate
	}
	local lanes = { -13, -8, -3, 3, 8, 13 }
	local s = Sim.FIRST_OBSTACLE
	while s < Sim.TRACK_LENGTH - 30 do
		local roll = rng:NextNumber()
		if roll < 0.24 then
			table.insert(layout.Snow, { X = rng:NextNumber(-half + 7, half - 7), S = s })
		elseif roll < 0.42 then
			table.insert(layout.Puddles, { X = rng:NextNumber(-half + 6, half - 6), S = s })
		elseif roll < 0.68 then
			-- Two bumpers in different lanes.
			local first = rng:NextInteger(1, #lanes)
			local second = (first + rng:NextInteger(2, 4) - 1) % #lanes + 1
			table.insert(layout.Bumpers, { X = lanes[first], S = s })
			table.insert(layout.Bumpers, { X = lanes[second], S = s })
		elseif roll < 0.84 then
			-- A wall block sticking out from one side, or sitting in the middle.
			local width = Sim.TRACK_WIDTH * rng:NextNumber(0.3, 0.42)
			local kind = rng:NextInteger(1, 3)
			local x0 = if kind == 1 then -half elseif kind == 2 then half - width else -width / 2
			table.insert(layout.Barriers, { X0 = x0, X1 = x0 + width, S0 = s - 1.5, S1 = s + 1.5 })
		else
			-- No side walls here, and a bumper in the middle to make it interesting.
			table.insert(layout.Open, { S0 = s - Sim.OBSTACLE_SPACING / 2, S1 = s + Sim.OBSTACLE_SPACING / 2 })
			table.insert(layout.Bumpers, { X = 0, S = s })
		end
		s += Sim.OBSTACLE_SPACING
	end
	local checkpoint = Sim.CHECKPOINT_SPACING
	while checkpoint < Sim.TRACK_LENGTH - 40 do
		table.insert(layout.Checkpoints, checkpoint)
		checkpoint += Sim.CHECKPOINT_SPACING
	end
	return layout
end

function Sim.hasWall(layout, s: number): boolean
	for _, open in layout.Open do
		if s >= open.S0 and s <= open.S1 then
			return false
		end
	end
	return true
end

-- Speed-cap and steering multipliers for whatever is under (x, s).
function Sim.surface(layout, x: number, s: number): (number, number)
	local slow, steer = 1, 1
	for _, snow in layout.Snow do
		if math.abs(x - snow.X) <= Sim.SNOW_SIZE.X / 2 and math.abs(s - snow.S) <= Sim.SNOW_SIZE.Y / 2 then
			slow = math.min(slow, Sim.SNOW_SLOW)
		end
	end
	for _, puddle in layout.Puddles do
		local dx, ds = x - puddle.X, s - puddle.S
		if dx * dx + ds * ds <= Sim.PUDDLE_RADIUS * Sim.PUDDLE_RADIUS then
			slow = math.min(slow, Sim.PUDDLE_SLOW)
			steer = math.min(steer, Sim.PUDDLE_STEER)
		end
	end
	return slow, steer
end

-- The furthest checkpoint at or before s (the start line counts).
function Sim.checkpointFor(layout, s: number): number
	local best = Sim.START_S
	for _, checkpoint in layout.Checkpoints do
		if s >= checkpoint then
			best = checkpoint
		end
	end
	return best
end

-- Racers -------------------------------------------------------------------------------------

function Sim.newRacer(lane: number)
	return {
		X = lane,
		S = Sim.START_S,
		VX = 0,
		VS = 0,
		Lane = lane,
		Checkpoint = Sim.START_S,
		State = "Racing", -- "Racing" | "Falling" | "Finished"
		FallTime = 0,
	}
end

function Sim.respawn(racer)
	racer.State = "Racing"
	racer.X = racer.Lane
	racer.S = racer.Checkpoint
	racer.VX = 0
	racer.VS = 0
	racer.FallTime = 0
end

-- How far a falling racer has dropped below the ice.
function Sim.fallDrop(racer): number
	return if racer.State == "Falling" then math.min(18, 40 * racer.FallTime * racer.FallTime) else 0
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

--[[
	Advances one racer by dt seconds. `steer` is -1 (left), 0 or 1 (right).
	Returns "fell", "respawned" or "finished" when that happened this step, otherwise nil.
]]
function Sim.step(layout, racer, steer: number, dt: number): string?
	local half = Sim.HALF_WIDTH
	if racer.State == "Falling" then
		racer.FallTime += dt
		racer.X += racer.VX * dt
		racer.S += racer.VS * dt * 0.5
		if racer.FallTime >= Sim.RESPAWN_DELAY then
			Sim.respawn(racer)
			return "respawned"
		end
		return nil
	end
	if racer.State == "Finished" then
		-- Glide to a stop in the run-off area.
		racer.VS *= math.exp(-2.5 * dt)
		racer.VX *= math.exp(-3 * dt)
		racer.X = math.clamp(racer.X + racer.VX * dt, -half + Sim.RACER_RADIUS, half - Sim.RACER_RADIUS)
		racer.S = math.min(racer.S + racer.VS * dt, Sim.TRACK_LENGTH + 40)
		return nil
	end

	local slow, steerGrip = Sim.surface(layout, racer.X, racer.S)

	-- Sideways: push from steering, a little friction, lots of drift.
	racer.VX += steer * Sim.STEER_ACCEL * steerGrip * dt
	racer.VX *= math.exp(-Sim.ICE_FRICTION * dt)
	racer.VX = math.clamp(racer.VX, -Sim.MAX_SIDE_SPEED, Sim.MAX_SIDE_SPEED)

	-- Forward: always accelerating up to the cap of the surface you're on.
	local cap = Sim.MAX_SPEED * slow
	if racer.VS < cap then
		racer.VS = math.min(cap, racer.VS + Sim.FORWARD_ACCEL * dt)
	else
		racer.VS = cap + (racer.VS - cap) * math.exp(-Sim.SLOW_DRAG * dt)
	end

	racer.X += racer.VX * dt
	racer.S += racer.VS * dt

	-- Bumpers: round, bouncy, and they kick.
	for _, bumper in layout.Bumpers do
		local dx, ds = racer.X - bumper.X, racer.S - bumper.S
		local reach = Sim.BUMPER_RADIUS + Sim.RACER_RADIUS
		local distanceSquared = dx * dx + ds * ds
		if distanceSquared < reach * reach then
			local distance = math.sqrt(distanceSquared)
			local nx, ns = 0, -1
			if distance > 0.01 then
				nx, ns = dx / distance, ds / distance
			end
			racer.X = bumper.X + nx * reach
			racer.S = bumper.S + ns * reach
			bounce(racer, nx, ns, Sim.BUMPER_BOUNCE, Sim.BUMPER_KICK)
		end
	end

	-- Barrier blocks: bounce off whichever face you hit.
	for _, barrier in layout.Barriers do
		local nearestX = math.clamp(racer.X, barrier.X0, barrier.X1)
		local nearestS = math.clamp(racer.S, barrier.S0, barrier.S1)
		local dx, ds = racer.X - nearestX, racer.S - nearestS
		local distanceSquared = dx * dx + ds * ds
		if distanceSquared < Sim.RACER_RADIUS * Sim.RACER_RADIUS then
			local distance = math.sqrt(distanceSquared)
			local nx, ns
			if distance > 0.01 then
				nx, ns = dx / distance, ds / distance
			else
				nx, ns = 0, -1 -- somehow inside: shove back the way you came
			end
			racer.X = nearestX + nx * Sim.RACER_RADIUS
			racer.S = nearestS + ns * Sim.RACER_RADIUS
			bounce(racer, nx, ns, Sim.WALL_BOUNCE, 0)
		end
	end
	racer.VS = math.max(racer.VS, -Sim.MAX_SPEED * 0.6)
	racer.S = math.max(racer.S, 1)

	-- Edges: a wall bounces you back; no wall means a long drop.
	local limit = half - Sim.RACER_RADIUS
	if math.abs(racer.X) > limit then
		if Sim.hasWall(layout, racer.S) then
			local side = math.sign(racer.X)
			racer.X = side * limit
			if racer.VX * side > 0 then
				racer.VX = -racer.VX * Sim.WALL_BOUNCE
			end
		elseif math.abs(racer.X) > half + 0.5 then
			racer.State = "Falling"
			racer.FallTime = 0
			return "fell"
		end
	end

	racer.Checkpoint = math.max(racer.Checkpoint, Sim.checkpointFor(layout, racer.S))

	if racer.S >= Sim.TRACK_LENGTH then
		racer.State = "Finished"
		return "finished"
	end
	return nil
end

--[[
	Racers are solid to each other. Pushes an overlapping pair apart and trades momentum.
	moveA / moveB say which of the two this machine is allowed to change (a client only moves
	its own racer; the server only moves bots).
]]
function Sim.collide(a, b, moveA: boolean, moveB: boolean)
	if a.State ~= "Racing" or b.State ~= "Racing" then
		return
	end
	local reach = Sim.RACER_RADIUS * 2
	local dx, ds = b.X - a.X, b.S - a.S
	local distanceSquared = dx * dx + ds * ds
	if distanceSquared >= reach * reach then
		return
	end
	local distance = math.sqrt(distanceSquared)
	local nx, ns = 1, 0
	if distance > 0.01 then
		nx, ns = dx / distance, ds / distance
	end
	local overlap = (reach - distance) / 2
	-- Equal masses: swap (most of) the speed along the line between them.
	local closing = (a.VX - (b.VX or 0)) * nx + (a.VS - (b.VS or 0)) * ns
	local impulse = if closing > 0 then closing * (1 + Sim.RACER_BOUNCE) / 2 else 0
	if moveA then
		a.X -= nx * overlap
		a.S -= ns * overlap
		a.VX -= impulse * nx
		a.VS -= impulse * ns
	end
	if moveB then
		b.X += nx * overlap
		b.S += ns * overlap
		b.VX += impulse * nx
		b.VS += impulse * ns
	end
end

return Sim
