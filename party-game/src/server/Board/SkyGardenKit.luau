--[[
	SkyGardenKit
	Refined, reusable decoration pieces for the Sunny Loop sky-garden (Studio build of the
	Blender kit in art/blender/sunny_loop/, same proportions and names so the meshes can replace
	these later). Shape language: faceted, chunky, asymmetric forms instead of spheres.

	  Kit.tree(parent, at, variant, rng, scale?)     variant "Orchard" | "Riverside" | "Fair"
	  Kit.bush(parent, at, rng)                      2-3 faceted leaf masses, sometimes berries
	  Kit.flowerBed(parent, at, rng, colours, shape) petal flowers + leaf tufts, "Round" | "Long"
	  Kit.rockCluster(parent, at, rng, scale?)       2-4 faceted stones in the cliff palette
	  Kit.strata(parent, centre, diameter, bottom, top, rng)  banded cliff with a ledge
	  Kit.pathEdge(parent, a, b, width)              kerbs, seams and an occasional motif
	  Kit.shoreFoam(parent, centre, radius, y)       broken foam ring at a water edge
	  Kit.reeds(parent, at, rng)

	Every part is decoration: no collision, queries or touches; small pieces cast no shadow.
	Materials are textured (Grass, Slate, Wood, Cobblestone...) in mid-tone colours, so lighting
	gives depth without the flat-plastic look; colours stay lively but not fluorescent.
]]

local Kit = {}

-- Areas built with the refined kit (vertical slice was the orchard; approved and extended to
-- every area). Remove an area to compare against the earlier blockout.
Kit.RefinedAreas = { Orchard = true, Stream = true, Village = true, Fair = true }
Kit.RefineAll = false

function Kit.isRefined(area: string?): boolean
	return Kit.RefineAll or (area ~= nil and Kit.RefinedAreas[area] == true)
end

-- Palette (mid-tone: reads saturated under warm light without clipping) -------------------------

Kit.Colors = {
	Bark = Color3.fromRGB(122, 82, 56),
	BarkLight = Color3.fromRGB(150, 104, 70),
	Stone = Color3.fromRGB(214, 168, 120),
	StoneDark = Color3.fromRGB(176, 128, 96),
	StoneRose = Color3.fromRGB(196, 136, 124),
	StoneLight = Color3.fromRGB(232, 200, 160),
	Moss = Color3.fromRGB(96, 160, 64),
	Path = Color3.fromRGB(236, 214, 170),
	PathKerb = Color3.fromRGB(196, 158, 110),
	PathSeam = Color3.fromRGB(206, 178, 132),
	Foam = Color3.fromRGB(236, 248, 250),
	Reed = Color3.fromRGB(116, 168, 70),
}
local C = Kit.Colors

-- Canopy colour families per tree variant: { shade, mid, light } (lower masses darker)
local CANOPIES = {
	Orchard = {
		{ Color3.fromRGB(78, 150, 52), Color3.fromRGB(104, 176, 58), Color3.fromRGB(138, 196, 70) },
		{ Color3.fromRGB(64, 140, 70), Color3.fromRGB(88, 166, 74), Color3.fromRGB(122, 188, 84) },
	},
	Riverside = {
		{ Color3.fromRGB(48, 138, 98), Color3.fromRGB(70, 160, 112), Color3.fromRGB(104, 184, 128) },
		{ Color3.fromRGB(60, 132, 84), Color3.fromRGB(82, 156, 96), Color3.fromRGB(118, 180, 104) },
	},
	Fair = {
		{ Color3.fromRGB(196, 92, 136), Color3.fromRGB(224, 126, 166), Color3.fromRGB(240, 166, 196) },
		{ Color3.fromRGB(206, 150, 46), Color3.fromRGB(230, 182, 64), Color3.fromRGB(244, 210, 104) },
		{ Color3.fromRGB(70, 150, 66), Color3.fromRGB(96, 174, 72), Color3.fromRGB(132, 194, 86) },
	},
}
local FRUIT = { Color3.fromRGB(220, 52, 52), Color3.fromRGB(240, 128, 36), Color3.fromRGB(240, 196, 40) }

-- Basics ------------------------------------------------------------------------------------

local function part(parent, name, size: Vector3, cframe: CFrame, color: Color3, material, shape)
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
Kit.part = part

local function group(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A faceted mass: a cube turned on two axes reads as a chunky low-poly lump, not a ball.
local function facet(parent, name, size: Vector3, at: Vector3, color, material, rng)
	local cf = CFrame.new(at) * CFrame.Angles(rng:NextNumber(0.35, 0.8), rng:NextNumber(0, math.pi), rng:NextNumber(0.25, 0.7))
	return part(parent, name, size, cf, color, material)
end

local function upright(parent, name, d: number, bottom: number, top: number, at: Vector3, color, material)
	local h = top - bottom
	return part(parent, name, Vector3.new(h, d, d), CFrame.new(at.X, bottom + h / 2, at.Z) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

-- Trees ----------------------------------------------------------------------------------------

--[[
	Tapered trunk (two sections), one or two branches, 2-4 asymmetric faceted canopy masses
	stacked low-dark to high-light. Orchard trees are short and wide with a little fruit;
	riverside trees are tall and narrow and lean; fair trees are round-topped blossom/golden.
]]
function Kit.tree(parent, at: Vector3, variant: string, rng, scale: number?)
	local s = scale or 1
	local model = group(parent, variant .. "Tree")
	local families = CANOPIES[variant] or CANOPIES.Orchard
	local colours = families[rng:NextInteger(1, #families)]
	local tall = variant == "Riverside"
	local h = (if tall then rng:NextNumber(7, 9) elseif variant == "Fair" then rng:NextNumber(5, 6.5) else rng:NextNumber(4, 5.2)) * s
	local lean = CFrame.Angles(rng:NextNumber(-0.16, 0.16), rng:NextNumber(0, 6.28), rng:NextNumber(-0.16, 0.16)) * (if tall then CFrame.Angles(0.12, 0, 0) else CFrame.new())
	local base = CFrame.new(at) * lean
	-- trunk: lower thick, upper thin
	part(model, "TrunkLow", Vector3.new(1.5 * s, h * 0.55, 1.5 * s), base * CFrame.new(0, h * 0.275, 0) * CFrame.Angles(0, 0.4, 0), C.Bark, Enum.Material.Wood)
	part(model, "TrunkHigh", Vector3.new(1.05 * s, h * 0.55, 1.05 * s), base * CFrame.new(0, h * 0.75, 0) * CFrame.Angles(0, 1.1, 0), C.BarkLight, Enum.Material.Wood)
	part(model, "Root", Vector3.new(2.4 * s, 0.6 * s, 2.4 * s), base * CFrame.new(0, 0.3 * s, 0) * CFrame.Angles(0, 0.8, 0), C.Bark, Enum.Material.Wood)
	local top = (base * CFrame.new(0, h, 0)).Position
	-- branches
	for k = 1, rng:NextInteger(1, 2) do
		local a = rng:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(a), 0.9, math.sin(a)).Unit
		local from = (base * CFrame.new(0, h * rng:NextNumber(0.55, 0.75), 0)).Position
		local len = 2.6 * s
		part(model, "Branch" .. k, Vector3.new(0.55 * s, 0.55 * s, len), CFrame.lookAt(from + dir * len / 2, from + dir * len), C.Bark, Enum.Material.Wood)
	end
	-- Canopy: 2-4 asymmetric clumps. Each clump = a flattened faceted body (shade underneath)
	-- with a lighter pyramid cap, so the outline is a lumpy crown, not a ball or a box.
	local width = (if tall then 4.2 elseif variant == "Orchard" then 5.6 else 5) * s
	local masses = rng:NextInteger(2, 4)
	local spin = rng:NextNumber(0, math.pi * 2)
	for k = 1, masses do
		local a = spin + k / masses * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local r = if k == 1 then 0 else width * rng:NextNumber(0.35, 0.55)
		local sz = width * (if k == 1 then 1 else rng:NextNumber(0.6, 0.8))
		local y = if k == 1 then width * 0.2 else width * rng:NextNumber(-0.1, 0.45)
		if tall then
			y += (k - 1) * width * 0.35
		end
		local c = top + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
		local yaw = CFrame.new(c) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6.28), rng:NextNumber(-0.15, 0.15))
		local body = part(model, "Clump" .. k, Vector3.new(sz, sz * 0.62, sz * 0.9), yaw, colours[if k == 1 then 2 else 1], Enum.Material.Grass)
		body.CastShadow = k == 1
		-- octagonal look: a second body turned 45 degrees
		part(model, "Clump" .. k .. "b", Vector3.new(sz * 0.86, sz * 0.66, sz * 0.78), yaw * CFrame.Angles(0, math.pi / 4, 0) * CFrame.new(0, sz * 0.05, 0), colours[2], Enum.Material.Grass).CastShadow = false
		local cap = part(model, "Cap" .. k, Vector3.new(sz * 0.72, sz * 0.42, sz * 0.66), yaw * CFrame.new(0, sz * 0.48, 0), colours[3], Enum.Material.Grass)
		cap.CastShadow = false
		cap.Shape = Enum.PartType.Block
		local tip = part(model, "Tip" .. k, Vector3.new(sz * 0.5, sz * 0.3, sz * 0.45), yaw * CFrame.new(0, sz * 0.78, 0) * CFrame.Angles(0, math.pi / 4, 0), colours[3]:Lerp(Color3.fromRGB(255, 250, 200), 0.12), Enum.Material.Grass)
		tip.CastShadow = false
	end
	if variant == "Orchard" and rng:NextNumber() < 0.6 then
		local fruit = FRUIT[rng:NextInteger(1, #FRUIT)]
		for k = 1, rng:NextInteger(2, 3) do
			local a = rng:NextNumber(0, math.pi * 2)
			local p = top + Vector3.new(math.cos(a) * width * 0.5, width * rng:NextNumber(0, 0.3), math.sin(a) * width * 0.5)
			local f = part(model, "Fruit" .. k, Vector3.one * 1.1 * s, CFrame.new(p), fruit, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			f.CastShadow = false
		end
	end
	return model
end

-- Bushes and flowers ------------------------------------------------------------------------------

function Kit.bush(parent, at: Vector3, rng)
	local model = group(parent, "Bush")
	local colours = CANOPIES.Orchard[rng:NextInteger(1, 2)]
	local s = rng:NextNumber(2.4, 3.6)
	facet(model, "Mass1", Vector3.new(s * 1.3, s * 0.8, s), at + Vector3.new(0, s * 0.3, 0), colours[2], Enum.Material.Grass, rng).CastShadow = false
	facet(model, "Mass2", Vector3.new(s * 0.8, s * 0.7, s * 0.8), at + Vector3.new(s * 0.45, s * 0.55, s * 0.1), colours[3], Enum.Material.Grass, rng).CastShadow = false
	if rng:NextNumber() < 0.5 then
		facet(model, "Mass3", Vector3.new(s * 0.7, s * 0.55, s * 0.7), at + Vector3.new(-s * 0.5, s * 0.25, -s * 0.2), colours[1], Enum.Material.Grass, rng).CastShadow = false
	end
	return model
end

-- One stylised flower: stem, five petals in a cup, a centre. ~7 parts.
local function flower(parent, at: Vector3, colour: Color3, size: number, rng)
	local stemH = size * rng:NextNumber(1.2, 1.8)
	part(parent, "Stem", Vector3.new(0.18, stemH, 0.18), CFrame.new(at + Vector3.new(0, stemH / 2, 0)), C.Reed).CastShadow = false
	local head = at + Vector3.new(0, stemH, 0)
	local spin = rng:NextNumber(0, 6.28)
	for k = 0, 4 do
		local a = spin + k / 5 * math.pi * 2
		local p = part(parent, "Petal", Vector3.new(size * 0.55, 0.14, size * 0.32), CFrame.new(head) * CFrame.Angles(0, a, 0) * CFrame.new(size * 0.3, 0, 0) * CFrame.Angles(0, 0, 0.35), colour, Enum.Material.SmoothPlastic)
		p.CastShadow = false
	end
	part(parent, "Centre", Vector3.new(size * 0.28, 0.22, size * 0.28), CFrame.new(head + Vector3.new(0, 0.08, 0)), Color3.fromRGB(250, 214, 80), Enum.Material.SmoothPlastic).CastShadow = false
end

-- Leaf tuft: three blades fanning out.
local function tuft(parent, at: Vector3, rng)
	for k = 0, 2 do
		local a = rng:NextNumber(0, 6.28)
		local blade = part(parent, "Leaf", Vector3.new(0.2, 1.5, 0.6), CFrame.new(at + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, a, rng:NextNumber(0.3, 0.6)), C.Moss, Enum.Material.Grass, Enum.PartType.Wedge)
		blade.CastShadow = false
	end
end

--[[
	A composed bed: a soil-edged base (round or long), 3-5 flowers in one or two colour
	families, leaf tufts between. Fewer, better clusters.
]]
function Kit.flowerBed(parent, at: Vector3, rng, colours, shape: string?)
	local model = group(parent, "FlowerBed")
	local long = shape == "Long"
	local yaw = rng:NextNumber(0, 6.28)
	local bed
	if long then
		bed = part(model, "Bed", Vector3.new(7, 0.45, 3), CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(150, 110, 76), Enum.Material.Ground)
		part(model, "Edging", Vector3.new(7.5, 0.35, 3.5), bed.CFrame * CFrame.new(0, -0.12, 0), Color3.fromRGB(176, 124, 80), Enum.Material.WoodPlanks).CastShadow = false
	else
		bed = part(model, "Bed", Vector3.new(0.45, 4.6, 4.6), CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, yaw, math.pi / 2), Color3.fromRGB(150, 110, 76), Enum.Material.Ground, Enum.PartType.Cylinder)
		part(model, "Edging", Vector3.new(0.35, 5.2, 5.2), bed.CFrame * CFrame.new(-0.12, 0, 0), C.StoneLight, Enum.Material.Cobblestone, Enum.PartType.Cylinder).CastShadow = false
		bed.CFrame = CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 2)
	end
	bed.CastShadow = false
	local main = colours[rng:NextInteger(1, #colours)]
	local accent = colours[rng:NextInteger(1, #colours)]
	local count = if long then 5 else 4
	for k = 1, count do
		local off = if long then Vector3.new(-2.6 + (k - 1) * 1.3, 0, rng:NextNumber(-0.7, 0.7)) else Vector3.new(math.cos(k * 1.7) * 1.4, 0, math.sin(k * 1.7) * 1.4)
		local p = (CFrame.new(at) * CFrame.Angles(0, yaw, 0) * CFrame.new(off)).Position + Vector3.new(0, 0.35, 0)
		flower(model, p, if k % 3 == 0 then accent else main, rng:NextNumber(1.1, 1.5), rng)
	end
	tuft(model, (CFrame.new(at) * CFrame.Angles(0, yaw, 0) * CFrame.new(if long then 2.9 else 0, 0, 0)).Position + Vector3.new(0, 0.3, 0), rng)
	return model
end

-- Rocks and cliffs -------------------------------------------------------------------------------

local STONES = { C.Stone, C.StoneDark, C.StoneRose, C.StoneLight }

function Kit.rockCluster(parent, at: Vector3, rng, scale: number?)
	local model = group(parent, "Rocks")
	local s = scale or 1
	for k = 1, rng:NextInteger(2, 4) do
		local sz = s * rng:NextNumber(1.4, 3.2) * (if k == 1 then 1.3 else 1)
		local p = at + Vector3.new(rng:NextNumber(-1.6, 1.6) * s, sz * 0.25, rng:NextNumber(-1.6, 1.6) * s)
		local r = part(model, "Stone" .. k, Vector3.new(sz * 1.25, sz * 0.9, sz), CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)), STONES[rng:NextInteger(1, #STONES)], Enum.Material.Slate, if k == 2 then Enum.PartType.Wedge else nil)
		r.CastShadow = k == 1
	end
	if rng:NextNumber() < 0.5 then
		tuft(model, at + Vector3.new(1.8 * s, 0, 0.6 * s), rng)
	end
	return model
end

--[[
	Banded cliff column: three strata of different stone, the middle one stepped out as a ledge
	with a moss lip, so island edges read as layered rock instead of a smooth tube.
]]
function Kit.strata(parent, centre: Vector3, diameter: number, bottom: number, top: number, rng)
	local h = top - bottom
	local bands = {
		{ 0.0, 0.34, C.StoneDark, diameter * 0.92 },
		{ 0.34, 0.62, C.Stone, diameter * 1.04 },
		{ 0.62, 1.0, C.StoneRose, diameter },
	}
	local turn = rng:NextInteger(0, 3)
	for k, b in bands do
		local col = bands[(k + turn - 1) % 3 + 1][3]
		upright(parent, "Strata" .. k, b[4], bottom + h * b[1], bottom + h * b[2], centre + Vector3.new(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)), col, Enum.Material.Slate)
	end
	-- moss lip on the ledge
	local ledgeY = bottom + h * 0.62
	upright(parent, "Moss", diameter * 1.06, ledgeY - 0.3, ledgeY + 0.15, centre, C.Moss, Enum.Material.Grass).CastShadow = false
end

-- Paths ---------------------------------------------------------------------------------------------

--[[
	Kerbs both sides (bevelled look: a low dark kerb with a lighter cap), cross seams every
	~3 studs, and an engraved motif (sun disc) on long runs. a, b are path-top points.
]]
function Kit.pathEdge(parent, a: Vector3, b: Vector3, width: number, motif: boolean?)
	local model = group(parent, "PathEdge")
	local dir = b - a
	local len = dir.Magnitude
	if len < 1 then
		return model
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	for s = -1, 1, 2 do
		local kerb = part(model, "Kerb", Vector3.new(0.7, 0.55, len), cf * CFrame.new(s * (width / 2 + 0.2), -0.05, 0), C.PathKerb, Enum.Material.Cobblestone)
		kerb.CastShadow = false
		local cap = part(model, "KerbCap", Vector3.new(0.5, 0.12, len), cf * CFrame.new(s * (width / 2 + 0.2), 0.25, 0), C.StoneLight, Enum.Material.Slate)
		cap.CastShadow = false
	end
	local seams = math.floor(len / 3)
	for k = 1, seams do
		local z = -len / 2 + k * len / (seams + 1)
		local seam = part(model, "Seam", Vector3.new(width - 0.4, 0.06, 0.18), cf * CFrame.new(0, 0.26, z), C.PathSeam, Enum.Material.Slate)
		seam.CastShadow = false
	end
	if motif and len > 6 then
		local sun = part(model, "Motif", Vector3.new(0.06, 2.2, 2.2), cf * CFrame.new(0, 0.27, 0) * CFrame.Angles(0, 0, math.pi / 2), C.PathSeam, Enum.Material.Slate, Enum.PartType.Cylinder)
		sun.CastShadow = false
		for k = 0, 3 do
			local ray = part(model, "MotifRay", Vector3.new(0.3, 0.06, 1.0), cf * CFrame.new(0, 0.27, 0) * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, 0, 1.55), C.PathSeam, Enum.Material.Slate)
			ray.CastShadow = false
		end
	end
	return model
end

-- Water edges ---------------------------------------------------------------------------------------

function Kit.shoreFoam(parent, centre: Vector3, radius: number, y: number, rng)
	local model = group(parent, "Foam")
	local n = math.floor(radius * 0.9)
	for k = 1, n do
		if rng:NextNumber() < 0.7 then
			local a = k / n * math.pi * 2
			local p = Vector3.new(centre.X + math.cos(a) * radius, y, centre.Z + math.sin(a) * radius)
			local f = part(model, "Foam", Vector3.new(0.5, 0.15, rng:NextNumber(2, 3.4)), CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), C.Foam, Enum.Material.SmoothPlastic)
			f.Transparency = 0.15
			f.CastShadow = false
		end
	end
	return model
end

function Kit.reeds(parent, at: Vector3, rng)
	local model = group(parent, "Reeds")
	for k = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(2, 3.4)
		local p = at + Vector3.new(rng:NextNumber(-0.9, 0.9), h / 2, rng:NextNumber(-0.9, 0.9))
		part(model, "Reed", Vector3.new(0.18, h, 0.18), CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), C.Reed, Enum.Material.Grass).CastShadow = false
		if k == 1 then
			part(model, "Cattail", Vector3.new(0.4, 0.9, 0.4), CFrame.new(p + Vector3.new(0, h / 2 + 0.2, 0)), Color3.fromRGB(130, 86, 54), Enum.Material.Fabric).CastShadow = false
		end
	end
	return model
end

-- A waterfall sheet with flowing streaks (Beam texture scrolls on its own, no scripts).
function Kit.flow(parent: BasePart, width: number, height: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, height / 2, -0.7)
	a0.Parent = parent
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -height / 2, -0.7)
	a1.Parent = parent
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 1.1
	beam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = -1.4
	beam.LightEmission = 0.3
	beam.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255))
	beam.Transparency = NumberSequence.new(0.45)
	beam.FaceCamera = false
	beam.Parent = parent
	return beam
end

return Kit
