--[[
	BoardWorld
	Builds a board in the Workspace from a loaded board (BoardLayout) and tells BoardGame
	where pieces stand. Placeholder look: coloured tiles, paths and a gold collectible marker.

	  local world = BoardWorld.build(board, spaceTypes, origin)
	  world:spaceCFrame(id, slot, facingId?)  where a piece stands (slot 1..4 share a tile)
	  world:movePath(from, fromId, toId, to) the visible route of one move segment (BoardMove)
	  BoardWorld.moveTime(points, stairs, step, isBot)  seconds that segment takes
	  world:introSpec()                      the board-opening intro anchors in world space, or nil
	  world:setCollectible(id, label)        move the collectible marker
	  world:destroy()
	  BoardWorld.clearStale()                remove boards left in the Workspace (see below)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)

local FestivalScene = require(script.Parent.FestivalScene)
local MedallionKit = require(script.Parent.MedallionKit)
local SkyGardenScene = require(script.Parent.SkyGardenScene)
local SkyGardenKit = require(script.Parent.SkyGardenKit)

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
	local self = setmetatable({ Board = board, Origin = origin, Tops = {}, Tiles = {} }, BoardWorld)
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
		-- at[3] (optional) is the space's height in studs (terraces, bridges).
		return origin + Vector3.new(at[1] * spacing, at[3] or 0, -at[2] * spacing) - centre
	end
	self.WorldAt = worldAt
	local medallions = board.Style == "Medallion"

	if not board.Bridge and not medallions then
	part({
		Name = "Base",
		Size = Vector3.new((maxX - minX) * spacing + 30, 2, (maxZ - minZ) * spacing + 30),
		Position = origin + Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(120, 200, 120),
		Material = Enum.Material.Grass,
		Parent = folder,
	})

	end
	for _, id in board.Order do
		local space = board.Spaces[id]
		local spaceType = spaceTypes[space.Type]
		local position = worldAt(space.At)
		if medallions then
			-- Round medallion spaces + sloped sandy paths (MedallionKit); same Tops/Tiles API.
			self.Tops[id] = position + Vector3.new(0, MedallionKit.TOP, 0)
			local refined = board.Scene == "SkyGarden" and SkyGardenKit.isRefined(space.Area)
			self.Tiles[id] = MedallionKit.space(folder, position, space.Type, spaceType, id, refined, board.Name == "SunnyLoopV2")
			continue
		end
		self.Tops[id] = position + Vector3.new(0, TILE_HEIGHT, 0)

		local tile = part({
			Name = "Space" .. id,
			Size = Vector3.new(TILE_SIZE, TILE_HEIGHT, TILE_SIZE),
			Position = position + Vector3.new(0, TILE_HEIGHT / 2, 0),
			Color = spaceType.Color,
			Parent = folder,
		})
		self.Tiles[id] = tile
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
			if board.Bridge and (id >= 33 or nextId >= 33) then continue end
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

	if medallions then
		for _, id in board.Order do
			for _, nextId in board.Spaces[id].Next do
				-- A route between two refined areas (or inside one) gets that area's path material
				local area = board.Spaces[id].Area
				local refinedPath = board.Scene == "SkyGarden" and SkyGardenKit.isRefined(area) and SkyGardenKit.isRefined(board.Spaces[nextId].Area)
				MedallionKit.path(folder, self.Tops[id], self.Tops[nextId], ("Path%d_%d"):format(id, nextId), if refinedPath then area else nil)
			end
		end
	end
	if board.Bridge then FestivalScene.build(self) end
	if board.Scene == "SkyGarden" then SkyGardenScene.build(self) end
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

-- The visible route of one move segment, as HumanoidRootPart positions from `from` to `to` (the
-- piece's slot on `toId`). Presentation only: Match has already decided the move. Uses the
-- edge's Via waypoints when the board has them; otherwise medallion boards run edge to edge
-- and climb every stair step, and tile boards go straight. Returns the points and whether the
-- segment is a stair climb.
function BoardWorld:movePath(from: Vector3, fromId: number, toId: number, to: Vector3): ({ Vector3 }, boolean)
	local lift = Vector3.new(0, ROOT_HEIGHT, 0)
	local medallions = self.Board.Style == "Medallion"
	local points, stairs = { from }, false
	local space = self.Board.Spaces[fromId]
	local via = space and space.Via and space.Via[toId]
	local a, b = self.Tops[fromId], self.Tops[toId]
	if via then
		local surface = Vector3.new(0, if medallions then MedallionKit.TOP else TILE_HEIGHT, 0)
		for _, at in via do
			table.insert(points, self.WorldAt(at) + surface + lift)
		end
	elseif medallions and a and b and space and table.find(space.Next, toId) then
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if flat.Magnitude > MedallionKit.DIAMETER then
			local radius = MedallionKit.DIAMETER / 2 - 0.4
			local exit, entry = a + flat.Unit * radius, b - flat.Unit * radius
			table.insert(points, exit + lift)
			local rise = b.Y - a.Y
			if math.abs(rise) >= 1.5 then
				stairs = true
				local count = MedallionKit.stairCount(rise)
				for i = 1, count do
					local t = (i - 0.5) / count
					local y = a.Y + rise * (if rise > 0 then i / count else (i - 1) / count)
					local centre = exit:Lerp(entry, t)
					table.insert(points, Vector3.new(centre.X, y, centre.Z) + lift)
				end
			end
			table.insert(points, entry + lift)
		end
	end
	table.insert(points, to)
	return points, stairs
end

-- Seconds one segment takes: path length at MoveSpeed inside the normal or stair band, faster
-- for later steps of a long roll and for bots, all scaled by HopTime (tests run it fast).
function BoardWorld.moveTime(points: { Vector3 }, stairs: boolean, step: number, isBot: boolean): number
	local board = Config.Board
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end
	local band = if stairs then board.StairTime else board.MoveTime
	local seconds = math.clamp(length / board.MoveSpeed, band[1], band[2])
	seconds *= math.max(board.MoveRampMin, 1 - board.MoveRamp * (step - 1))
	if isBot then
		seconds *= board.BotMoveScale
	end
	return seconds * board.HopTime / 0.35
end

--[[
	The board-opening introduction in world space, from the board's declarative Intro data
	(grid points { x, z, height } like At), or nil when the board has none:
	  Establish = { Camera, Look }   the landmark shot
	  Arrival = { Camera, Look }     the entrance, held while each participant arrives
	  Entry = { points }             where arrivals appear, then walk through (the last point
	                                 leads to the piece's slot on Start)
	  Group = { Camera, Look }       everyone on the start space
	  Effect = "Sunbeam" | "Moonbeam" | "Walk"
	  Times = { Establish = 1.3, Each = 1.25, ... } overrides Config.Board.Intro
]]
function BoardWorld:introSpec()
	local intro = self.Board.Intro
	if not intro then
		return nil
	end
	local surface = Vector3.new(0, if self.Board.Style == "Medallion" then MedallionKit.TOP else TILE_HEIGHT, 0)
	local function at(point)
		return self.WorldAt(point) + surface
	end
	local function shot(data)
		return { Camera = at(data.Camera), Look = at(data.Look) }
	end
	local entry = {}
	for _, point in intro.Entry do
		table.insert(entry, at(point) + Vector3.new(0, ROOT_HEIGHT, 0))
	end
	return {
		Establish = shot(intro.Establish),
		Arrival = shot(intro.Arrival),
		Group = shot(intro.Group),
		Entry = entry,
		Effect = intro.Effect or "Walk",
		Times = intro.Times,
	}
end

-- True if a piece at `position` is clearly not standing on space `id` (knocked off, fell
-- through, flung away). Small wobbles inside the tile don't count.
function BoardWorld:isMisplaced(position: Vector3, id: number): boolean
	local top = self.Tops[id]
	if not top then
		return false
	end
	local flat = Vector3.new(position.X - top.X, 0, position.Z - top.Z)
	return flat.Magnitude > TILE_SIZE or position.Y < top.Y - 2 or position.Y > top.Y + 20
end

-- Medallion boards: a gold ring over the space of whoever's turn it is (presentation only).
function BoardWorld:setActiveSpace(id: number?)
	if self.Board.Style ~= "Medallion" then
		return
	end
	local top = id and self.Tops[id]
	if not top then
		if self.ActiveMarker then
			self.ActiveMarker.Parent = nil
		end
		return
	end
	self.ActiveMarker = self.ActiveMarker or MedallionKit.highlight(self.Folder)
	self.ActiveMarker.Parent = self.Folder
	self.ActiveMarker:PivotTo(CFrame.new(top + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2))
end

function BoardWorld:setCollectible(id: number?, label: string)
	self.MarkerId = id
	local top = id and self.Tops[id]
	self.Marker.Transparency = if top then 0 else 1
	self.MarkerLabel.Text = label
	if top then
		self.Marker.Position = top + Vector3.new(0, 7, 0)
	end
end

-- Shows each gate on its path: a red barrier when closed, a yellow toll post when open.
function BoardWorld:setGates(gates, openState)
	self.GateMarkers = self.GateMarkers or {}
	for _, gate in gates or {} do
		local path = self.Folder:FindFirstChild(("Path%d_%d"):format(gate.From, gate.To))
		if not path then
			continue
		end
		local marker = self.GateMarkers[gate.Id]
		if not marker then
			marker = part({
				Name = "Gate_" .. gate.Id,
				Size = Vector3.new(4, 3, 0.6),
				CFrame = path.CFrame * CFrame.new(0, 1.5, 0),
				CanCollide = false,
				CanQuery = false,
				Parent = self.Folder,
			})
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromScale(6, 1.5) -- studs, so it shrinks with distance like the board
			gui.StudsOffset = Vector3.new(0, 3, 0)
			gui.Parent = marker
			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0
			label.Parent = gui
			self.GateMarkers[gate.Id] = marker
		end
		local open = openState[gate.Id]
		marker.Color = if open then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(220, 50, 50)
		marker.Transparency = if open then 0.5 else 0
		marker:FindFirstChildWhichIsA("BillboardGui").Label.Text = if not open
			then "CLOSED"
			elseif (gate.Toll or 0) > 0 then ("TOLL %d"):format(gate.Toll)
			else "OPEN"
	end
end

-- Draws a small marker on every trapped space ({ [spaceId] = trap }).
function BoardWorld:setTraps(traps)
	self.TrapMarkers = self.TrapMarkers or {}
	for id, marker in self.TrapMarkers do
		if not traps[id] then
			marker:Destroy()
			self.TrapMarkers[id] = nil
		end
	end
	for id in traps do
		local top = self.Tops[id]
		if top and not self.TrapMarkers[id] then
			self.TrapMarkers[id] = part({
				Name = "Trap" .. id,
				Size = Vector3.new(3, 0.4, 3),
				Position = top + Vector3.new(0, 0.2, 0),
				Color = Color3.fromRGB(120, 40, 40),
				Material = Enum.Material.DiamondPlate,
				CanCollide = false,
				CanQuery = false,
				Parent = self.Folder,
			})
		end
	end
end

function BoardWorld:setBridgeAngle(angle)
 FestivalScene.align(self,angle)
 if self.MarkerId and self.MarkerId>=33 then self.Marker.Position=self.Tops[self.MarkerId]+Vector3.new(0,7,0) end
 for id,marker in self.TrapMarkers or {} do
  if id>=33 then marker.Position=self.Tops[id]+Vector3.new(0,0.2,0) end
 end
end
function BoardWorld:setBridgeState(state)
 if state then FestivalScene.status(self,state) end
end

-- Board lighting while the board is on screen (not during minigames). The festival has its
-- dusk values; a scene can set self.LightingPreset (e.g. SkyGardenScene) to use its own.
function BoardWorld:setFestivalLighting(active)
 if not self.Board.Bridge and not self.LightingPreset then return end
 local lighting=game:GetService("Lighting")
 if active and not self.SavedLighting then
  self.SavedLighting={ClockTime=lighting.ClockTime,Ambient=lighting.Ambient,OutdoorAmbient=lighting.OutdoorAmbient,Brightness=lighting.Brightness}
  for key in self.LightingPreset or {} do self.SavedLighting[key]=lighting[key] end
  if self.LightingPreset then
   for key,value in self.LightingPreset do lighting[key]=value end
   for _,child in self.LightingChildren or {} do child.Parent=lighting end
  else
  lighting.ClockTime=17.8;lighting.Ambient=Color3.fromRGB(145,130,180)
  lighting.OutdoorAmbient=Color3.fromRGB(155,150,190);lighting.Brightness=2
  end
 elseif not active and self.SavedLighting then
  for key,value in self.SavedLighting do lighting[key]=value end
  for _,child in self.LightingChildren or {} do child.Parent=nil end
  self.SavedLighting=nil
 end
end

-- A board saved into the place file (e.g. a preview built in Edit mode and then saved) would sit
-- under the live one: doubled colliders, overlapping faces, and clients picking the wrong folder.
-- Only one match runs per server, so before a new board is built every old one goes.
function BoardWorld.clearStale()
	for _, child in Workspace:GetChildren() do
		if child.Name == "PartyBoard" then
			child:Destroy()
		end
	end
end

function BoardWorld:destroy()
 self:setFestivalLighting(false)
 for _,child in self.LightingChildren or {} do child:Destroy() end
	self.Folder:Destroy()
end

return BoardWorld
