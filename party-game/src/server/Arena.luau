--[[
	Arena
	World helpers owned by the framework (minigames build their own map *inside* the arena):
	  * the lobby (built automatically if the place has no SpawnLocation)
	  * a fresh arena Folder per round, positioned at Config.ArenaOrigin
	  * the glass spectator box eliminated participants are sent to
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)

local Arena = {}

local function makePart(props): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Returns the lobby spawn, building a simple lobby first if the place has none.
function Arena.ensureLobby(): SpawnLocation
	local existing = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if existing then
		return existing
	end

	local lobby = Instance.new("Model")
	lobby.Name = "PartyLobby"

	makePart({
		Name = "Floor",
		Size = Vector3.new(80, 2, 80),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(255, 170, 230),
		Material = Enum.Material.SmoothPlastic,
		Parent = lobby,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Color = Color3.fromRGB(255, 220, 90)
	spawn.Neutral = true
	spawn.Duration = 0 -- no forcefield; it would block hot potato passes
	spawn.Parent = lobby

	lobby.Parent = Workspace
	return spawn
end

-- A spot in a ring around the lobby spawn so returning players don't stack up.
function Arena.lobbySpot(index: number): CFrame
	local spawn = Arena.ensureLobby()
	local angle = (index - 1) * (math.pi * 2 / Config.PlayersPerMatch)
	local offset = Vector3.new(math.cos(angle) * 10, 4, math.sin(angle) * 10)
	local position = spawn.Position + offset
	return CFrame.lookAt(position, Vector3.new(spawn.Position.X, position.Y, spawn.Position.Z))
end

local function buildSpectatorBox(parent: Instance, origin: CFrame): CFrame
	local box = Instance.new("Model")
	box.Name = "SpectatorBox"

	local center = origin.Position + Config.SpectatorOffset
	local size = 28
	makePart({
		Name = "Glass",
		Size = Vector3.new(size, 1, size),
		Position = center,
		Transparency = 0.7,
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(170, 230, 255),
		Parent = box,
	})
	-- Low invisible walls so spectators can't wander off the glass.
	for i = 0, 3 do
		local angle = i * math.pi / 2
		local wallCenter = center + Vector3.new(math.cos(angle) * size / 2, 4, math.sin(angle) * size / 2)
		makePart({
			Name = "Wall",
			Size = Vector3.new(1, 8, size),
			CFrame = CFrame.new(wallCenter) * CFrame.Angles(0, -angle, 0),
			Transparency = 1,
			Parent = box,
		})
	end
	box.Parent = parent
	return CFrame.new(center + Vector3.new(0, 4, 0))
end

--[[
	Creates the arena object handed to Minigame:Setup(arena, ...):
	  arena.Folder          parent everything you build here; it is destroyed after the round
	  arena.Origin          CFrame at the centre of the play space
	  arena.SpectatorCFrame where eliminated participants are sent
]]
function Arena.create(minigameName: string)
	local folder = Instance.new("Folder")
	folder.Name = "Arena_" .. minigameName
	folder.Parent = Workspace

	local origin = CFrame.new(Config.ArenaOrigin)
	return {
		Folder = folder,
		Origin = origin,
		SpectatorCFrame = buildSpectatorBox(folder, origin),
	}
end

function Arena.destroy(arena)
	if arena and arena.Folder then
		arena.Folder:Destroy()
	end
end

return Arena
