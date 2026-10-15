--[[
	BoardWorld
	Builds a board in the Workspace from a loaded board (BoardLayout) and tells BoardGame
	where pieces stand. Placeholder look: coloured tiles, paths and a gold collectible marker.

	  local world = BoardWorld.build(board, spaceTypes, origin)
	  world:spaceCFrame(id, slot, facingId?)  where a piece stands (slot 1..4 share a tile)
	  world:setCollectible(id, label)        move the collectible marker
	  world:destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)

local BoardWorld = {}
BoardWorld.__index = BoardWorld

local TILE_SIZE = 9
local TILE_HEIGHT = 1
local ROOT_HEIGHT = 3.2 -- HumanoidRootPart height above the tile top
local SLOT_OFFSETS = {
	Vector3.new(-2.5, 0, -2.5),
	Vector3.new(2.5, 0, -2.5),
	Vector3.new(-2.5, 0, 2.5),
	Vector3.new(2.5, 0, 2.5),
}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

function BoardWorld.build(board, spaceTypes, origin: Vector3)
	local self = setmetatable({ Board = board, Origin = origin, Tops = {} }, BoardWorld)
	local spacing = Config.Board.SpaceSpacing
	local folder = Instance.new("Folder")
	folder.Name = "PartyBoard"
	self.Folder = folder

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, id in board.Order do
		local at = board.Spaces[id].At
		minX, maxX = math.min(minX, at[1]), math.max(maxX, at[1])
		minZ, maxZ = math.min(minZ, at[2]), math.max(maxZ, at[2])
	end
	-- Centre the layout on the origin. Grid z goes "up the board" = -Z in the world.
	local centre = Vector3.new((minX + maxX) / 2 * spacing, 0, -(minZ + maxZ) / 2 * spacing)
	local function worldAt(at): Vector3
		return origin + Vector3.new(at[1] * spacing, 0, -at[2] * spacing) - centre
	end

	part({
		Name = "Base",
		Size = Vector3.new((maxX - minX) * spacing + 30, 2, (maxZ - minZ) * spacing + 30),
		Position = origin + Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(120, 200, 120),
		Material = Enum.Material.Grass,
		Parent = folder,
	})

	for _, id in board.Order do
		local space = board.Spaces[id]
		local spaceType = spaceTypes[space.Type]
		local position = worldAt(space.At)
		self.Tops[id] = position + Vector3.new(0, TILE_HEIGHT, 0)

		local tile = part({
			Name = "Space" .. id,
			Size = Vector3.new(TILE_SIZE, TILE_HEIGHT, TILE_SIZE),
			Position = position + Vector3.new(0, TILE_HEIGHT / 2, 0),
			Color = spaceType.Color,
			Parent = folder,
		})
		tile:SetAttribute("SpaceId", id)
		tile:SetAttribute("SpaceType", space.Type)
		if spaceType.Short ~= "" then
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 25
			gui.Parent = tile
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.4
			label.Text = spaceType.Short
			label.Parent = gui
		end

		-- Paths to the next spaces
		for _, nextId in space.Next do
			local target = worldAt(board.Spaces[nextId].At)
			local length = (target - position).Magnitude - TILE_SIZE
			if length > 0 then
				local middle = (position + target) / 2 + Vector3.new(0, 0.2, 0)
				part({
					Name = ("Path%d_%d"):format(id, nextId),
					Size = Vector3.new(2, 0.4, length),
					CFrame = CFrame.lookAt(middle, target + Vector3.new(0, 0.2, 0)),
					Color = Color3.fromRGB(245, 235, 210),
					Parent = folder,
				})
			end
		end
	end

	-- The collectible marker: a floating gold gem with a price tag.
	local marker = part({
		Name = "Collectible",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.5, 3.5, 3.5),
		Color = Color3.fromRGB(255, 205, 40),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Parent = folder,
	})
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(160, 40)
	tag.StudsOffset = Vector3.new(0, 3.5, 0)
	tag.AlwaysOnTop = true
	tag.Parent = marker
	local tagLabel = Instance.new("TextLabel")
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.BackgroundTransparency = 1
	tagLabel.Font = Enum.Font.FredokaOne
	tagLabel.TextScaled = true
	tagLabel.TextColor3 = Color3.fromRGB(255, 225, 90)
	tagLabel.TextStrokeTransparency = 0
	tagLabel.Parent = tag
	self.Marker = marker
	self.MarkerLabel = tagLabel

	folder.Parent = Workspace
	return self
end

-- Where a piece stands on space `id`. Up to four share a tile, one per corner slot.
function BoardWorld:spaceCFrame(id: number, slot: number?, facingId: number?): CFrame
	local top = self.Tops[id] or self.Origin
	local position = top + SLOT_OFFSETS[((slot or 1) - 1) % #SLOT_OFFSETS + 1] + Vector3.new(0, ROOT_HEIGHT, 0)
	local facing = facingId and self.Tops[facingId]
	if facing and (facing - top).Magnitude > 0.1 then
		local look = Vector3.new(facing.X, position.Y, facing.Z) + (position - top - Vector3.new(0, ROOT_HEIGHT, 0))
		return CFrame.lookAt(position, look)
	end
	return CFrame.new(position)
end

function BoardWorld:setCollectible(id: number?, label: string)
	local top = id and self.Tops[id]
	self.Marker.Transparency = if top then 0 else 1
	self.MarkerLabel.Text = label
	if top then
		self.Marker.Position = top + Vector3.new(0, 7, 0)
	end
end

function BoardWorld:destroy()
	self.Folder:Destroy()
end

return BoardWorld
