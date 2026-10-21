--[[
	Trail Tangle (FFA, strategy / survival)
	Everyone rides across a grid one cell at a time, on their own, leaving a solid trail.
	You only turn left or right. Hit the edge, any trail (yours too), or move into the same
	cell as someone else in the same moment, and you're out. Last rider wins; if time runs
	out, the riders still going rank by cells claimed. It starts slow and speeds up, so it
	rewards planning ahead and cutting off space rather than fast fingers.

	Server-authoritative fixed-step grid simulation (the pure functions below the tuning are
	what the unit tests drive):
	  * Turns are requests: at most one is buffered per rider and it is applied on the next
	    tick. Turning is relative (left / right), so a rider can never reverse into its trail.
	  * Each tick every rider's next cell is worked out first, then all collisions are resolved
	    together (edge, trails, two riders entering one cell, swaps), then survivors move.
	  * Ticks run on a fixed schedule from the round clock, so frame rate never changes
	    outcomes. One small message per tick goes to clients (client/Minigames/TrailTangle),
	    which glide the riders between cells.
	Bots plan right after each tick through the same turn requests players make.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local TrailTangle = {}

-- Tuning ----------------------------------------------------------------------------------

TrailTangle.GRID_WIDTH = 26 -- cells
TrailTangle.GRID_HEIGHT = 26
TrailTangle.CELL_SIZE = 3 -- studs per cell
TrailTangle.START_INTERVAL = 0.32 -- seconds per step at the start (slow enough to learn)
TrailTangle.FINAL_INTERVAL = 0.13 -- seconds per step once fully sped up
TrailTangle.RAMP_START = 6 -- seconds before the pace starts rising
TrailTangle.RAMP_END = 28 -- seconds when it reaches FINAL_INTERVAL
TrailTangle.RAMP_CURVE = 1.3 -- >1: speeds up gently at first, harder later
TrailTangle.SPEED_WARNINGS = { 6, 14, 22 } -- seconds: "speeding up" toast when these pass
TrailTangle.TURN_COOLDOWN = 0.06 -- seconds: turn requests closer together than this are dropped
TrailTangle.ROUND_DURATION = 35
TrailTangle.MAX_CATCH_UP = 3 -- ticks run at most per frame after a server hitch
TrailTangle.TRAIL_HEIGHT = 1.2 -- studs; trail blocks the riders stand on

-- Bots (skill 0..1 blends from the first number to the second)
TrailTangle.BOT = {
	Reach = { 30, 220 }, -- open cells counted down each option (planning depth)
	Mistake = { 0.14, 0.01 }, -- chance per decision of a late or wrong reaction
	Aggression = { 0.1, 0.35 }, -- weight on claiming space before opponents can (cutting off)
	Caution = { 0.3, 1 }, -- how much a cell an opponent could also enter next step is feared
	Noise = { 10, 1 }, -- random judgement added to each option's score
	Pocket = 2.5, -- extra penalty per missing cell when an option leads into a small pocket
	Crowding = 15, -- penalty for steering within two cells of an opponent's head
}

TrailTangle.Info = {
	Name = "Trail Tangle",
	Description = "You ride on your own and leave a solid trail. Turn LEFT or RIGHT to dodge the edge and every trail. Trap the others; last rider wins! It speeds up, so plan ahead.",
	Duration = TrailTangle.ROUND_DURATION,
	Layout = Config.Layouts.FFA,
	Tutorial = {
		Objective = "Turn to dodge every trail and the edge.",
		Rule = "You ride on your own and leave a solid trail.",
		Win = "Last rider wins.",
		Controls = { { Label = "TURN", Actions = { "Left", "Right" } } },
		Preview = {
			Loop = 6,
			Camera = { Position = Vector3.new(0, 18, 12), LookAt = Vector3.new(0, 0, 0) },
			Actors = {
				{ Start = Vector3.new(-6, 0, 6), Face = Vector3.new(-6, 0, -10) },
				{ Start = Vector3.new(6, 0, -6), Face = Vector3.new(6, 0, 10) },
			},
			Props = {
				{ Id = "Grid", Shape = "Block", Size = Vector3.new(16, 1, 16), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(40, 52, 76) },
				{ Id = "TrailA", Shape = "Block", Size = Vector3.new(1, 0.4, 8), Position = Vector3.new(-6, 0.2, 2), Color = Color3.fromRGB(240, 198, 96), Neon = true, Hidden = true },
				{ Id = "TrailB", Shape = "Block", Size = Vector3.new(8, 0.4, 1), Position = Vector3.new(-2, 0.2, -2), Color = Color3.fromRGB(240, 198, 96), Neon = true, Hidden = true },
				{ Id = "TrailC", Shape = "Block", Size = Vector3.new(1, 0.4, 8), Position = Vector3.new(6, 0.2, -2), Color = Color3.fromRGB(120, 200, 255), Neon = true, Hidden = true },
				{ Id = "TrailD", Shape = "Block", Size = Vector3.new(7, 0.4, 1), Position = Vector3.new(2.5, 0.2, 2), Color = Color3.fromRGB(120, 200, 255), Neon = true, Hidden = true },
			},
			Steps = {
				{ At = 0.2, Actor = 1, To = Vector3.new(-6, 0, -2), Time = 1.4 },
				{ At = 0.2, Actor = 2, To = Vector3.new(6, 0, 2), Time = 1.4 },
				{ At = 1.0, Prop = "TrailA", Visible = true },
				{ At = 1.0, Prop = "TrailC", Visible = true },
				{ At = 1.7, Actor = 1, Caption = "RIGHT" },
				{ At = 1.7, Actor = 1, To = Vector3.new(2, 0, -2), Time = 1.4 },
				{ At = 1.7, Actor = 2, Caption = "LEFT" },
				{ At = 1.7, Actor = 2, To = Vector3.new(-1, 0, 2), Time = 1.4 },
				{ At = 2.6, Prop = "TrailB", Visible = true },
				{ At = 2.6, Prop = "TrailD", Visible = true },
				{ At = 3.6, Caption = "DON'T HIT A TRAIL" },
			},
		},
	},
	-- Steep, fixed view of the whole grid (no drift toward you). On phones it's a little
	-- closer and aimed further ahead, so the grid fills the gap between the chips and the
	-- bottom edge, between the LEFT and RIGHT buttons.
	Camera = {
		Mode = "AngledOverhead",
		Height = 92,
		Distance = 40,
		Follow = 0,
		Smooth = 20,
		TouchZoom = 0.92,
		TouchLookAhead = 12,
	},
	Controls = {
		Move = false,
		Jump = false,
		-- Hold = true only so on-screen buttons fire the moment a finger lands (the "...Stop"
		-- half is ignored); one press is one turn.
		Actions = {
			{ Action = "Left", Label = "LEFT", Keys = { "A", "Left" }, Gamepads = { "DPadLeft", "ButtonL1" }, Side = "Left", Hold = true },
			{ Action = "Right", Label = "RIGHT", Keys = { "D", "Right" }, Gamepads = { "DPadRight", "ButtonR1" }, Hold = true },
		},
	},
	ProgressLabel = "Cells",
	ClientModule = "TrailTangle", -- client/Minigames/TrailTangle glides the riders between cells
}

-- Grid simulation (pure) ------------------------------------------------------------------

-- Directions: 1 = north (-Y), 2 = east (+X), 3 = south (+Y), 4 = west (-X).
local DX = { 0, 1, 0, -1 }
local DY = { -1, 0, 1, 0 }
TrailTangle.DX, TrailTangle.DY = DX, DY

local function turned(dir: number, side: string): number
	return if side == "Right" then dir % 4 + 1 else (dir + 2) % 4 + 1
end
local function reverse(dir: number): number
	return (dir + 1) % 4 + 1
end
TrailTangle.turned = turned

-- A pinwheel: everyone starts the same distance from the edge, each heading for the
-- next one's corner, so nobody starts boxed in and the first turns come early.
function TrailTangle.startCells(width: number, height: number)
	local a, bx, by = 6, width - 7, height - 7
	return {
		{ X = a, Y = a, Dir = 2 },
		{ X = bx, Y = a, Dir = 3 },
		{ X = bx, Y = by, Dir = 4 },
		{ X = a, Y = by, Dir = 1 },
	}
end

function TrailTangle.newSim(count: number, width: number?, height: number?)
	local sim = {
		Width = width or TrailTangle.GRID_WIDTH,
		Height = height or TrailTangle.GRID_HEIGHT,
		Cells = {}, -- [index] = rider index that claimed it
		Riders = {},
		Tick = 0,
	}
	local starts = TrailTangle.startCells(sim.Width, sim.Height)
	for index = 1, count do
		local start = starts[(index - 1) % #starts + 1]
		local rider = {
			Index = index,
			X = start.X,
			Y = start.Y,
			Dir = start.Dir,
			Pending = nil, -- the one buffered turn (a direction), applied next tick
			Alive = true,
			Claimed = 1,
			EliminatedTick = nil,
			LastTurnAt = -math.huge,
		}
		sim.Riders[index] = rider
		sim.Cells[TrailTangle.cellIndex(sim, rider.X, rider.Y)] = index
	end
	return sim
end

function TrailTangle.cellIndex(sim, x: number, y: number): number
	return y * sim.Width + x + 1
end

function TrailTangle.inside(sim, x: number, y: number): boolean
	return x >= 0 and y >= 0 and x < sim.Width and y < sim.Height
end

function TrailTangle.isOpen(sim, x: number, y: number): boolean
	return TrailTangle.inside(sim, x, y) and sim.Cells[TrailTangle.cellIndex(sim, x, y)] == nil
end

--[[
	A turn request ("Left" / "Right") at time `now` (seconds). Returns ok, reason.
	Only one turn is buffered per tick; requests faster than TURN_COOLDOWN are dropped.
]]
function TrailTangle.requestTurn(sim, rider, side, now: number): (boolean, string?)
	if not rider or not rider.Alive then
		return false, "out"
	end
	if side ~= "Left" and side ~= "Right" then
		return false, "malformed"
	end
	if type(now) ~= "number" or now ~= now or now - rider.LastTurnAt < TrailTangle.TURN_COOLDOWN then
		return false, "too_fast"
	end
	if rider.Pending then
		return false, "buffered"
	end
	local dir = turned(rider.Dir, side)
	if dir == reverse(rider.Dir) then
		return false, "reverse" -- can't happen with relative turns; kept as a hard rule
	end
	rider.Pending = dir
	rider.LastTurnAt = now
	return true, nil
end

-- Removes a rider (left the game / body lost). Their trail stays.
function TrailTangle.knockOut(sim, rider)
	if rider.Alive then
		rider.Alive = false
		rider.EliminatedTick = sim.Tick
		rider.Pending = nil
	end
end

--[[
	One fixed step for everyone. All next cells are decided before anything moves, so the
	order riders are listed in never matters:
	  * off the grid, or into any trail cell (heads included) -> out
	  * two or more riders entering the same cell -> all of them out
	  * swapping cells is two riders entering each other's (already claimed) head -> both out
	Returns the riders knocked out this tick.
]]
function TrailTangle.step(sim)
	sim.Tick += 1
	local moves = {}
	local targets = {} -- [cell index] = number of riders heading there
	for _, rider in sim.Riders do
		if rider.Alive then
			if rider.Pending and rider.Pending ~= reverse(rider.Dir) then
				rider.Dir = rider.Pending
			end
			rider.Pending = nil
			local x, y = rider.X + DX[rider.Dir], rider.Y + DY[rider.Dir]
			local move = { Rider = rider, X = x, Y = y, Crash = not TrailTangle.isOpen(sim, x, y) }
			if TrailTangle.inside(sim, x, y) then
				move.Cell = TrailTangle.cellIndex(sim, x, y)
				targets[move.Cell] = (targets[move.Cell] or 0) + 1
			end
			table.insert(moves, move)
		end
	end
	local out = {}
	for _, move in moves do
		if move.Crash or (move.Cell and targets[move.Cell] > 1) then
			move.Rider.Alive = false
			move.Rider.EliminatedTick = sim.Tick
			table.insert(out, move.Rider)
		end
	end
	for _, move in moves do
		local rider = move.Rider
		if rider.Alive then
			rider.X, rider.Y = move.X, move.Y
			rider.Claimed += 1
			sim.Cells[move.Cell] = rider.Index
		end
	end
	return out
end

-- Seconds per step `elapsed` seconds into the round.
function TrailTangle.intervalAt(elapsed: number): number
	if elapsed <= TrailTangle.RAMP_START then
		return TrailTangle.START_INTERVAL
	end
	local alpha = math.clamp((elapsed - TrailTangle.RAMP_START) / (TrailTangle.RAMP_END - TrailTangle.RAMP_START), 0, 1)
	alpha ^= TrailTangle.RAMP_CURVE
	return TrailTangle.START_INTERVAL + (TrailTangle.FINAL_INTERVAL - TrailTangle.START_INTERVAL) * alpha
end

function TrailTangle.alive(sim)
	local list = {}
	for _, rider in sim.Riders do
		if rider.Alive then
			table.insert(list, rider)
		end
	end
	return list
end

-- Ranking score: later elimination is better (survivors best), then cells claimed.
function TrailTangle.score(sim, rider): number
	return (rider.EliminatedTick or (sim.Tick + 1)) * 100000 + rider.Claimed
end

-- Bot planning (pure) ---------------------------------------------------------------------

local function blend(pair, skill: number): number
	return pair[1] + (pair[2] - pair[1]) * skill
end

-- Open cells reachable from (x, y) (which counts as taken), up to `cap`.
function TrailTangle.openArea(sim, x: number, y: number, cap: number): number
	local seen = { [TrailTangle.cellIndex(sim, x, y)] = true }
	local queue, head, count = { x, y }, 1, 0
	while head < #queue and count < cap do
		local cx, cy = queue[head], queue[head + 1]
		head += 2
		for dir = 1, 4 do
			local nx, ny = cx + DX[dir], cy + DY[dir]
			if TrailTangle.isOpen(sim, nx, ny) then
				local index = TrailTangle.cellIndex(sim, nx, ny)
				if not seen[index] then
					seen[index] = true
					count += 1
					table.insert(queue, nx)
					table.insert(queue, ny)
				end
			end
		end
	end
	return count
end

-- Cells I could reach strictly before any opponent (starting from (x, y)) minus theirs.
local function territory(sim, me, x: number, y: number): number
	local owner, dist = {}, {}
	local queue = {}
	local function seed(cx, cy, who)
		local index = TrailTangle.cellIndex(sim, cx, cy)
		owner[index], dist[index] = who, 0
		table.insert(queue, { cx, cy, who, 0 })
	end
	seed(x, y, me.Index)
	for _, other in sim.Riders do
		if other ~= me and other.Alive then
			seed(other.X, other.Y, other.Index)
		end
	end
	local head = 1
	while head <= #queue do
		local cx, cy, who, d = table.unpack(queue[head])
		head += 1
		if owner[TrailTangle.cellIndex(sim, cx, cy)] ~= 0 then
			for dir = 1, 4 do
				local nx, ny = cx + DX[dir], cy + DY[dir]
				if TrailTangle.isOpen(sim, nx, ny) then
					local index = TrailTangle.cellIndex(sim, nx, ny)
					if dist[index] == nil then
						owner[index], dist[index] = who, d + 1
						table.insert(queue, { nx, ny, who, d + 1 })
					elseif dist[index] == d + 1 and owner[index] ~= who then
						owner[index] = 0 -- contested
					end
				end
			end
		end
	end
	local mine, theirs = 0, 0
	for _, who in owner do
		if who == me.Index then
			mine += 1
		elseif who ~= 0 then
			theirs += 1
		end
	end
	return mine - theirs / 3
end

--[[
	What a bot of `skill` (0..1) asks for this tick: "Left", "Right" or nil (straight on).
	It looks only at the visible grid: open space down each option (deeper with skill),
	small dead-end pockets, cells an opponent could enter at the same moment, and how much
	space it would claim before opponents (aggression). Sloppier bots look less far, judge
	noisily and sometimes react late or pick the second-best option (never a move that
	crashes on the spot: their mistakes show up as worse positions a few steps later).
]]
function TrailTangle.botChoice(sim, rider, skill: number, rng: Random)
	if not rider.Alive then
		return nil
	end
	local bot = TrailTangle.BOT
	local reach = math.floor(blend(bot.Reach, skill))
	local options, straight = {}, nil
	for _, side in { false, "Left", "Right" } do
		local dir = if side then turned(rider.Dir, side) else rider.Dir
		local x, y = rider.X + DX[dir], rider.Y + DY[dir]
		local score
		if not TrailTangle.isOpen(sim, x, y) then
			score = -1e9
		else
			local area = TrailTangle.openArea(sim, x, y, reach)
			score = area
			if area < reach then
				score -= (reach - area) * bot.Pocket -- walled-in pocket: avoid
			end
			for _, other in sim.Riders do
				if other ~= rider and other.Alive then
					local gap = math.abs(other.X - x) + math.abs(other.Y - y)
					if gap == 1 then
						score -= 40 * blend(bot.Caution, skill) -- they could take this cell too
					elseif gap == 2 then
						score -= bot.Crowding * blend(bot.Caution, skill) -- don't ride head to head
					end
				end
			end
			score += territory(sim, rider, x, y) * blend(bot.Aggression, skill) * 0.5
			score += rng:NextNumber() * blend(bot.Noise, skill)
			if not side then
				score += 0.5 -- no reason to wiggle
			end
		end
		local option = { Side = side, Score = score }
		straight = straight or option
		table.insert(options, option)
	end
	table.sort(options, function(a, b)
		return a.Score > b.Score
	end)
	local pick = options[1]
	if rng:NextNumber() < blend(bot.Mistake, skill) then
		-- A believable slip: react a step late (carry straight on) or take the runner-up. Never
		-- one that crashes on the spot; the cost shows up later as a worse position.
		local slip = if rng:NextNumber() < 0.5 then straight else options[2]
		if slip.Score > -1e9 then
			pick = slip
		end
	end
	return pick.Side or nil
end

-- Round ---------------------------------------------------------------------------------------

local COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(90, 225, 110),
	Color3.fromRGB(255, 205, 60),
}

-- Grid cell -> world (centre of the cell, on the floor's top surface).
function TrailTangle:_cellCFrame(x: number, y: number, height: number?): CFrame
	local cell = TrailTangle.CELL_SIZE
	local w, h = self.Sim.Width, self.Sim.Height
	return self.Arena.Origin * CFrame.new((x - (w - 1) / 2) * cell, height or 0, (y - (h - 1) / 2) * cell)
end

local function yawOf(dir: number): number
	-- CFrame looks down -Z: north (-Y on the grid, -Z in the world) is yaw 0.
	return ({ 0, -math.pi / 2, math.pi, math.pi / 2 })[dir]
end
TrailTangle.yawOf = yawOf

function TrailTangle:_part(properties)
	local part = Instance.new("Part")
	part.Anchored = true
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

function TrailTangle:_buildGrid()
	local cell = TrailTangle.CELL_SIZE
	local w, h = self.Sim.Width * cell, self.Sim.Height * cell
	self:_part({
		Name = "Floor",
		Size = Vector3.new(w, 1, h),
		CFrame = self.Arena.Origin * CFrame.new(0, -0.5, 0),
		Color = Color3.fromRGB(40, 44, 62),
	})
	-- Faint lines so the cells can be counted at a glance.
	for i = 0, self.Sim.Width do
		self:_part({
			Name = "GridLine",
			CanCollide = false,
			Size = Vector3.new(0.15, 0.05, h),
			CFrame = self.Arena.Origin * CFrame.new(i * cell - w / 2, 0.03, 0),
			Color = Color3.fromRGB(70, 76, 102),
		})
	end
	for i = 0, self.Sim.Height do
		self:_part({
			Name = "GridLine",
			CanCollide = false,
			Size = Vector3.new(w, 0.05, 0.15),
			CFrame = self.Arena.Origin * CFrame.new(0, 0.03, i * cell - h / 2),
			Color = Color3.fromRGB(70, 76, 102),
		})
	end
	-- The edge is deadly: a bright rim.
	for _, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local alongX = side[1] == 0
		self:_part({
			Name = "Edge",
			Material = Enum.Material.Neon,
			Size = if alongX then Vector3.new(w + 2, 2, 1) else Vector3.new(1, 2, h + 2),
			CFrame = self.Arena.Origin * CFrame.new(side[1] * (w / 2 + 0.5), 1, side[2] * (h / 2 + 0.5)),
			Color = Color3.fromRGB(255, 90, 160),
		})
	end
end

function TrailTangle:_trail(rider)
	local cell = TrailTangle.CELL_SIZE
	self:_part({
		Name = "Trail",
		Size = Vector3.new(cell - 0.25, TrailTangle.TRAIL_HEIGHT, cell - 0.25),
		CFrame = self:_cellCFrame(rider.X, rider.Y, TrailTangle.TRAIL_HEIGHT / 2),
		Color = COLORS[(rider.Index - 1) % #COLORS + 1],
	})
end

-- Height of a body's pivot (root) standing on a trail block.
function TrailTangle:_rideHeight(participant): number
	local humanoid = participant:GetHumanoid()
	local root = participant:GetRoot()
	local hip = if humanoid then humanoid.HipHeight else 2
	return TrailTangle.TRAIL_HEIGHT + hip + (if root then root.Size.Y / 2 else 1)
end

function TrailTangle:_place(participant)
	local rider = self.RiderOf[participant]
	local character = participant:GetCharacter()
	if rider and rider.Alive and character then
		character:PivotTo(self:_cellCFrame(rider.X, rider.Y, self.Heights[participant]) * CFrame.Angles(0, yawOf(rider.Dir), 0))
	end
end

function TrailTangle:Setup(arena, participants, _round)
	self.Connections = {}
	self.Anchored = {}
	self.Highlights = {}
	self.Heights = {}
	self.Sim = TrailTangle.newSim(#participants)
	self.RiderOf = {}
	self.ParticipantOf = {}
	self.BotRng = Random.new()
	self:_buildGrid()
	local spawns = {}
	for index, participant in participants do
		local rider = self.Sim.Riders[index]
		self.RiderOf[participant] = rider
		self.ParticipantOf[rider] = participant
		self:_trail(rider)
		self.Heights[participant] = self:_rideHeight(participant)
		spawns[index] = self:_cellCFrame(rider.X, rider.Y, self.Heights[participant] + 0.5)
			* CFrame.Angles(0, yawOf(rider.Dir), 0)
	end
	return spawns
end

function TrailTangle:_tickMessage(interval: number)
	local riders = {}
	for _, rider in self.Sim.Riders do
		table.insert(riders, { rider.X, rider.Y, rider.Dir, rider.Alive })
	end
	return { Type = "Tick", N = self.Sim.Tick, I = interval, R = riders }
end

function TrailTangle:_tick(elapsed: number)
	local sim = self.Sim
	local round = self.Round
	local out = TrailTangle.step(sim)
	for _, rider in sim.Riders do
		if rider.Alive then
			self:_trail(rider)
		end
	end
	for _, rider in out do
		local participant = self.ParticipantOf[rider]
		local root = participant:GetRoot()
		if root then
			root.Anchored = false
		end
		round:Eliminate(participant)
	end
	for participant, rider in self.RiderOf do
		round:ReportProgress(participant, rider.Claimed)
		self:_place(participant)
	end
	Net.minigameRemote():FireAllClients(self:_tickMessage(TrailTangle.intervalAt(elapsed)))

	local warning = TrailTangle.SPEED_WARNINGS[self.NextWarning]
	if warning and elapsed >= warning then
		self.NextWarning += 1
		round:Toast("⚡ Speeding up!")
	end

	local alive = TrailTangle.alive(sim)
	if #alive <= 1 and #sim.Riders > 1 then
		round:End(if #alive == 1 then "LastRider" else "AllOut")
		return
	end
	-- Bots decide for the next step now, through the same turn requests players make.
	for _, participant in self.Participants do
		if participant.IsBot and participant.Bot and self.RiderOf[participant].Alive then
			self:_botThink(participant.Bot)
		end
	end
end

function TrailTangle:_botThink(bot)
	local participant = bot.Participant
	local rider = participant and self.RiderOf[participant]
	if not rider or not rider.Alive or bot.Memory.Tick == self.Sim.Tick then
		return
	end
	bot.Memory.Tick = self.Sim.Tick
	local side = TrailTangle.botChoice(self.Sim, rider, bot.Skill or 0.5, self.BotRng)
	if side then
		bot:Input(side)
	end
end

function TrailTangle:Start()
	local round = self.Round
	self.StartedAt = os.clock()
	self.NextTickAt = TrailTangle.intervalAt(0)
	self.NextWarning = 1
	local describe = {}
	for _, participant in self.Participants do
		local rider = self.RiderOf[participant]
		local root = participant:GetRoot()
		local character = participant:GetCharacter()
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			table.insert(self.Anchored, root)
		end
		if character then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TrailTangleColor"
			highlight.FillColor = COLORS[(rider.Index - 1) % #COLORS + 1]
			highlight.FillTransparency = 0.45
			highlight.OutlineColor = Color3.new(1, 1, 1)
			highlight.Parent = character
			table.insert(self.Highlights, highlight)
		end
		self:_place(participant)
		round:ReportProgress(participant, rider.Claimed)
		table.insert(describe, {
			Id = participant.Id,
			Character = character,
			Height = self.Heights[participant],
			Color = COLORS[(rider.Index - 1) % #COLORS + 1],
		})
	end
	Net.minigameRemote():FireAllClients({
		Type = "Setup",
		Origin = self.Arena.Origin,
		Cell = TrailTangle.CELL_SIZE,
		Width = self.Sim.Width,
		Height = self.Sim.Height,
		Riders = describe,
	})
	Net.minigameRemote():FireAllClients(self:_tickMessage(TrailTangle.intervalAt(0)))
	round:SetStatus("Turn LEFT / RIGHT · don't hit any trail")
	for _, participant in self.Participants do
		if participant.IsBot and participant.Bot then
			self:_botThink(participant.Bot)
		end
	end

	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function()
			local catchUp = 0
			while not round.Ended and os.clock() - self.StartedAt >= self.NextTickAt and catchUp < TrailTangle.MAX_CATCH_UP do
				catchUp += 1
				local at = self.NextTickAt
				self:_tick(at)
				self.NextTickAt = at + TrailTangle.intervalAt(at)
			end
		end)
	)
end

function TrailTangle:OnInput(participant, action)
	local rider = self.RiderOf[participant]
	if rider and (action == "Left" or action == "Right") then
		TrailTangle.requestTurn(self.Sim, rider, action, os.clock())
	end
end

-- Backup brain on the framework's think loop (normally bots plan right after each tick).
function TrailTangle:UpdateBot(bot, _dt)
	if self.StartedAt then
		self:_botThink(bot)
	end
end

function TrailTangle:OnParticipantLost(participant, _reason)
	local rider = self.RiderOf[participant]
	if rider then
		TrailTangle.knockOut(self.Sim, rider)
		local root = participant:GetRoot()
		if root then
			root.Anchored = false
		end
	end
end

function TrailTangle:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		return TrailTangle.score(self.Sim, self.RiderOf[participant])
	end)
end

function TrailTangle:Cleanup()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, root in self.Anchored do
		if root.Parent then
			root.Anchored = false
		end
	end
	for _, highlight in self.Highlights do
		highlight:Destroy()
	end
	table.clear(self.Highlights)
	-- Grid and trails live in arena.Folder, which the framework destroys.
end

return TrailTangle
