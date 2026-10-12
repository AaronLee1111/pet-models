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
	Description = "The floor is lava's lazy cousin: tiles crumble after you step on them and random ones drop out. Keep moving, don't fall!",
	Duration = 75,
	Layout = Config.Layouts.FFA,
	Controls = {}, -- movement + jump only
}

local GRID = 7 -- GRID x GRID tiles
local TILE_SIZE = 8
local GAP = 1
local STEP_DELAY = 0.8 -- crumble time after being stepped on
local RANDOM_DELAY = 1.4 -- crumble time for a randomly picked tile (longer warning)
local RANDOM_INTERVAL = { 2.0, 0.5 } -- seconds between random drops, start -> end of round
local CHECK_INTERVAL = 0.1

local SOLID_COLOR = Color3.fromRGB(110, 220, 255)
local WARNING_COLOR = Color3.fromRGB(255, 200, 40)
local CRUMBLE_COLOR = Color3.fromRGB(255, 70, 70)

-- Setup -----------------------------------------------------------------------------------

function FallingPlatforms:Setup(arena, participants, _round)
	self.Tiles = {} -- [row][col] = { Part, State = "Solid" | "Warning" | "Fallen", Row, Col }
	self.Connections = {}

	local pitch = TILE_SIZE + GAP
	local half = (GRID - 1) / 2
	for row = 1, GRID do
		self.Tiles[row] = {}
		for col = 1, GRID do
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
	local spawnTiles = { { 2, 2 }, { 2, GRID - 1 }, { GRID - 1, 2 }, { GRID - 1, GRID - 1 } }
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
	local half = (GRID - 1) / 2
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
				elseif position.Y < floorY + 8 then
					-- Standing (or nearly) on the grid: the tile underneath starts crumbling.
					local tile = self:_tileAt(position)
					if tile then
						self:_crumble(tile, STEP_DELAY)
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

			if #round:GetAlive() <= 1 then
				round:End("LastStanding")
			end
		end)
	)
	round:SetStatus("Keep moving! 🏃")
end

--[[
	Bot behaviour: hop to a neighbouring solid tile whenever the current one starts to go
	(or every so often anyway). Low-skill bots occasionally make a bad call, which is funny.
]]
function FallingPlatforms:UpdateBot(bot, _dt)
	local position = bot:GetPosition()
	if not position then
		return
	end
	local memory = bot.Memory
	local current = self:_tileAt(position)
	local target = memory.Target

	local targetBad = not target or target.State ~= "Solid"
	local currentBad = not current or current.State ~= "Solid"
	local bored = os.clock() >= (memory.NextHop or 0)
	if not targetBad and not (current == target and (currentBad or bored)) then
		bot:MoveTo(target.Part.Position + Vector3.new(0, 3, 0))
		return
	end

	-- Pick the next tile: a solid 4-neighbour, preferring tiles nearer the middle.
	local from = current or target
	local options = {}
	if from then
		for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local row = self.Tiles[from.Row + offset[1]]
			local tile = row and row[from.Col + offset[2]]
			if tile and tile.State == "Solid" then
				table.insert(options, tile)
			end
		end
	end
	if #options == 0 or math.random() > 0.85 + bot.Skill * 0.15 then
		-- Stuck (or just dumb): head for the nearest solid tile anywhere.
		local best, bestDistance = nil, math.huge
		for _, tile in self:_solidTiles() do
			local distance = (tile.Part.Position - position).Magnitude
			if distance < bestDistance and tile ~= current then
				best, bestDistance = tile, distance
			end
		end
		options = { best }
	end
	if #options == 0 then
		memory.Target = nil -- no floor left anywhere; enjoy the fall
		return
	end

	local center = self.Arena.Origin.Position
	table.sort(options, function(a, b)
		return (a.Part.Position - center).Magnitude < (b.Part.Position - center).Magnitude
	end)
	-- Skilled bots usually take the most central option; others pick at random.
	local choice = if math.random() < bot.Skill then options[1] else options[math.random(1, #options)]

	memory.Target = choice
	memory.NextHop = os.clock() + 1 + math.random() * 1.5
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
