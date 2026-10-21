--[[
	Falling Platforms (FFA, elimination)
	A grid of tiles floating over the void. Any tile you stand on starts to crumble, and
	random tiles drop faster and faster as the round goes on. Fall and you're out.
	Last one standing wins; if time runs out every survivor ties for 1st.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local FallingPlatforms = {}

FallingPlatforms.Info = {
	Name = "Falling Platforms",
	Description = "Tiles crumble after you step on them and random ones drop out. Keep moving, don't fall!",
	Duration = 75,
	Layout = Config.Layouts.FFA,
	Tutorial = {
		Objective = "Stay on the platforms.",
		Rule = "Tiles crumble after you step on them.",
		Win = "Last player standing wins.",
		Preview = {
			Loop = 6,
			Camera = { Position = Vector3.new(0, 14, 16), LookAt = Vector3.new(0, 0, 0) },
			Actors = {
				{ Start = Vector3.new(-4.2, 0, 4.2) },
				{ Start = Vector3.new(4.2, 0, 0) },
			},
			Props = {
				{ Id = "A1", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(-4.2, -0.5, -4.2), Color = Color3.fromRGB(120, 196, 170) },
				{ Id = "A2", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(0, -0.5, -4.2), Color = Color3.fromRGB(150, 210, 185) },
				{ Id = "A3", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(4.2, -0.5, -4.2), Color = Color3.fromRGB(120, 196, 170) },
				{ Id = "B1", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(-4.2, -0.5, 0), Color = Color3.fromRGB(150, 210, 185) },
				{ Id = "B2", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(120, 196, 170) },
				{ Id = "B3", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(4.2, -0.5, 0), Color = Color3.fromRGB(150, 210, 185) },
				{ Id = "C1", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(-4.2, -0.5, 4.2), Color = Color3.fromRGB(120, 196, 170) },
				{ Id = "C2", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(0, -0.5, 4.2), Color = Color3.fromRGB(150, 210, 185) },
				{ Id = "C3", Shape = "Block", Size = Vector3.new(4, 1, 4), Position = Vector3.new(4.2, -0.5, 4.2), Color = Color3.fromRGB(120, 196, 170) },
			},
			Steps = {
				{ At = 0.3, Actor = 1, To = Vector3.new(0, 0, 4.2), Time = 0.8 },
				{ At = 0.6, Prop = "C1", Color = Color3.fromRGB(226, 110, 90) },
				{ At = 1.2, Prop = "C1", Visible = false },
				{ At = 1.2, Actor = 1, To = Vector3.new(0, 0, 0), Time = 0.8 },
				{ At = 0.8, Prop = "A3", Color = Color3.fromRGB(226, 110, 90) },
				{ At = 1.6, Prop = "A3", Visible = false },
				{ At = 1.6, Prop = "C2", Color = Color3.fromRGB(226, 110, 90) },
				{ At = 2.2, Prop = "C2", Visible = false },
				{ At = 2.2, Actor = 2, Jump = true },
				{ At = 2.2, Actor = 2, To = Vector3.new(4.2, 0, 4.2), Time = 0.6 },
				{ At = 2.4, Actor = 1, To = Vector3.new(-4.2, 0, -4.2), Time = 1 },
				{ At = 3.0, Prop = "B2", Color = Color3.fromRGB(226, 110, 90) },
				{ At = 3.6, Prop = "B2", Visible = false },
				{ At = 3.8, Caption = "KEEP MOVING!" },
			},
		},
	},
	Camera = { Mode = "FollowBehind" },
	Controls = { Move = true, Jump = true, WalkSpeed = 18 }, -- no actions, slightly zippier
	ProgressLabel = "Survived",
}

-- Tuning ----------------------------------------------------------------------------------
-- These decide how long a round lasts. Aim: 30-45 seconds with four players.

local GRID_SIZE = 10 -- GRID_SIZE x GRID_SIZE tiles
local TILE_SIZE = 8
local GAP = 1
-- Seconds a tile survives after being stepped on: { at GO, once the round is fully sped up }.
local CRUMBLE_DELAY = { 3.0, 1.2 }
-- Random drops: warning time for the tile, and seconds between drops { at GO, sped up }.
local RANDOM_DELAY = 2.0
local RANDOM_INTERVAL = { 3.0, 0.8 }
local RAMP_TIME = 45 -- seconds after GO until both of the above reach their fastest value
local START_GRACE = 1.5 -- tiles ignore footsteps this long after GO, so nobody drops before they can react
local CHECK_INTERVAL = 0.1

local SOLID_COLOR = Color3.fromRGB(110, 220, 255)
local WARNING_COLOR = Color3.fromRGB(255, 200, 40)
local CRUMBLE_COLOR = Color3.fromRGB(255, 70, 70)

-- Setup -----------------------------------------------------------------------------------

function FallingPlatforms:Setup(arena, participants, _round)
	self.Tiles = {} -- [row][col] = { Part, State = "Solid" | "Warning" | "Fallen", Row, Col }
	self.Connections = {}

	local pitch = TILE_SIZE + GAP
	local half = (GRID_SIZE - 1) / 2
	for row = 1, GRID_SIZE do
		self.Tiles[row] = {}
		for col = 1, GRID_SIZE do
			local part = Instance.new("Part")
			part.Name = ("Tile_%d_%d"):format(row, col)
			part.Anchored = true
			part.Size = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
			part.CFrame = arena.Origin * CFrame.new((col - 1 - half) * pitch, 0, (row - 1 - half) * pitch)
			-- Checkerboard tint so the grid reads well from above.
			part.Color = if (row + col) % 2 == 0 then SOLID_COLOR else SOLID_COLOR:Lerp(Color3.new(1, 1, 1), 0.3)
			part.Material = Enum.Material.SmoothPlastic
			part.Parent = arena.Folder
			self.Tiles[row][col] = { Part = part, State = "Solid", Row = row, Col = col }
		end
	end

	-- One player per corner-ish tile.
	local spawnTiles = { { 2, 2 }, { 2, GRID_SIZE - 1 }, { GRID_SIZE - 1, 2 }, { GRID_SIZE - 1, GRID_SIZE - 1 } }
	local spawns = {}
	for index = 1, #participants do
		local cell = spawnTiles[(index - 1) % #spawnTiles + 1]
		local tile = self.Tiles[cell[1]][cell[2]]
		local position = tile.Part.Position + Vector3.new(0, 4, 0)
		spawns[index] = CFrame.lookAt(position, Vector3.new(arena.Origin.X, position.Y, arena.Origin.Z))
	end
	return spawns
end

-- Tiles -----------------------------------------------------------------------------------

-- Which tile (if any) is directly under a world position.
function FallingPlatforms:_tileAt(position: Vector3)
	local localPosition = self.Arena.Origin:PointToObjectSpace(position)
	local pitch = TILE_SIZE + GAP
	local half = (GRID_SIZE - 1) / 2
	local col = math.floor(localPosition.X / pitch + half + 0.5) + 1
	local row = math.floor(localPosition.Z / pitch + half + 0.5) + 1
	local tileRow = self.Tiles[row]
	return tileRow and tileRow[col]
end

function FallingPlatforms:_crumble(tile, delay: number)
	if tile.State ~= "Solid" then
		return
	end
	tile.State = "Warning"
	tile.FallsAt = os.clock() + delay
	tile.Part.Color = WARNING_COLOR
	tile.Part.Material = Enum.Material.Neon

	task.delay(delay * 0.5, function()
		if tile.State == "Warning" and tile.Part.Parent then
			tile.Part.Color = CRUMBLE_COLOR
		end
	end)
	task.delay(delay, function()
		if tile.State ~= "Warning" or not tile.Part.Parent then
			return
		end
		tile.State = "Fallen"
		tile.Part.CanCollide = false
		tile.Part.Material = Enum.Material.Slate
		TweenService:Create(tile.Part, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = tile.Part.CFrame * CFrame.new(0, -40, 0) * CFrame.Angles(math.rad(25), 0, math.rad(15)),
			Transparency = 1,
		}):Play()
	end)
end

-- 0 at GO, 1 once the round has fully sped up.
function FallingPlatforms:_ramp(): number
	return math.clamp((os.clock() - (self.StartedAt or os.clock())) / RAMP_TIME, 0, 1)
end

function FallingPlatforms:_crumbleDelay(): number
	return CRUMBLE_DELAY[1] + (CRUMBLE_DELAY[2] - CRUMBLE_DELAY[1]) * self:_ramp()
end

function FallingPlatforms:_solidTiles()
	local list = {}
	for _, row in self.Tiles do
		for _, tile in row do
			if tile.State == "Solid" then
				table.insert(list, tile)
			end
		end
	end
	return list
end

-- Interface -------------------------------------------------------------------------------

function FallingPlatforms:Start()
	local round = self.Round
	local startedAt = os.clock()
	self.StartedAt = startedAt
	local nextChipUpdate = 0
	local nextCheck = 0
	local nextRandomDrop = os.clock() + RANDOM_INTERVAL[1]
	local floorY = self.Arena.Origin.Y

	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			if round.Ended or clock < nextCheck then
				return
			end
			nextCheck = clock + CHECK_INTERVAL

			for _, participant in round:GetAlive() do
				local position = participant:GetPosition()
				if not position then
					continue
				end
				if position.Y < floorY - Config.FallOutDepth then
					round:Eliminate(participant, true)
					round:Toast(("🪂 %s fell into the void"):format(participant.Name))
					round:ReportProgress(participant, ("🪂 %ds"):format(clock - startedAt))
				elseif position.Y < floorY + 8 and clock - startedAt >= START_GRACE then
					-- Standing (or nearly) on the grid: the tile underneath starts crumbling.
					local tile = self:_tileAt(position)
					if tile then
						self:_crumble(tile, self:_crumbleDelay())
					end
				end
			end

			-- Random drops speed up over the round.
			if clock >= nextRandomDrop then
				local progress = math.clamp((clock - startedAt) / self.Info.Duration, 0, 1)
				local interval = RANDOM_INTERVAL[1] + (RANDOM_INTERVAL[2] - RANDOM_INTERVAL[1]) * progress
				nextRandomDrop = clock + interval
				local solid = self:_solidTiles()
				if #solid > 0 then
					self:_crumble(solid[round.Rng:NextInteger(1, #solid)], RANDOM_DELAY)
				end
			end

			-- Chips: seconds survived for anyone still standing.
			if clock >= nextChipUpdate then
				nextChipUpdate = clock + 1
				for _, participant in round:GetAlive() do
					round:ReportProgress(participant, ("%ds"):format(clock - startedAt))
				end
			end

			if #round:GetAlive() <= 1 then
				round:End("LastStanding")
			end
		end)
	)
	round:SetStatus("Keep moving! 🏃")
end

--[[
	Bot behaviour: stand on a tile until it is about to drop, then step to a neighbour.
	(Leaving a tile the moment it starts to crumble would burn through the whole floor in
	seconds.) Sloppier bots cut it closer and pick worse tiles, which is funny.
]]
function FallingPlatforms:_solidNeighbours(tile)
	local list = {}
	for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local row = self.Tiles[tile.Row + offset[1]]
		local neighbour = row and row[tile.Col + offset[2]]
		if neighbour and neighbour.State == "Solid" then
			table.insert(list, neighbour)
		end
	end
	return list
end

function FallingPlatforms:UpdateBot(bot, _dt)
	local position = bot:GetPosition()
	if not position then
		return
	end
	local memory = bot.Memory
	local clock = os.clock()
	local current = self:_tileAt(position)
	if current and current.State == "Fallen" then
		current = nil
	end
	if not memory.Target then
		memory.Target = current
		memory.Margin = 0.6
	end
	local target = memory.Target

	if target and target ~= current and target.State == "Solid" then
		-- On the way. Hop if the floor ahead is already gone.
		local toTarget = target.Part.Position - position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude > 1 then
			local ahead = self:_tileAt(position + flat.Unit * 4)
			if not ahead or ahead.State == "Fallen" then
				bot:Jump()
			end
		end
		bot:MoveTo(target.Part.Position + Vector3.new(0, 3, 0))
		return
	end
	if target and target == current and (current.State == "Solid" or current.FallsAt - clock > memory.Margin) then
		bot:MoveTo(current.Part.Position + Vector3.new(0, 3, 0))
		return -- this tile still has time left: stay put
	end

	-- Pick the next tile: a solid 4-neighbour, preferring ones that aren't dead ends.
	local from = current or target
	local options = if from then self:_solidNeighbours(from) else {}
	if #options == 0 then
		-- Stranded: make a run (and a jump) for the nearest solid tile anywhere.
		local best, bestDistance = nil, math.huge
		for _, tile in self:_solidTiles() do
			local distance = (tile.Part.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = tile, distance
			end
		end
		options = { best }
	end
	if #options == 0 then
		memory.Target = nil -- no floor left anywhere; enjoy the fall
		return
	end

	local choice = options[math.random(1, #options)]
	if math.random() < bot.Skill then
		local bestExits = -1
		for _, tile in options do
			local exits = #self:_solidNeighbours(tile) + math.random() * 0.5
			if exits > bestExits then
				choice, bestExits = tile, exits
			end
		end
	end

	memory.Target = choice
	-- How late this bot dares to leave its next tile (seconds before it drops).
	memory.Margin = 0.35 + bot.Skill * 0.25 + math.random() * 0.45
	bot:MoveTo(choice.Part.Position + Vector3.new(0, 3, 0))
end

function FallingPlatforms:GetResults()
	return ResultsUtil.fromElimination(self.Participants, self.Round)
end

function FallingPlatforms:Cleanup()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return FallingPlatforms
