--[[
	Ice Dash (FFA, race)
	Everyone slides forward down a frozen track on their own; you only steer left and right.
	It's ice, so you drift: momentum carries you sideways after you let go. Snow drifts and
	puddles slow you, bumpers and walls bounce you, and some stretches have no side walls -
	slide off and you restart from the last checkpoint.
	First over the finish line wins. Everyone else is ranked by how far they got.

	Who simulates what (so it stays smooth on a laggy connection):
	  * Each player's client runs its own racer with the shared rules in PartyShared.IceDashSim
	    (see client/Minigames/IceDash) and reports its state ~20 times a second.
	  * The server checks every report (see _validateReport) and only then adopts it. It works
	    out checkpoints, falls and the finish itself, so finish order can't be faked.
	  * Bots are simulated here with the same rules.
	  * The server broadcasts everyone's accepted state ~20 times a second; clients draw the
	    other racers by interpolating between those snapshots.

	Physics and track tuning live at the top of PartyShared.IceDashSim (shared with the
	client). Network and anti-cheat tuning is below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local Sim = require(ReplicatedStorage.PartyShared.IceDashSim)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local IceDash = {}

-- Tuning ----------------------------------------------------------------------------------

local ROUND_DURATION = 40

-- Networking
local SNAPSHOT_RATE = 20 -- snapshots of every racer sent to clients per second
local FALLBACK_PLACE_RATE = 2 -- times per second the server itself moves the bodies (for late joiners)
local MAX_REPORT_AGE = 0.25 -- seconds a player's last report is projected forward in snapshots

-- Anti-cheat: how far a client's report may stray from what the rules allow before it is
-- thrown away and the client is snapped back to the last accepted state.
local CLOCK_SLACK = 0.35 -- seconds a client's race clock may run ahead of the server's
local SPEED_TOLERANCE = 1.08 -- sustained forward speed allowed, as a multiple of MAX_SPEED
local SPEED_BURST = 14 -- studs of extra forward travel allowed in a burst (bumper kicks, bounces)
local STEP_SLACK = 3 -- studs of slack on any single report's movement
local WALL_SLACK = 1 -- studs a report may poke past a wall or into a barrier
local RESPAWN_GRACE = 1.5 -- extra seconds a client gets to reappear at its checkpoint after falling

-- Start/checkpoint/finish arches. Tall enough that the chase camera (Height 12) passes
-- under the beam instead of having it fill the top of the screen after you finish.
local GATE_HEIGHT = 20

IceDash.Info = {
	Name = "Ice Dash",
	Description = "Slide down the ice ❄! You move on your own, so just steer. Dodge bumpers and snow, don't slip off the edge. First to the flag wins!",
	Duration = ROUND_DURATION,
	Layout = Config.Layouts.FFA,
	Camera = { Mode = "FollowBehind", Height = 12, Distance = 22, Smooth = 12 },
	Controls = {
		Move = false, -- you slide on your own; you only steer
		Jump = false,
		Actions = {
			{ Action = "Left", Label = "◀", Keys = { "A", "Left" }, Gamepad = "DPadLeft", Hold = true, Side = "Left" },
			{ Action = "Right", Label = "▶", Keys = { "D", "Right" }, Gamepad = "DPadRight", Hold = true },
		},
	},
	ProgressLabel = "Progress",
	ProgressBar = true,
	ClientModule = "IceDash", -- client/Minigames/IceDash runs the local racer and smooths the others
}

local HALF_WIDTH = Sim.HALF_WIDTH
local TRACK_LENGTH = Sim.TRACK_LENGTH

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

-- Track space -> world. x = sideways (+ is the racer's right), s = distance from the start line.
function IceDash:_at(x: number, y: number, s: number): CFrame
	return self.Frame * CFrame.new(x, y, -s)
end

-- Turns the layout (plain numbers from IceDashSim) into parts.
function IceDash:_buildTrack(layout)
	local width = Sim.TRACK_WIDTH
	local total = TRACK_LENGTH + 60
	self:_part({
		Name = "Ice",
		Size = Vector3.new(width, 1, total),
		CFrame = self:_at(0, 0, total / 2 - 10),
		Material = Enum.Material.Ice,
		Color = Color3.fromRGB(190, 235, 255),
		CanCollide = true,
	})

	for _, snow in layout.Snow do
		self:_part({
			Name = "SnowDrift",
			Size = Vector3.new(Sim.SNOW_SIZE.X, 0.8, Sim.SNOW_SIZE.Y),
			CFrame = self:_at(snow.X, 0.7, snow.S),
			Color = Color3.fromRGB(255, 255, 255),
		})
	end
	for _, puddle in layout.Puddles do
		self:_part({
			Name = "Puddle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, Sim.PUDDLE_RADIUS * 2, Sim.PUDDLE_RADIUS * 2),
			CFrame = self:_at(puddle.X, 0.56, puddle.S) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(40, 110, 220),
			Transparency = 0.25,
		})
	end
	for _, bumper in layout.Bumpers do
		self:_part({
			Name = "Bumper",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, Sim.BUMPER_RADIUS * 2, Sim.BUMPER_RADIUS * 2),
			CFrame = self:_at(bumper.X, 2, bumper.S) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 80, 140),
		})
	end
	for _, barrier in layout.Barriers do
		self:_part({
			Name = "Barrier",
			Size = Vector3.new(barrier.X1 - barrier.X0, 4, barrier.S1 - barrier.S0),
			CFrame = self:_at((barrier.X0 + barrier.X1) / 2, 2.5, (barrier.S0 + barrier.S1) / 2),
			Material = Enum.Material.Brick,
			Color = Color3.fromRGB(255, 170, 60),
		})
	end

	-- Side walls everywhere except the open stretches, which get a red warning stripe.
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
	local wallStart = -10
	for _, open in layout.Open do
		wall(wallStart, open.S0)
		wallStart = open.S1
		for _, side in { -1, 1 } do
			self:_part({
				Name = "EdgeWarning",
				Size = Vector3.new(2, 0.2, open.S1 - open.S0),
				CFrame = self:_at(side * (HALF_WIDTH - 1), 0.56, (open.S0 + open.S1) / 2),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 60, 60),
			})
		end
	end
	wall(wallStart, TRACK_LENGTH + 50)

	-- Start line, checkpoints and the finish arch.
	local function gate(at: number, color: Color3, name: string)
		self:_part({
			Name = name,
			Size = Vector3.new(width, 0.2, 2),
			CFrame = self:_at(0, 0.58, at),
			Material = Enum.Material.Neon,
			Color = color,
		})
		for _, side in { -1, 1 } do
			self:_part({
				Name = name .. "Post",
				Size = Vector3.new(1.5, GATE_HEIGHT, 1.5),
				CFrame = self:_at(side * (HALF_WIDTH + 0.75), GATE_HEIGHT / 2 + 0.5, at),
				Material = Enum.Material.Neon,
				Color = color,
			})
		end
		self:_part({
			Name = name .. "Beam",
			Size = Vector3.new(width + 3, 1.5, 1.5),
			CFrame = self:_at(0, GATE_HEIGHT + 0.5, at),
			Material = Enum.Material.Neon,
			Color = color,
		})
	end
	gate(0, Color3.fromRGB(255, 255, 255), "StartLine")
	for _, checkpoint in layout.Checkpoints do
		gate(checkpoint, Color3.fromRGB(90, 255, 140), "Checkpoint")
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
	self.Layout = Sim.generateLayout(round.Rng)
	self:_buildTrack(self.Layout)

	local spawns = {}
	for index, participant in participants do
		local lane = Sim.START_LANES[(index - 1) % #Sim.START_LANES + 1]
		local racer = Sim.newRacer(lane)
		racer.IsBot = participant.IsBot
		racer.Left = false -- bots only: held steer buttons
		racer.Right = false
		racer.RideHeight = 3.5
		racer.FinishTime = nil
		-- Players only: bookkeeping for checking their reports.
		racer.ClientTime = 0
		racer.Budget = SPEED_BURST
		racer.FellAt = 0
		racer.Violations = 0
		self.Racers[participant] = racer
		spawns[index] = self:_at(lane, 4, Sim.START_S)
	end
	return spawns
end

-- Racing --------------------------------------------------------------------------------------

function IceDash:_progressText(racer): string
	if racer.FinishTime then
		return ("🏁 %.1fs"):format(racer.FinishTime)
	end
	return ("%d%%"):format(math.clamp(racer.S / TRACK_LENGTH, 0, 0.99) * 100)
end

function IceDash:_finish(participant, racer)
	racer.State = "Finished"
	racer.FinishTime = os.clock() - self.StartedAt
	self.FinishCount += 1
	self.Round:Toast(("🏁 %s finished in %.1fs"):format(participant.Name, racer.FinishTime))
	self.Round:ReportProgress(participant, self:_progressText(racer))
end

-- Puts the body where the server believes the racer is.
function IceDash:_place(participant, racer)
	local character = participant:GetCharacter()
	if character then
		local lean = math.clamp(racer.VX / Sim.MAX_SIDE_SPEED, -1, 1) * 0.3
		character:PivotTo(
			self:_at(racer.X, racer.RideHeight - Sim.fallDrop(racer), racer.S) * CFrame.Angles(0, 0, -lean)
		)
	end
end

-- Tells one client to drop its own idea of where it is and use the server's.
function IceDash:_correct(participant, racer)
	Net.minigameRemote():FireClient(participant.Player, {
		Type = "Correct",
		X = racer.X,
		S = racer.S,
		VX = racer.VX,
		VS = racer.VS,
		State = racer.State,
		Checkpoint = racer.Checkpoint,
	})
end

--[[
	A player's client says "I am here, moving like this". Decide whether the rules allow that
	given the last accepted state. Returns nil if fine, or a short reason if not.
]]
function IceDash:_checkReport(racer, x: number, s: number, vx: number, vs: number, dt: number): string?
	local layout = self.Layout
	-- One report can't move further than top speed (plus a bounce) allows.
	if math.abs(s - racer.S) > (Sim.MAX_SPEED + Sim.BUMPER_KICK) * dt + STEP_SLACK then
		return "jump"
	end
	if math.abs(x - racer.X) > (Sim.MAX_SIDE_SPEED + Sim.BUMPER_KICK) * dt + STEP_SLACK then
		return "sidejump"
	end
	if math.abs(vx) > Sim.MAX_SIDE_SPEED + Sim.BUMPER_KICK + 1 or vs > Sim.MAX_SPEED + Sim.BUMPER_KICK + 1 then
		return "velocity"
	end
	-- Sustained speed: forward travel is paid for out of a budget that refills at top speed.
	local budget = math.min(SPEED_BURST, racer.Budget + Sim.MAX_SPEED * SPEED_TOLERANCE * dt)
	if s > racer.S then
		budget -= s - racer.S
	end
	if budget < 0 then
		return "speed"
	end
	-- Solid things stay solid.
	if Sim.hasWall(layout, s) and math.abs(x) > HALF_WIDTH - Sim.RACER_RADIUS + WALL_SLACK then
		return "wall"
	end
	for _, barrier in layout.Barriers do
		if
			x > barrier.X0 + WALL_SLACK
			and x < barrier.X1 - WALL_SLACK
			and s > barrier.S0 + WALL_SLACK * 0.5
			and s < barrier.S1 - WALL_SLACK * 0.5
		then
			return "barrier"
		end
	end
	for _, bumper in layout.Bumpers do
		local dx, ds = x - bumper.X, s - bumper.S
		if dx * dx + ds * ds < (Sim.BUMPER_RADIUS * 0.5) ^ 2 then
			return "bumper"
		end
	end
	racer.Budget = budget
	return nil
end

function IceDash:_validateReport(participant, racer, message)
	local t, x, s, vx, vs = message.T, message.X, message.S, message.VX, message.VS
	for _, value in { t, x, s, vx, vs } do
		if type(value) ~= "number" or value ~= value or math.abs(value) > 1e5 then
			return
		end
	end
	if racer.State == "Finished" or self.Round.Ended or not self.StartedAt then
		return
	end
	local elapsed = os.clock() - self.StartedAt
	-- The client's race clock can't run ahead of real time (that would be a speed hack), and
	-- reports can arrive out of order on the unreliable channel: drop stale ones.
	if t <= racer.ClientTime then
		return
	end
	if t > elapsed + CLOCK_SLACK then
		racer.Violations += 1
		racer.LastProblem = "clock"
		self:_correct(participant, racer)
		return
	end
	local dt = math.min(t - racer.ClientTime, 0.5)
	racer.ClientTime = t

	if racer.State == "Falling" then
		-- The only way back is the checkpoint the server has on record.
		if math.abs(s - racer.Checkpoint) < 3 and math.abs(x - racer.Lane) < 3 then
			Sim.respawn(racer)
			racer.Budget = SPEED_BURST
		elseif os.clock() - racer.FellAt > Sim.RESPAWN_DELAY + RESPAWN_GRACE then
			Sim.respawn(racer)
			racer.Budget = SPEED_BURST
			self:_correct(participant, racer)
		else
			racer.FallTime = os.clock() - racer.FellAt
			racer.X = math.clamp(x, -HALF_WIDTH - 20, HALF_WIDTH + 20)
		end
		return
	end

	local problem = self:_checkReport(racer, x, s, vx, vs, dt)
	if problem then
		racer.Violations += 1
		racer.LastProblem = problem
		self:_correct(participant, racer)
		return
	end
	racer.X, racer.S, racer.VX, racer.VS = x, s, vx, vs
	racer.AcceptedAt = os.clock()

	-- Checkpoints, falls and the finish are decided here, from accepted positions only.
	racer.Checkpoint = math.max(racer.Checkpoint, Sim.checkpointFor(self.Layout, s))
	if not Sim.hasWall(self.Layout, s) and math.abs(x) > HALF_WIDTH + 0.5 then
		racer.State = "Falling"
		racer.FallTime = 0
		racer.FellAt = os.clock()
		self.Round:Toast(("❄ %s slid off the edge"):format(participant.Name))
	elseif s >= TRACK_LENGTH then
		self:_finish(participant, racer)
	end
end

-- Interface -----------------------------------------------------------------------------

function IceDash:Start()
	local round = self.Round
	self.StartedAt = os.clock()
	local nextReport, nextSnapshot, nextPlace = 0, 0, 0

	-- Take over the bodies: anchored for the whole race. Clients position them every frame
	-- (their own racer from local simulation, everyone else from snapshots).
	local describe = {}
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
		table.insert(describe, {
			Id = participant.Id,
			Character = character,
			Lane = racer.Lane,
			RideHeight = racer.RideHeight,
		})
	end
	Net.minigameRemote():FireAllClients({
		Type = "Setup",
		Layout = self.Layout,
		Frame = self.Frame,
		Racers = describe,
	})
	round:SetStatus("Steer! ◀ ▶")

	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function(dt)
			if round.Ended then
				return
			end
			dt = math.min(dt, 0.05)
			local clock = os.clock()
			local alive = round:GetAlive()

			-- Bots run the shared rules here. Players are driven by their own reports.
			for _, participant in alive do
				local racer = self.Racers[participant]
				if racer.IsBot then
					local steer = (if racer.Right then 1 else 0) - (if racer.Left then 1 else 0)
					local event = Sim.step(self.Layout, racer, steer, dt)
					if event == "fell" then
						round:Toast(("❄ %s slid off the edge"):format(participant.Name))
					elseif event == "finished" then
						self:_finish(participant, racer)
					end
				elseif racer.State == "Falling" then
					racer.FallTime = clock - racer.FellAt
				end
			end
			-- Bots bump into everyone; a player's own client handles the player's half.
			for i = 1, #alive do
				local a = self.Racers[alive[i]]
				for j = i + 1, #alive do
					local b = self.Racers[alive[j]]
					if a.IsBot or b.IsBot then
						Sim.collide(a, b, a.IsBot, b.IsBot)
					end
				end
			end

			if clock >= nextSnapshot then
				nextSnapshot = clock + 1 / SNAPSHOT_RATE
				local racers = {}
				for _, participant in self.Participants do
					local racer = self.Racers[participant]
					local x, s = racer.X, racer.S
					if not racer.IsBot and racer.State == "Racing" and racer.AcceptedAt then
						-- A player's report is a little old by now: project it to this instant,
						-- so everyone else sees steady motion instead of stair-steps.
						local age = math.min(clock - racer.AcceptedAt, MAX_REPORT_AGE)
						x += racer.VX * age
						s += racer.VS * age
					end
					table.insert(racers, {
						participant.Id,
						x,
						s,
						racer.VX,
						racer.VS,
						if racer.State == "Falling" then racer.FallTime else -1,
					})
				end
				Net.minigameFastRemote():FireAllClients({ T = clock, R = racers })
			end

			if clock >= nextPlace then
				nextPlace = clock + 1 / FALLBACK_PLACE_RATE
				for _, participant in alive do
					self:_place(participant, self.Racers[participant])
				end
			end

			if clock >= nextReport then
				nextReport = clock + 0.1
				for _, participant in self.Participants do
					round:ReportProgress(participant, self:_progressText(self.Racers[participant]))
				end
			end

			if self.FinishCount >= #alive then
				round:End("Finish")
			end
		end)
	)
end

-- Bots steer through the normal input path. Players steer on their own client.
function IceDash:OnInput(participant, action)
	local racer = self.Racers[participant]
	if not racer or not racer.IsBot then
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

-- A state report from a player's client (see client/Minigames/IceDash).
function IceDash:OnClientMessage(participant, message)
	local racer = self.Racers[participant]
	if racer and not racer.IsBot and type(message) == "table" then
		self:_validateReport(participant, racer, message)
	end
end

-- The round is over: put every body where the server has it, for everyone.
function IceDash:OnRoundEnding(_reason)
	for _, participant in self.Participants do
		local racer = self.Racers[participant]
		self:_place(participant, racer)
		if racer.Violations > 0 then
			print(
				("[IceDash] %s: %d report(s) rejected (last: %s)"):format(
					participant.Name,
					racer.Violations,
					tostring(racer.LastProblem)
				)
			)
		end
	end
end

--[[
	Bot behaviour: look a little way down the track, score a handful of lines across it
	(bumpers and walls are terrible, snow and puddles are bad, the edge of an open stretch is
	scary), pick the cheapest and steer for it, allowing for drift. Sloppier bots look less
	far ahead, misjudge their drift, re-plan less often and sometimes just pick a bad line.
]]
function IceDash:_lineCost(me, x: number, fromS: number, toS: number): number
	local layout = self.Layout
	local cost = 0
	local margin = Sim.RACER_RADIUS + 1.2
	-- Don't tuck in right behind (or drive into) another racer.
	for _, other in self.Racers do
		if other ~= me and other.State == "Racing" and other.S > fromS - 3 and other.S < fromS + 14 then
			if math.abs(x - other.X) < Sim.RACER_RADIUS * 2 + 0.5 then
				cost += 45
			end
		end
	end
	for _, bumper in layout.Bumpers do
		if bumper.S > fromS and bumper.S < toS and math.abs(x - bumper.X) < Sim.BUMPER_RADIUS + margin then
			cost += 120
		end
	end
	for _, barrier in layout.Barriers do
		if barrier.S1 > fromS and barrier.S0 < toS and x > barrier.X0 - margin and x < barrier.X1 + margin then
			cost += 150
		end
	end
	for _, snow in layout.Snow do
		if snow.S > fromS - 4 and snow.S < toS and math.abs(x - snow.X) < Sim.SNOW_SIZE.X / 2 + 1 then
			cost += 35
		end
	end
	for _, puddle in layout.Puddles do
		if puddle.S > fromS - 4 and puddle.S < toS and math.abs(x - puddle.X) < Sim.PUDDLE_RADIUS + 1 then
			cost += 28
		end
	end
	for _, open in layout.Open do
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
			memory.TargetX = (math.random() - 0.5) * (Sim.TRACK_WIDTH - 6)
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
