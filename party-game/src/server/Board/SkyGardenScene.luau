--[[
	SkyGardenScene
	Environment for Sunny Loop v2 (Scene = "SkyGarden"). Clean Studio blockouts sized to the
	modular dimensions in docs/SunnyLoopV2.md, so Blender pieces can replace them later.

	  * Whole board: floating island ground under every space at its height (terrace columns
	    with rock skirts), a stream pool round the sundial, a sundial placeholder, the bridge's
	    stone piers, and the "Sunny day" lighting preset.
	  * Vertical slice (the orchard, spaces 4-10 and 30-32): orchard ground and the raised
	    Hillside Steps terrace with its rock face, the Orchard Market shop building, a fence
	    between the two routes, orchard trees, the fork signpost at 5 and lamps.

	Everything here is decoration: no collision, no queries, no touches. Gameplay positions
	come from BoardWorld (Tops), so this file can change freely without touching the rules.
]]

local Scene = {}

local GRASS = Color3.fromRGB(122, 196, 98)
local GRASS_DARK = Color3.fromRGB(96, 168, 82)
local ROCK = Color3.fromRGB(176, 160, 142)
local ROCK_DARK = Color3.fromRGB(138, 122, 110)
local WOOD = Color3.fromRGB(176, 120, 72)
local WOOD_DARK = Color3.fromRGB(126, 84, 52)
local CREAM = Color3.fromRGB(250, 240, 220)
local RED = Color3.fromRGB(222, 72, 70)
local WATER = Color3.fromRGB(80, 190, 235)
local GOLD = Color3.fromRGB(242, 190, 72)
local LEAF = Color3.fromRGB(86, 170, 72)
local FRUIT = Color3.fromRGB(255, 132, 48)

local function part(parent, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Upright cylinder (Roblox cylinders lie along X).
local function column(parent, name, diameter, bottom: number, top: number, at: Vector3, color, material)
	local height = top - bottom
	return part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(at.X, bottom + height / 2, at.Z) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function group(parent, name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function sign(parent, text: string, cframe: CFrame, size: Vector3, color: Color3?)
	local board = part(parent, "Sign", size, cframe, color or CREAM, Enum.Material.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(70, 44, 30)
		label.Text = text
		label.Parent = gui
	end
	return board
end

local function tree(parent, at: Vector3, scale: number)
	local model = group(parent, "OrchardTree")
	column(model, "Trunk", 1.6 * scale, at.Y, at.Y + 6 * scale, at, WOOD_DARK, Enum.Material.Wood)
	local crown = at + Vector3.new(0, 8 * scale, 0)
	part(model, "Canopy", Vector3.one * 8 * scale, CFrame.new(crown), LEAF, Enum.Material.Grass, Enum.PartType.Ball)
	part(model, "Canopy2", Vector3.one * 5.5 * scale, CFrame.new(crown + Vector3.new(2.6, 1.6, 1) * scale), GRASS_DARK, Enum.Material.Grass, Enum.PartType.Ball)
	for i = 1, 4 do -- a few big fruit, not dozens of small ones
		local a = i * math.pi / 2 + 0.4
		local fruit = crown + Vector3.new(math.cos(a) * 3.6, -1 + (i % 2), math.sin(a) * 3.6) * scale
		part(model, "Fruit", Vector3.one * 1.3 * scale, CFrame.new(fruit), FRUIT, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end

local function lamp(parent, at: Vector3)
	local model = group(parent, "Lamp")
	column(model, "Post", 0.6, at.Y, at.Y + 6, at, WOOD_DARK, Enum.Material.Wood)
	local light = part(model, "Lantern", Vector3.new(1.4, 1.8, 1.4), CFrame.new(at + Vector3.new(0, 6.6, 0)), Color3.fromRGB(255, 214, 120), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Range = 14
	glow.Brightness = 0.8
	glow.Color = Color3.fromRGB(255, 210, 140)
	glow.Parent = light
end

-- A run of fence posts + two rails from a to b (on the ground at their heights).
local function fence(parent, a: Vector3, b: Vector3)
	local model = group(parent, "Fence")
	local run = b - a
	local count = math.max(2, math.floor(run.Magnitude / 4))
	for i = 0, count do
		local at = a + run * (i / count)
		part(model, "Post", Vector3.new(0.5, 2.6, 0.5), CFrame.new(at + Vector3.new(0, 1.3, 0)), CREAM, Enum.Material.Wood)
	end
	for _, y in { 1.0, 2.0 } do
		part(model, "Rail", Vector3.new(0.3, 0.3, run.Magnitude), CFrame.lookAt((a + b) / 2 + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)), CREAM, Enum.Material.Wood)
	end
end

-- Ground column under a point: grass top at `top`, rock skirt below, ending under the island.
local function ground(parent, at: Vector3, diameter: number, top: number)
	column(parent, "Grass", diameter, top - 1, top, at, GRASS, Enum.Material.Grass)
	column(parent, "Rock", diameter - 1, top - 9, top - 1, at, ROCK, Enum.Material.Rock)
end

-- Orchard Market: a small timber shop with a striped awning, counter and fruit crates,
-- facing the space it serves.
local function market(parent, at: Vector3, facing: Vector3)
	local model = group(parent, "OrchardMarket")
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	local function place(name, size, offset, color, material, shape)
		return part(model, name, size, cf * CFrame.new(offset), color, material, shape)
	end
	place("Floor", Vector3.new(14, 1, 11), Vector3.new(0, 0.5, 0), WOOD_DARK, Enum.Material.WoodPlanks)
	place("Back", Vector3.new(14, 9, 1), Vector3.new(0, 5.5, 5), CREAM, Enum.Material.Plaster)
	place("SideL", Vector3.new(1, 9, 10), Vector3.new(-6.5, 5.5, 0.5), CREAM, Enum.Material.Plaster)
	place("SideR", Vector3.new(1, 9, 10), Vector3.new(6.5, 5.5, 0.5), CREAM, Enum.Material.Plaster)
	place("BeamL", Vector3.new(1.2, 9.5, 1.2), Vector3.new(-6.5, 5.5, -4.6), WOOD, Enum.Material.Wood)
	place("BeamR", Vector3.new(1.2, 9.5, 1.2), Vector3.new(6.5, 5.5, -4.6), WOOD, Enum.Material.Wood)
	place("Roof", Vector3.new(16, 1, 13), Vector3.new(0, 10.6, 0.4), RED, Enum.Material.SmoothPlastic)
	-- Striped awning (four wide stripes: fewer, bigger shapes)
	for i = 0, 3 do
		place("Awning" .. i, Vector3.new(4, 0.4, 5), Vector3.new(-6 + i * 4, 8.6, -6.8) , if i % 2 == 0 then RED else CREAM, Enum.Material.Fabric)
			.CFrame = cf * CFrame.new(-6 + i * 4, 8.4, -6.6) * CFrame.Angles(math.rad(-22), 0, 0)
	end
	place("Counter", Vector3.new(11, 3, 2), Vector3.new(0, 2.5, -3.6), WOOD, Enum.Material.Wood)
	for i, colour in { FRUIT, RED, Color3.fromRGB(250, 214, 70) } do
		place("Crate" .. i, Vector3.new(2.6, 1.6, 2.2), Vector3.new(-4.4 + (i - 1) * 4.4, 4.8, -3.6), WOOD_DARK, Enum.Material.WoodPlanks)
		place("Fruit" .. i, Vector3.new(2.2, 0.8, 1.8), Vector3.new(-4.4 + (i - 1) * 4.4, 5.8, -3.6), colour, Enum.Material.SmoothPlastic)
	end
	local s = sign(model, "ORCHARD MARKET", cf * CFrame.new(0, 12.4, -5.2), Vector3.new(11, 2.4, 0.4), GOLD)
	s.Name = "MarketSign"
	lamp(model, (cf * CFrame.new(-8.5, 0, -5.5)).Position)
	return model
end

-- Fork signpost: one arrow board per route, each pointing at the route's first space.
local function signpost(parent, at: Vector3, routes)
	local model = group(parent, "Signpost")
	column(model, "Pole", 0.7, at.Y, at.Y + 8, at, WOOD_DARK, Enum.Material.Wood)
	for i, route in routes do
		local y = at.Y + 7.2 - (i - 1) * 2
		local target = Vector3.new(route.Toward.X, y, route.Toward.Z)
		local cf = CFrame.lookAt(Vector3.new(at.X, y, at.Z), target) * CFrame.Angles(0, math.rad(90), 0)
		sign(model, route.Label .. "  ›", cf * CFrame.new(-3.2, 0, 0), Vector3.new(6.4, 1.6, 0.35), route.Color)
	end
end

function Scene.build(world)
	local folder = world.Folder
	local at = world.WorldAt
	local board = world.Board
	local scene = group(folder, "SkyGarden")

	-- Sunny day (applied while the board is on screen; BoardWorld restores the old values).
	world.LightingPreset = {
		ClockTime = 14.2,
		Brightness = 2.6,
		Ambient = Color3.fromRGB(150, 140, 120),
		OutdoorAmbient = Color3.fromRGB(170, 160, 140),
	}

	-- Island ground: one column per space at its height (terraces read as stacked mesas), and
	-- thin stone piers under the Sundial Bridge instead of solid ground.
	local island = group(scene, "Island")
	for _, id in board.Order do
		local space = board.Spaces[id]
		local p = at(space.At)
		if space.Landmark == "SundialBridge" or space.Landmark == "SundialPavilion" then
			column(island, "Pier", 3.2, -6, p.Y, p, ROCK, Enum.Material.Cobblestone)
		else
			ground(island, p, 17, p.Y)
		end
	end
	-- Base plate joining the islands, and a stream pool round the sundial.
	local centre = at({ 0, -0.2, 0 })
	column(island, "BasePlate", 150, -9, -1, centre, ROCK_DARK, Enum.Material.Rock)
	column(island, "BaseGrass", 146, -1.2, -0.2, centre, GRASS_DARK, Enum.Material.Grass)
	local pool = column(island, "StreamPool", 44, -0.5, -0.05, at({ 0.1, -0.6, 0 }), WATER, Enum.Material.Glass)
	pool.Transparency = 0.25

	-- Sundial pavilion placeholder (landmark stage: blockout only, modelled later in Blender).
	local dial = group(scene, "SundialPavilion")
	local dialAt = at({ 0.1, -1.1, 0 })
	column(dial, "Dais", 22, -0.2, 2.4, dialAt, CREAM, Enum.Material.Marble)
	column(dial, "Face", 16, 2.4, 3.2, dialAt, GOLD, Enum.Material.Metal)
	part(dial, "Gnomon", Vector3.new(1, 7, 7), CFrame.new(dialAt + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(35), math.rad(-30)), GOLD, Enum.Material.Metal, Enum.PartType.Wedge)

	-- ===== Vertical slice: the orchard =====
	local orchard = group(scene, "OrchardSlice")
	-- Hillside terrace (spaces 30-32): one raised plateau with a rock face toward Market Lane.
	local terrace = at({ -3.8, -1.0, 6 })
	column(orchard, "TerraceTop", 30, 5, 6, terrace, GRASS, Enum.Material.Grass)
	column(orchard, "TerraceRock", 29, -1, 5, terrace, ROCK, Enum.Material.Rock)
	-- Fence on the terrace edge: the two routes stay visibly separate.
	fence(orchard, at({ -4.65, -2.1, 6 }), at({ -4.75, 0.4, 6 }))
	-- Orchard trees on the terrace and the outer edge (big, few).
	for _, spot in { { -2.75, -1.6, 6 }, { -2.85, 0.2, 6 }, { -6.3, 0.9, 0 }, { -6.1, -3.4, 0 }, { -4.2, -4.9, 0 } } do
		tree(orchard, at(spot), 1)
	end
	-- Orchard Market shop beside space 7, facing it.
	local shopSpace = at(board.Spaces[7].At)
	-- Faces between its space (east) and the board camera (south) so the storefront shows.
	market(orchard, at({ -6.35, -1.95, 0 }), shopSpace + Vector3.new(0, 0, 14))
	-- Fork signpost at 5: Market Lane (6) and Hillside Steps (30).
	local fork = at(board.Spaces[5].At)
	signpost(orchard, fork + Vector3.new(4.5, 0, 3.5), {
		{ Label = "Market Lane", Toward = at(board.Spaces[6].At), Color = Color3.fromRGB(255, 236, 190) },
		{ Label = "Hillside Steps", Toward = at(board.Spaces[30].At), Color = Color3.fromRGB(214, 240, 200) },
	})
	lamp(orchard, at({ -4.3, -3.75, 0 }))
	lamp(orchard, at({ -4.2, 0.75, 6 }))
	return scene
end

return Scene
