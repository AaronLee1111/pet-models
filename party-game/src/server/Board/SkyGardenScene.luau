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

local GRASS = Color3.fromRGB(128, 214, 86)
local GRASS_DARK = Color3.fromRGB(104, 194, 78)
local ROCK = Color3.fromRGB(196, 178, 156)
local ROCK_DARK = Color3.fromRGB(162, 142, 124)
local WOOD = Color3.fromRGB(176, 120, 72)
local WOOD_DARK = Color3.fromRGB(126, 84, 52)
local CREAM = Color3.fromRGB(250, 240, 220)
local RED = Color3.fromRGB(222, 72, 70)
local WATER = Color3.fromRGB(80, 190, 235)
local GOLD = Color3.fromRGB(242, 190, 72)
local LEAF = Color3.fromRGB(96, 192, 70)
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


-- More pieces --------------------------------------------------------------------------------

local LEAVES = {
	Color3.fromRGB(96, 196, 70),
	Color3.fromRGB(126, 214, 82),
	Color3.fromRGB(78, 176, 76),
	Color3.fromRGB(156, 222, 92),
}
-- A few blossom / golden trees for colour (fair and village)
local BLOSSOMS = {
	Color3.fromRGB(255, 170, 200),
	Color3.fromRGB(255, 205, 90),
	Color3.fromRGB(250, 140, 170),
}
local FLOWERS = {
	Color3.fromRGB(255, 120, 150),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(250, 250, 255),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(255, 150, 70),
}
local STRIPES = {
	{ RED, CREAM },
	{ Color3.fromRGB(70, 130, 230), CREAM },
	{ Color3.fromRGB(250, 190, 60), Color3.fromRGB(240, 90, 60) },
	{ Color3.fromRGB(150, 90, 220), CREAM },
}
local STONE = Color3.fromRGB(226, 218, 200)
local ROOF_BLUE = Color3.fromRGB(80, 120, 200)
local ROOF_RED = Color3.fromRGB(205, 85, 70)

local function ball(parent, name, size: number, at: Vector3, color, material)
	return part(parent, name, Vector3.one * size, CFrame.new(at), color, material or Enum.Material.SmoothPlastic, Enum.PartType.Ball)
end

-- A cone-like roof from stacked shrinking discs (no meshes needed).
local function roof(parent, diameter: number, base: number, height: number, at: Vector3, colors)
	local steps = 4
	for i = 0, steps - 1 do
		local d = diameter * (1 - i / steps) + 0.6
		local y0 = base + height * i / steps
		column(parent, "Roof" .. i, d, y0, y0 + height / steps, at, colors[i % #colors + 1], Enum.Material.Fabric)
	end
	ball(parent, "Finial", 1.2, at + Vector3.new(0, base + height + 0.4 - at.Y, 0), GOLD, Enum.Material.Metal)
end

local function roundTree(parent, at: Vector3, scale: number, rng, blossom: boolean?)
	local model = group(parent, "Tree")
	column(model, "Trunk", 1.4 * scale, at.Y, at.Y + 5 * scale, at, WOOD_DARK, Enum.Material.Wood)
	local leaf = if blossom then BLOSSOMS[rng:NextInteger(1, #BLOSSOMS)] else LEAVES[rng:NextInteger(1, #LEAVES)]
	ball(model, "Canopy", 7 * scale, at + Vector3.new(0, 7 * scale, 0), leaf, Enum.Material.Grass)
	ball(model, "Canopy2", 4.5 * scale, at + Vector3.new(1.8, 8.6, -0.8) * scale, if blossom then leaf else LEAVES[rng:NextInteger(1, #LEAVES)], Enum.Material.Grass)
end

local function pineTree(parent, at: Vector3, scale: number)
	local model = group(parent, "Pine")
	column(model, "Trunk", 1.1 * scale, at.Y, at.Y + 3 * scale, at, WOOD_DARK, Enum.Material.Wood)
	for i = 0, 2 do
		local d = (6.5 - i * 1.8) * scale
		column(model, "Tier" .. i, d, at.Y + (2.5 + i * 2.6) * scale, at.Y + (5 + i * 2.6) * scale, at, Color3.fromRGB(60, 140, 80), Enum.Material.Grass)
	end
end

local function bush(parent, at: Vector3, rng)
	local s = rng:NextNumber(2.4, 4)
	ball(parent, "Bush", s, at + Vector3.new(0, s * 0.35, 0), LEAVES[rng:NextInteger(1, #LEAVES)], Enum.Material.Grass)
	if rng:NextNumber() < 0.5 then
		ball(parent, "Berry", 0.9, at + Vector3.new(s * 0.3, s * 0.7, -s * 0.2), FLOWERS[rng:NextInteger(1, #FLOWERS)])
	end
end

local function flowerBed(parent, at: Vector3, rng)
	local bed = column(parent, "FlowerBed", rng:NextNumber(4, 6), at.Y - 0.2, at.Y + 0.35, at, GRASS_DARK, Enum.Material.Grass)
	bed.CastShadow = false
	local colour = FLOWERS[rng:NextInteger(1, #FLOWERS)]
	for i = 1, 4 do
		local a = i * math.pi / 2 + rng:NextNumber(0, 1)
		local f = ball(parent, "Flower", 1.1, at + Vector3.new(math.cos(a) * 1.4, 0.7, math.sin(a) * 1.4), if i == 4 then FLOWERS[rng:NextInteger(1, #FLOWERS)] else colour)
		f.CastShadow = false
	end
end

local function rock(parent, at: Vector3, rng, scale: number?)
	local s = (scale or 1) * rng:NextNumber(1.6, 3.4)
	local r = part(parent, "Rock", Vector3.new(s * 1.3, s, s), CFrame.new(at + Vector3.new(0, s * 0.35, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), ROCK, Enum.Material.Slate)
	r.CastShadow = false
	return r
end

local function crate(parent, at: Vector3, rng)
	local c = part(parent, "Crate", Vector3.new(2.4, 1.6, 2), CFrame.new(at + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), WOOD, Enum.Material.WoodPlanks)
	part(parent, "Apples", Vector3.new(2, 0.6, 1.6), c.CFrame * CFrame.new(0, 1, 0), if rng:NextNumber() < 0.5 then FRUIT else RED, Enum.Material.SmoothPlastic)
end

-- A small cottage with a wedge roof, facing `facing`.
local function cottage(parent, at: Vector3, facing: Vector3, rng, roofColor)
	local model = group(parent, "Cottage")
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	local w, d = rng:NextNumber(7, 9), rng:NextNumber(6, 8)
	part(model, "Walls", Vector3.new(w, 5, d), cf * CFrame.new(0, 2.5, 0), CREAM, Enum.Material.Plaster)
	for side = -1, 1, 2 do
		part(model, "Roof", Vector3.new(w + 1, 3, d / 2 + 0.6), cf * CFrame.new(0, 6.5, side * (d / 4 + 0.15)) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0), roofColor or ROOF_BLUE, Enum.Material.SmoothPlastic, Enum.PartType.Wedge)
	end
	part(model, "Door", Vector3.new(1.6, 2.8, 0.3), cf * CFrame.new(0, 1.4, -d / 2 - 0.1), WOOD_DARK, Enum.Material.Wood)
	for x = -1, 1, 2 do
		local win = part(model, "Window", Vector3.new(1.4, 1.4, 0.3), cf * CFrame.new(x * w / 3.2, 3, -d / 2 - 0.1), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
		win.CastShadow = false
	end
	part(model, "Chimney", Vector3.new(1.2, 3, 1.2), cf * CFrame.new(w / 3, 7.5, d / 5), STONE, Enum.Material.Brick)
	return model
end

-- Striped booth with a counter (fairground stalls).
local function booth(parent, at: Vector3, facing: Vector3, stripes)
	local model = group(parent, "Booth")
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	part(model, "Counter", Vector3.new(6, 2.6, 3), cf * CFrame.new(0, 1.3, 0), WOOD, Enum.Material.Wood)
	for x = -1, 1, 2 do
		part(model, "Post", Vector3.new(0.5, 6, 0.5), cf * CFrame.new(x * 2.7, 3, 1.2), CREAM, Enum.Material.Wood)
	end
	for i = 0, 2 do
		local stripe = part(model, "Awning", Vector3.new(2.1, 0.4, 4.2), cf * CFrame.new(-2.1 + i * 2.1, 6.2, 0) * CFrame.Angles(math.rad(-15), 0, 0), stripes[i % 2 + 1], Enum.Material.Fabric)
		stripe.CastShadow = false
	end
	ball(model, "Prize", 1.4, (cf * CFrame.new(0, 3.3, 0)).Position, FLOWERS[1])
end

-- A string of triangle flags between two posts.
local function bunting(parent, a: Vector3, b: Vector3, rng)
	local model = group(parent, "Bunting")
	for _, p in { a, b } do
		column(model, "Pole", 0.5, p.Y, p.Y + 8, p, WOOD_DARK, Enum.Material.Wood)
	end
	local top1, top2 = a + Vector3.new(0, 7.6, 0), b + Vector3.new(0, 7.6, 0)
	local length = (top2 - top1).Magnitude
	part(model, "Rope", Vector3.new(0.15, 0.15, length), CFrame.lookAt((top1 + top2) / 2, top2), CREAM)
	local count = math.max(3, math.floor(length / 2.5))
	for i = 1, count do
		local p = top1:Lerp(top2, i / (count + 1)) - Vector3.new(0, 0.2 + math.sin(i / (count + 1) * math.pi) * 0.8, 0)
		local flag = part(model, "Flag", Vector3.new(0.1, 1.4, 1.2), CFrame.lookAt(p, p + (top2 - top1)) * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, math.rad(90), math.rad(180)), FLOWERS[(i + rng:NextInteger(0, 4)) % #FLOWERS + 1], Enum.Material.Fabric, Enum.PartType.Wedge)
		flag.CastShadow = false
	end
end

local function balloon(parent, at: Vector3, rng)
	local h = rng:NextNumber(7, 10)
	part(parent, "String", Vector3.new(0.08, h, 0.08), CFrame.new(at + Vector3.new(0, h / 2, 0)), CREAM)
	ball(parent, "Balloon", 1.8, at + Vector3.new(0, h + 0.9, 0), FLOWERS[rng:NextInteger(1, #FLOWERS)])
end

-- Big striped circus tent (fairground hero).
local function circusTent(parent, at: Vector3)
	local model = group(parent, "CircusTent")
	column(model, "Floor", 22, at.Y - 0.2, at.Y + 0.5, at, WOOD, Enum.Material.WoodPlanks)
	local wallColours = { RED, CREAM }
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local p = at + Vector3.new(math.cos(a) * 9.4, 0, math.sin(a) * 9.4)
		part(model, "Wall" .. i, Vector3.new(5.2, 7, 0.6), CFrame.lookAt(p + Vector3.new(0, 4, 0), at + Vector3.new(0, 4, 0)), wallColours[i % 2 + 1], Enum.Material.Fabric)
	end
	roof(model, 22, at.Y + 7.5, 9, at, { RED, CREAM })
	part(model, "Flag", Vector3.new(0.2, 2, 3), CFrame.new(at + Vector3.new(1.5, 18.8, 0)), GOLD, Enum.Material.Fabric)
	column(model, "FlagPole", 0.4, at.Y + 16.5, at.Y + 20, at, WOOD_DARK)
	return model
end

local function stage(parent, at: Vector3, facing: Vector3)
	local model = group(parent, "EventStage")
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	part(model, "Deck", Vector3.new(14, 2, 9), cf * CFrame.new(0, 1, 0), WOOD, Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(14, 9, 0.8), cf * CFrame.new(0, 5.5, 4.2), Color3.fromRGB(150, 60, 160), Enum.Material.Fabric)
	for x = -1, 1, 2 do
		part(model, "Curtain", Vector3.new(2.4, 8, 0.6), cf * CFrame.new(x * 6, 6, 3.6), RED, Enum.Material.Fabric)
		local light = part(model, "Spot", Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(x * 5, 10.5, 3.6), Color3.fromRGB(255, 240, 180), Enum.Material.Neon)
		light.CastShadow = false
	end
	part(model, "Arch", Vector3.new(15, 1.4, 1.4), cf * CFrame.new(0, 10, 3.6), GOLD, Enum.Material.Metal)
	local s = sign(model, "★ STAGE ★", cf * CFrame.new(0, 11.6, 3.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(8, 1.8, 0.4), GOLD)
	s.Name = "StageSign"
end

local function crownPavilion(parent, at: Vector3, facing: Vector3)
	local model = group(parent, "CrownPavilion")
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	column(model, "Plinth", 15, at.Y - 0.5, at.Y + 1.2, at, STONE, Enum.Material.Marble)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		column(model, "Pillar" .. i, 1.4, at.Y + 1.2, at.Y + 10, at + Vector3.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6), Color3.fromRGB(250, 246, 236), Enum.Material.Marble)
	end
	column(model, "Ring", 14, at.Y + 10, at.Y + 11.2, at, GOLD, Enum.Material.Metal)
	ball(model, "Dome", 11, at + Vector3.new(0, 11, 0), Color3.fromRGB(250, 246, 236), Enum.Material.Marble)
	-- Crown on top: a band with five gold points and a red gem
	local top = at + Vector3.new(0, 17, 0)
	column(model, "CrownBand", 5, top.Y - 0.8, top.Y + 0.6, top, GOLD, Enum.Material.Metal)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		part(model, "CrownPoint" .. i, Vector3.new(0.6, 2.4, 1.6), CFrame.new(top + Vector3.new(math.cos(a) * 2.1, 1.6, math.sin(a) * 2.1)) * CFrame.Angles(0, -a, 0), GOLD, Enum.Material.Metal, Enum.PartType.Wedge)
	end
	ball(model, "Gem", 1.3, top + Vector3.new(0, 0, 0), Color3.fromRGB(230, 40, 70), Enum.Material.Glass)
	part(model, "Carpet", Vector3.new(4, 0.2, 9), cf * CFrame.new(0, 1.3 - 0.2, -6), RED, Enum.Material.Fabric)
	for x = -1, 1, 2 do
		part(model, "Banner", Vector3.new(2.4, 5, 0.2), cf * CFrame.new(x * 7.5, 6, -1), RED, Enum.Material.Fabric)
		column(model, "BannerPole", 0.4, at.Y, at.Y + 9, (cf * CFrame.new(x * 7.5, 0, -1)).Position, GOLD, Enum.Material.Metal)
	end
end

local function waterwheelMill(parent, at: Vector3, wheelSide: Vector3)
	local model = group(parent, "WaterwheelMill")
	local cf = CFrame.lookAt(at, Vector3.new(wheelSide.X, at.Y, wheelSide.Z))
	part(model, "Base", Vector3.new(12, 3, 10), cf * CFrame.new(0, 1.5, 0), STONE, Enum.Material.Cobblestone)
	part(model, "Walls", Vector3.new(11, 7, 9), cf * CFrame.new(0, 6.5, 0), CREAM, Enum.Material.Plaster)
	for side = -1, 1, 2 do
		part(model, "Roof", Vector3.new(12.5, 4.5, 5.2), cf * CFrame.new(0, 12.2, side * 2.4) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), ROOF_BLUE, Enum.Material.Slate, Enum.PartType.Wedge)
	end
	part(model, "Chimney", Vector3.new(1.6, 5, 1.6), cf * CFrame.new(-3.5, 13, 1.5), STONE, Enum.Material.Brick)
	for x = -1, 1, 2 do
		local win = part(model, "Window", Vector3.new(1.6, 1.8, 0.3), cf * CFrame.new(x * 3, 7, 4.6), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
		win.CastShadow = false
	end
	-- Wheel on the stream side (front = -Z of cf, toward wheelSide)
	local hub = cf * CFrame.new(0, 5, -6.2)
	local wheel = group(model, "Wheel")
	part(wheel, "Rim", Vector3.new(1.4, 11, 11), hub * CFrame.Angles(0, math.rad(90), 0), WOOD_DARK, Enum.Material.Wood, Enum.PartType.Cylinder)
	part(wheel, "Inner", Vector3.new(1.6, 8.5, 8.5), hub * CFrame.Angles(0, math.rad(90), 0), WOOD, Enum.Material.Wood, Enum.PartType.Cylinder)
	for i = 0, 3 do
		part(wheel, "Spoke" .. i, Vector3.new(10.6, 0.7, 1.7), hub * CFrame.Angles(0, 0, i * math.pi / 4), WOOD_DARK, Enum.Material.Wood)
	end
	part(model, "Dock", Vector3.new(8, 0.6, 6), cf * CFrame.new(7, 0.3, -5), WOOD, Enum.Material.WoodPlanks)
	part(model, "Boat", Vector3.new(3, 1.2, 6), cf * CFrame.new(9, 0.2, -10) * CFrame.Angles(0, 0.4, 0), WOOD, Enum.Material.Wood)
	return model
end

local function bellTower(parent, at: Vector3)
	local model = group(parent, "BellSwitch")
	for x = -1, 1, 2 do
		part(model, "Leg", Vector3.new(0.8, 9, 0.8), CFrame.new(at + Vector3.new(x * 2.4, 4.5, 0)), WOOD_DARK, Enum.Material.Wood)
	end
	part(model, "Beam", Vector3.new(6, 0.8, 1), CFrame.new(at + Vector3.new(0, 9, 0)), WOOD, Enum.Material.Wood)
	ball(model, "Bell", 3, at + Vector3.new(0, 7.2, 0), GOLD, Enum.Material.Metal)
	part(model, "Roof", Vector3.new(7, 1.6, 3), CFrame.new(at + Vector3.new(0, 10.2, 0)), ROOF_RED, Enum.Material.SmoothPlastic)
end

local function kiosk(parent, at: Vector3)
	local model = group(parent, "FairKiosk")
	column(model, "Floor", 9, at.Y, at.Y + 0.6, at, WOOD, Enum.Material.WoodPlanks)
	column(model, "Counter", 6, at.Y + 0.6, at.Y + 3, at, CREAM, Enum.Material.Wood)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.4
		column(model, "Post" .. i, 0.5, at.Y, at.Y + 6.5, at + Vector3.new(math.cos(a) * 3.8, 0, math.sin(a) * 3.8), GOLD, Enum.Material.Metal)
	end
	roof(model, 10, at.Y + 6.5, 4, at, { ROOF_BLUE, CREAM })
end

local function sunGate(parent, a: Vector3, b: Vector3)
	-- An arch over the path: posts left and right of the space, a sun disc on the lintel.
	local model = group(parent, "SunGate")
	local mid = (a + b) / 2
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for s = -1, 1, 2 do
		column(model, "Post", 1.2, mid.Y, mid.Y + 8.5, mid + side * s * 4.2, STONE, Enum.Material.Marble)
	end
	part(model, "Lintel", Vector3.new(10, 0.9, 1.1), CFrame.lookAt(mid + Vector3.new(0, 8.6, 0), mid + Vector3.new(0, 8.6, 0) + side) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
	local sun = part(model, "Sun", Vector3.new(0.5, 3, 3), CFrame.lookAt(mid + Vector3.new(0, 10, 0), mid + Vector3.new(0, 10, 0) + dir) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 210, 70), Enum.Material.Neon, Enum.PartType.Cylinder)
	sun.CastShadow = false
end

-- Sundial pavilion: marble dais in the pool, ring of columns, gold dial and gnomon, banners.
local function sundialPavilion(parent, at: Vector3)
	local model = group(parent, "SundialPavilion")
	column(model, "Base", 30, at.Y - 2, at.Y + 1, at, STONE, Enum.Material.Cobblestone)
	column(model, "Dais", 22, at.Y + 1, at.Y + 3.4, at, Color3.fromRGB(250, 246, 236), Enum.Material.Marble)
	column(model, "Face", 16, at.Y + 3.4, at.Y + 4.2, at, GOLD, Enum.Material.Metal)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part(model, "Hour" .. i, Vector3.new(0.3, 0.2, 1.6), CFrame.new(at + Vector3.new(math.cos(a) * 6.6, 4.3, math.sin(a) * 6.6)) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(130, 80, 30), Enum.Material.Metal)
	end
	part(model, "Gnomon", Vector3.new(1, 8, 8), CFrame.new(at + Vector3.new(0, 8.2, 0)) * CFrame.Angles(0, math.rad(35), 0), GOLD, Enum.Material.Metal, Enum.PartType.Wedge)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = at + Vector3.new(math.cos(a) * 10.2, 0, math.sin(a) * 10.2)
		column(model, "Pillar" .. i, 1.3, at.Y + 3.4, at.Y + 12, p, Color3.fromRGB(250, 246, 236), Enum.Material.Marble)
		ball(model, "PillarCap" .. i, 1.8, p + Vector3.new(0, 12.4 - p.Y + at.Y, 0), GOLD, Enum.Material.Metal)
	end
	-- Open gold ring on the pillars (segments, so the dial stays visible from above)
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2
		local p = at + Vector3.new(math.cos(a) * 10.2, 12.4, math.sin(a) * 10.2)
		part(model, "Ring" .. i, Vector3.new(1.4, 0.9, 4.3), CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), GOLD, Enum.Material.Metal)
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local p = at + Vector3.new(math.cos(a) * 14.5, 0, math.sin(a) * 14.5)
		column(model, "BannerPole" .. i, 0.5, at.Y, at.Y + 13, p, GOLD, Enum.Material.Metal)
		part(model, "Banner" .. i, Vector3.new(2.6, 6, 0.2), CFrame.lookAt(p + Vector3.new(0, 9, 0), at + Vector3.new(0, 9, 0)) * CFrame.new(1.4, 0, 0), Color3.fromRGB(60, 90, 200), Enum.Material.Fabric)
	end
	local glow = Instance.new("PointLight")
	glow.Range = 24
	glow.Brightness = 1.2
	glow.Color = Color3.fromRGB(255, 215, 120)
	glow.Parent = model:FindFirstChild("Face")
end

-- A small floating island for the backdrop: grass top, tapering rock, trees, maybe a cottage.
local function floatingIsland(parent, at: Vector3, size: number, rng)
	local model = group(parent, "FloatingIsland")
	column(model, "Grass", size, at.Y - 1.5, at.Y, at, GRASS, Enum.Material.Grass)
	local d, y = size - 1, at.Y - 1.5
	for i = 1, 4 do
		local h = size * 0.28
		column(model, "Rock" .. i, d, y - h, y, at + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), if i % 2 == 0 then ROCK else ROCK_DARK, Enum.Material.Rock)
		y -= h
		d *= 0.68
	end
	local trees = rng:NextInteger(1, 3)
	for _ = 1, trees do
		local p = at + Vector3.new(rng:NextNumber(-0.3, 0.3) * size, 0, rng:NextNumber(-0.3, 0.3) * size)
		roundTree(model, p, size / 16, rng)
	end
	if rng:NextNumber() < 0.6 then
		cottage(model, at + Vector3.new(size * 0.15, 0, -size * 0.1), at + Vector3.new(0, 0, 50), rng, if rng:NextNumber() < 0.5 then ROOF_RED else ROOF_BLUE)
	end
	return model
end

local function cloud(parent, at: Vector3, size: number, rng)
	local model = group(parent, "Cloud")
	for i = 1, 5 do
		local s = size * rng:NextNumber(0.5, 1)
		local c = ball(model, "Puff", s, at + Vector3.new(rng:NextNumber(-1, 1) * size, rng:NextNumber(-0.2, 0.3) * size, rng:NextNumber(-0.6, 0.6) * size), Color3.fromRGB(255, 255, 255))
		c.CastShadow = false
		c.Transparency = 0.08
	end
end

local function waterfall(parent, top: Vector3, width: number, drop: number, facing: Vector3)
	local cf = CFrame.lookAt(top, top + facing)
	local fall = part(parent, "Waterfall", Vector3.new(width, drop, 1.2), cf * CFrame.new(0, -drop / 2, -0.8), Color3.fromRGB(150, 220, 255), Enum.Material.Glass)
	fall.Transparency = 0.15
	fall.CastShadow = false
	local foam = part(parent, "Foam", Vector3.new(width + 1, 1, 2), cf * CFrame.new(0, 0, -0.6), Color3.fromRGB(240, 250, 255), Enum.Material.SmoothPlastic)
	foam.CastShadow = false
	local mist = Instance.new("ParticleEmitter")
	mist.Rate = 6
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Speed = NumberRange.new(1, 3)
	mist.Size = NumberSequence.new(3, 6)
	mist.Transparency = NumberSequence.new(0.6, 1)
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1))
	mist.Parent = fall
	return fall
end

-- Geometry helpers -----------------------------------------------------------------------------

local function flat(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

local function segmentDistance(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local t = if ab.Magnitude < 1e-3 then 0 else math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function Scene.build(world)
	local folder = world.Folder
	local at = world.WorldAt
	local board = world.Board
	local scene = group(folder, "SkyGarden")
	local rng = Random.new(20261018)

	-- Sunny day (applied while the board is on screen; BoardWorld restores the old values).
	world.LightingPreset = {
		ClockTime = 14.2,
		Brightness = 2.8,
		Ambient = Color3.fromRGB(150, 140, 120),
		OutdoorAmbient = Color3.fromRGB(175, 165, 145),
	}
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "SkyGardenAtmosphere"
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(205, 230, 255)
	atmosphere.Decay = Color3.fromRGB(120, 170, 230)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SkyGardenGrade"
	grade.Saturation = 0.18
	grade.Contrast = 0.06
	grade.Brightness = 0.02
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SkyGardenBloom"
	bloom.Intensity = 0.35
	bloom.Size = 20
	bloom.Threshold = 1.6
	world.LightingChildren = { atmosphere, grade, bloom }

	-- Spaces, paths and landmark positions in world space ---------------------------------------
	local spaces = {} -- { Pos, H, Area, Bridge }
	local segments = {} -- { A, B, HA, HB, Bridge }
	for _, id in board.Order do
		local space = board.Spaces[id]
		local p = at(space.At)
		local bridge = space.Landmark == "SundialBridge" or space.Landmark == "SundialPavilion"
		table.insert(spaces, { Id = id, Pos = p, H = p.Y, Area = space.Area, Bridge = bridge })
	end
	local byId = {}
	for _, s in spaces do
		byId[s.Id] = s
	end
	for _, s in spaces do
		for _, n in board.Spaces[s.Id].Next do
			local t = byId[n]
			table.insert(segments, { A = flat(s.Pos), B = flat(t.Pos), HA = s.H, HB = t.H, Bridge = s.Bridge or t.Bridge })
		end
	end
	local function pathDistance(p: Vector2, includeBridge: boolean?): (number, any)
		local best, seg = math.huge, nil
		for _, g in segments do
			if includeBridge or not g.Bridge then
				local d = segmentDistance(p, g.A, g.B)
				if d < best then
					best, seg = d, g
				end
			end
		end
		return best, seg
	end
	-- True when `p` sits between the board camera (south, +Z) and a nearby path: only low
	-- things (flowers, bushes, rocks) go there so pieces and spaces stay in view.
	local function inFrontOfPath(p: Vector2): boolean
		for _, g in segments do
			local ab = g.B - g.A
			local t = math.clamp((p - g.A):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
			local closest = g.A + ab * t
			local away = p - closest
			if away.Magnitude < 20 and away.Y > 2 then
				return true
			end
		end
		return false
	end
	local function nearestSpace(p: Vector2)
		local best, found = math.huge, nil
		for _, s in spaces do
			if not s.Bridge then
				local d = (flat(s.Pos) - p).Magnitude
				if d < best then
					best, found = d, s
				end
			end
		end
		return found, best
	end

	local pool = at({ 0.1, -1.1, 0 })
	local poolR = 30
	-- Stream channels: pool -> south edge waterfall, pool -> mill.
	local channels = {
		{ flat(pool), flat(at({ 0.55, -6.3, 0 })) },
		{ flat(pool), flat(at({ 3.55, 0.75, 0 })) },
	}
	local function inWater(p: Vector2): boolean
		if (p - flat(pool)).Magnitude < poolR then
			return true
		end
		for _, c in channels do
			if segmentDistance(p, c[1], c[2]) < 6 then
				return true
			end
		end
		return false
	end

	-- Landmarks: position, ground height, clear radius (no scatter inside)
	local L = {
		Market = { Pos = at({ -6.35, -1.95, 0 }), R = 11 },
		Crown = { Pos = at({ 1.05, 6.35, 10 }), R = 10 },
		Stage = { Pos = at({ 0.55, 2.4, 6 }), R = 10 },
		Tent = { Pos = at({ -2.75, 5.15, 5 }), R = 13 },
		Kiosk = { Pos = at({ 2.75, 5.85, 9 }), R = 6 },
		Bell = { Pos = at({ 3.75, 4.95, 6 }), R = 5 },
		Mill = { Pos = at({ 4.05, 1.25, 1 }), R = 10 },
		SpringW = { Pos = at({ -6.6, 1.9, 0 }), R = 6 },
		SpringE = { Pos = at({ 6.0, -2.2, 0 }), R = 6 },
	}
	local reserved = { { Pos = flat(pool), R = 17 } }
	for _, l in L do
		table.insert(reserved, { Pos = flat(l.Pos), R = l.R })
	end
	local function isReserved(p: Vector2, pad: number): boolean
		for _, r in reserved do
			if (p - r.Pos).Magnitude < r.R + pad then
				return true
			end
		end
		return false
	end

	-- Island ground: a grid of overlapping columns; each takes its nearest space's height --------
	local island = group(scene, "Island")
	local cells = {}
	local STEP = 8
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, s in spaces do
		minX, maxX = math.min(minX, s.Pos.X), math.max(maxX, s.Pos.X)
		minZ, maxZ = math.min(minZ, s.Pos.Z), math.max(maxZ, s.Pos.Z)
	end
	local inside = {}
	local function key(ix, iz)
		return ix * 1000 + iz
	end
	local function footprint(p: Vector2): boolean
		local s, d = nearestSpace(p)
		if s and d < 22 then
			return true
		end
		if (p - flat(pool)).Magnitude < poolR + 6 then
			return true
		end
		for _, l in L do
			if (p - flat(l.Pos)).Magnitude < l.R + 4 then
				return true
			end
		end
		return false
	end
	local ix0, iz0 = math.floor((minX - 30) / STEP), math.floor((minZ - 30) / STEP)
	local ix1, iz1 = math.ceil((maxX + 30) / STEP), math.ceil((maxZ + 30) / STEP)
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			local p = Vector2.new(ix * STEP, iz * STEP)
			if footprint(p) then
				inside[key(ix, iz)] = true
			end
		end
	end
	-- Board base height (a space's world Y minus its own height)
	local islandY = spaces[1].Pos.Y - (board.Spaces[spaces[1].Id].At[3] or 0)
	local function heightAt(p: Vector2): number
		if inWater(p) then
			return islandY - 2
		end
		for _, l in L do
			if (p - flat(l.Pos)).Magnitude < l.R then
				return l.Pos.Y
			end
		end
		local d, seg = pathDistance(p)
		if d < 7 and seg then
			return math.min(seg.HA, seg.HB)
		end
		local s = nearestSpace(p)
		return s and s.H or islandY
	end
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			if not inside[key(ix, iz)] then
				continue
			end
			local p = Vector2.new(ix * STEP, iz * STEP)
			local top = heightAt(p)
			local edge = not (inside[key(ix + 1, iz)] and inside[key(ix - 1, iz)] and inside[key(ix, iz + 1)] and inside[key(ix, iz - 1)])
			local centre = Vector3.new(p.X, 0, p.Y)
			local wet = inWater(p)
			local g = column(island, "Ground", STEP + 3.5, top - 1, top, centre, if wet then ROCK_DARK elseif (ix + iz) % 3 == 0 then GRASS_DARK else GRASS, if wet then Enum.Material.Slate else Enum.Material.Grass)
			g.CastShadow = false
			local bottom = if edge then islandY - rng:NextNumber(14, 26) else islandY - 7
			column(island, "Cliff", STEP + (if edge then 2.5 else 3), bottom, top - 1, centre, if (ix * 7 + iz) % 2 == 0 then ROCK else ROCK_DARK, Enum.Material.Rock)
			if edge then
				-- hanging rock under the rim
				local hang = rng:NextNumber(8, 20)
				column(island, "Hang", STEP * 0.7, bottom - hang, bottom, centre + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), ROCK_DARK, Enum.Material.Rock)
			end
		end
	end
	-- Medallion seats: a grass pad under every space at its height, bridge piers in stone
	for _, s in spaces do
		if s.Bridge then
			column(island, "Pier", 3.6, islandY - 4, s.H, s.Pos, STONE, Enum.Material.Cobblestone)
		else
			ground(island, s.Pos, 15, s.H)
		end
	end
	-- Big rocks hanging under the island
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local c = flat(pool) + Vector2.new(math.cos(a) * 28, math.sin(a) * 26)
		local d, y = rng:NextNumber(18, 26), islandY - 20
		for t = 1, 4 do
			local h = rng:NextNumber(8, 12)
			column(island, "Underrock", d, y - h, y, Vector3.new(c.X, 0, c.Y), if t % 2 == 0 then ROCK else ROCK_DARK, Enum.Material.Rock)
			y -= h
			d *= 0.62
		end
	end

	-- Water ---------------------------------------------------------------------------------------
	local water = group(scene, "Water")
	local poolPart = column(water, "Pool", poolR * 2 + 2, islandY - 1.2, islandY - 0.25, pool, WATER, Enum.Material.Glass)
	poolPart.Transparency = 0.2
	poolPart.CastShadow = false
	for _, c in channels do
		local a, b = Vector3.new(c[1].X, islandY - 0.3, c[1].Y), Vector3.new(c[2].X, islandY - 0.3, c[2].Y)
		local w = part(water, "Channel", Vector3.new(11, 0.9, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), WATER, Enum.Material.Glass)
		w.Transparency = 0.2
		w.CastShadow = false
	end
	local southEdge = at({ 0.55, -6.3, 0 })
	waterfall(water, Vector3.new(southEdge.X, islandY - 0.3, southEdge.Z) + Vector3.new(0, 0, 4), 10, 38, Vector3.new(0, 0, -1))
	-- Two more springs on the rim: a small pond that spills over the cliff (orchard, village)
	for _, spring in { { -6.6, 1.9 }, { 6.0, -2.2 } } do
		local p = at({ spring[1], spring[2], 0 })
		local pond = column(water, "Spring", 9, islandY - 0.6, islandY + 0.15, p, WATER, Enum.Material.Glass)
		pond.Transparency = 0.2
		pond.CastShadow = false
		local out = Vector3.new(p.X - pool.X, 0, p.Z - pool.Z).Unit
		waterfall(water, Vector3.new(p.X, islandY + 0.1, p.Z) + out * 9, 6, 30, -out)
		local brook = part(water, "Brook", Vector3.new(5, 0.5, 10), CFrame.lookAt(Vector3.new(p.X, islandY + 0.05, p.Z) + out * 5, Vector3.new(p.X, islandY + 0.05, p.Z) + out * 10), WATER, Enum.Material.Glass)
		brook.Transparency = 0.2
		brook.CastShadow = false
	end

	-- Lily pads and stepping rocks in the pool
	for i = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(17, poolR - 3)
		local p = pool + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if pathDistance(flat(p), true) > 6 then
			if i % 3 == 0 then
				rock(water, Vector3.new(p.X, islandY - 0.8, p.Z), rng)
			else
				local pad = column(water, "LilyPad", rng:NextNumber(2, 3.2), islandY - 0.3, islandY - 0.1, p, Color3.fromRGB(90, 180, 90), Enum.Material.Grass)
				pad.CastShadow = false
				if i % 2 == 0 then
					ball(water, "Lily", 0.9, Vector3.new(p.X, islandY + 0.1, p.Z), FLOWERS[1]).CastShadow = false
				end
			end
		end
	end

	-- Landmarks -----------------------------------------------------------------------------------
	local marks = group(scene, "Landmarks")
	sundialPavilion(marks, Vector3.new(pool.X, islandY, pool.Z))
	market(marks, L.Market.Pos, at(board.Spaces[7].At) + Vector3.new(0, 0, 14))
	crownPavilion(marks, L.Crown.Pos, at(board.Spaces[39].At))
	stage(marks, L.Stage.Pos, at(board.Spaces[16].At))
	circusTent(marks, L.Tent.Pos)
	kiosk(marks, L.Kiosk.Pos)
	bellTower(marks, L.Bell.Pos)
	waterwheelMill(marks, L.Mill.Pos, at({ 3.55, 0.75, 0 }) - Vector3.new(3, 0, 0))
	sunGate(marks, at(board.Spaces[29].At), at(board.Spaces[1].At))
	-- Signposts at the three forks, each board pointing at its route
	for _, fork in { { 5, 6, 30, "Market Lane", "Hillside Steps" }, { 12, 13, 33, "Fairground", "Sundial Bridge" }, { 15, 16, 38, "Fair Midway", "Crown Terrace" } } do
		local base = at(board.Spaces[fork[1]].At)
		local a, b = at(board.Spaces[fork[2]].At), at(board.Spaces[fork[3]].At)
		local away = (base - (a + b) / 2)
		away = Vector3.new(away.X, 0, away.Z)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
		local side = Vector3.new(-away.Z, 0, away.X)
		signpost(marks, base + side * 7 + away * 2, {
			{ Label = fork[4], Toward = a, Color = Color3.fromRGB(255, 236, 190) },
			{ Label = fork[5], Toward = b, Color = Color3.fromRGB(214, 240, 200) },
		})
	end
	-- Sundial Bridge: stone railings with gold caps along every bridge segment
	for _, g in segments do
		if g.Bridge then
			local a = Vector3.new(g.A.X, g.HA + 1.2, g.A.Y)
			local b = Vector3.new(g.B.X, g.HB + 1.2, g.B.Y)
			local dir = (b - a)
			local side = Vector3.new(-dir.Z, 0, dir.X).Unit
			for s = -1, 1, 2 do
				local p0, p1 = a + side * s * 3, b + side * s * 3
				part(marks, "Rail", Vector3.new(0.7, 1.6, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2 + Vector3.new(0, 0.6, 0), p1 + Vector3.new(0, 0.6, 0)), STONE, Enum.Material.Marble)
				ball(marks, "RailCap", 1.1, p0 + Vector3.new(0, 1.7, 0), GOLD, Enum.Material.Metal)
			end
			local mid = (a + b) / 2
			part(marks, "Arch", Vector3.new(5, 2, (b - a).Magnitude * 0.9), CFrame.lookAt(mid - Vector3.new(0, 2.2, 0), b - Vector3.new(0, 2.2, 0)), STONE, Enum.Material.Cobblestone)
		end
	end

	-- Path dressing: fences on the outer side, lamps every few spaces --------------------------------
	local dressing = group(scene, "PathDressing")
	local islandCentre = flat(pool)
	for i, g in segments do
		if g.Bridge or math.abs(g.HA - g.HB) > 0.5 then
			continue
		end
		local mid = (g.A + g.B) / 2
		local dir = (g.B - g.A).Unit
		local side = Vector2.new(-dir.Y, dir.X)
		if (mid + side - islandCentre).Magnitude < (mid - islandCentre).Magnitude then
			side = -side
		end
		local o = side * 4.6
		if i % 2 == 0 then
			local a = g.A:Lerp(g.B, 0.28) + o
			local b = g.A:Lerp(g.B, 0.72) + o
			fence(dressing, Vector3.new(a.X, g.HA, a.Y), Vector3.new(b.X, g.HA, b.Y))
		elseif i % 5 == 1 then
			local p = mid + side * 5
			lamp(dressing, Vector3.new(p.X, g.HA, p.Y))
		end
	end

	-- Scatter: themed planting and props on every free patch -------------------------------------
	local life = group(scene, "Life")
	local SCATTER = 6
	for ix = math.floor((minX - 30) / SCATTER), math.ceil((maxX + 30) / SCATTER) do
		for iz = math.floor((minZ - 30) / SCATTER), math.ceil((maxZ + 30) / SCATTER) do
			local p = Vector2.new(ix * SCATTER + rng:NextNumber(-2, 2), iz * SCATTER + rng:NextNumber(-2, 2))
			local cell = inside[key(math.round(p.X / STEP), math.round(p.Y / STEP))]
			if not cell or inWater(p) then
				continue
			end
			local d = pathDistance(p, true)
			if d < 7.5 or isReserved(p, 2) then
				continue
			end
			local s = nearestSpace(p)
			local area = s and s.Area or "Stream"
			local y = heightAt(p)
			local pos = Vector3.new(p.X, y, p.Y)
			local roll = rng:NextNumber()
			if inFrontOfPath(p) then
				if roll < 0.45 then
					flowerBed(life, pos, rng)
				elseif roll < 0.8 then
					bush(life, pos, rng)
				elseif area == "Orchard" then
					crate(life, pos, rng)
				else
					rock(life, pos, rng, 0.7)
				end
			elseif area == "Orchard" then
				if roll < 0.32 then
					tree(life, pos, rng:NextNumber(0.75, 1))
				elseif roll < 0.5 then
					crate(life, pos, rng)
				elseif roll < 0.75 then
					flowerBed(life, pos, rng)
				else
					bush(life, pos, rng)
				end
			elseif area == "Fair" then
				if roll < 0.14 then
					booth(life, pos, s.Pos, STRIPES[rng:NextInteger(1, #STRIPES)])
				elseif roll < 0.3 then
					balloon(life, pos, rng)
				elseif roll < 0.48 then
					roundTree(life, pos, rng:NextNumber(0.8, 1.1), rng, rng:NextNumber() < 0.45)
				elseif roll < 0.75 then
					flowerBed(life, pos, rng)
				else
					bush(life, pos, rng)
				end
			elseif area == "Village" then
				if roll < 0.12 and d > 11 then
					cottage(life, pos, s.Pos, rng, if rng:NextNumber() < 0.5 then ROOF_RED else ROOF_BLUE)
				elseif roll < 0.38 then
					if rng:NextNumber() < 0.4 then
						pineTree(life, pos, rng:NextNumber(0.9, 1.2))
					else
						roundTree(life, pos, rng:NextNumber(0.8, 1.1), rng, rng:NextNumber() < 0.3)
					end
				elseif roll < 0.62 then
					flowerBed(life, pos, rng)
				else
					bush(life, pos, rng)
				end
			else -- Stream walk
				if roll < 0.25 then
					roundTree(life, pos, rng:NextNumber(0.8, 1.1), rng, rng:NextNumber() < 0.2)
				elseif roll < 0.45 then
					rock(life, pos, rng)
				elseif roll < 0.75 then
					flowerBed(life, pos, rng)
				else
					bush(life, pos, rng)
				end
			end
		end
	end
	-- Fairground bunting between landmark poles
	local fairA, fairB = L.Tent.Pos, L.Stage.Pos
	bunting(life, fairA + Vector3.new(11, 0, 8), fairB + Vector3.new(-8, 0, -4), rng)
	bunting(life, L.Stage.Pos + Vector3.new(8, 0, -5), L.Bell.Pos + Vector3.new(-4, 0, 4), rng)
	bunting(life, L.Crown.Pos + Vector3.new(-9, 0, 2), L.Tent.Pos + Vector3.new(12, 0, -3), rng)

	-- Background: floating islands and a sea of clouds all round -----------------------------------
	local back = group(scene, "Backdrop")
	local centre = Vector3.new(pool.X, islandY, pool.Z)
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = rng:NextNumber(150, 260)
		local y = islandY + rng:NextNumber(-35, 45)
		floatingIsland(back, centre + Vector3.new(math.cos(a) * r, y - islandY, math.sin(a) * r), rng:NextNumber(18, 34), rng)
	end
	for i = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(90, 320)
		cloud(back, centre + Vector3.new(math.cos(a) * r, rng:NextNumber(-75, -45), math.sin(a) * r), rng:NextNumber(14, 28), rng)
	end
	for i = 1, 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(200, 340)
		cloud(back, centre + Vector3.new(math.cos(a) * r, rng:NextNumber(10, 60), math.sin(a) * r), rng:NextNumber(10, 20), rng)
	end
	-- A deep layer of big low clouds instead of a flat floor (fills the space under the board)
	for i = 1, 36 do
		local a = i / 36 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(40, 230)
		cloud(back, centre + Vector3.new(math.cos(a) * r, rng:NextNumber(-110, -80), math.sin(a) * r), rng:NextNumber(26, 40), rng)
	end

	return scene
end

return Scene
