--[[
 Sunny Loop medallions: Blender mesh slice with the previous visuals as a load fallback.
 The collider, presentation top, paths, attributes and dynamic text retain their contract.
 See docs/medallions-v1/README.md for source/import scale and outstanding rollout gates.
]]

local MedallionKit = {}
local Meshes = require(script.Parent.MedallionMeshes)

--[[
	Vertical layers of a space, in studs above its position. Every visible face of a space sits
	on its own plane, and nothing else (stairs, paths) may share one of these planes nearby:
	  0.295 rim foot top · 0.75 rim band top · 1.00 base top · 1.12 bevel top ·
	  1.16 recess top · 1.20 field top · 1.235 symbol top · 1.265 symbol hole top ·
	  1.275 icon plate (SurfaceGui) · ~1.45 active-space ring (BoardWorld:setActiveSpace)
]]
MedallionKit.LayerPlanes = { 0.295, 0.75, 0.86, 0.91, 1.0, 1.12, 1.16, 1.2, 1.235, 1.24, 1.265, 1.38, 1.445 }

MedallionKit.DIAMETER = 10.5
MedallionKit.TOP = 1.2
MedallionKit.PATH_WIDTH = 4.5

local CERAMIC = Color3.fromRGB(255, 252, 244) -- clean white
local RIM = Color3.fromRGB(255, 196, 52) -- warm gold
local PATH = Color3.fromRGB(255, 234, 178) -- pale golden cream
local PATH_EDGE = Color3.fromRGB(238, 196, 120)
local STEP_COLOUR = Color3.fromRGB(255, 224, 160)

-- Shape and glyph per space type (colour comes from SpaceTypes).
-- Colour is a brighter, more saturated take on each type's SpaceTypes hue (same hue family,
-- so the MAP legend still matches); shape and glyph keep types readable without colour.
local LOOK = {
	Neutral = { Shape = "Dot", Glyph = "", Color = Color3.fromRGB(255, 214, 120) },
	Gain = { Shape = "Circle", Glyph = "+3", Color = Color3.fromRGB(30, 146, 255) },
	Lose = { Shape = "Diamond", Glyph = "−3", Color = Color3.fromRGB(255, 56, 80) },
	Event = { Shape = "Circle", Glyph = "?", Color = Color3.fromRGB(34, 206, 96) },
	Shop = { Shape = "Square", Glyph = "SHOP", Color = Color3.fromRGB(190, 70, 255) },
	Item = { Shape = "Square", Glyph = "ITEM", Color = Color3.fromRGB(0, 206, 226) },
	Duel = { Shape = "Ring", Glyph = "VS", Color = Color3.fromRGB(255, 136, 20) },
	Chaos = { Shape = "Diamond", Glyph = "!", Color = Color3.fromRGB(126, 46, 210) },
	Switch = { Shape = "Ring", Glyph = "⇄", Color = Color3.fromRGB(255, 186, 30) },
	Reward = { Shape = "Ring", Glyph = "GIFT", Color = Color3.fromRGB(255, 196, 20) },
}
LOOK.Gift = LOOK.Reward
MedallionKit.Look = LOOK

local function part(props)
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

-- A flat disc lying on the ground (cylinders stand on their X axis).
local function disc(parent, name, diameter, height, centre: Vector3, color, material)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

local function decor(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Path materials per zone: one construction language, different stone/wood per area.
local ZONE_PATH = {
	Orchard = { Color = Color3.fromRGB(232, 206, 158), Material = Enum.Material.Cobblestone },
	Village = { Color = Color3.fromRGB(214, 170, 112), Material = Enum.Material.WoodPlanks },
	Fair = { Color = Color3.fromRGB(232, 196, 178), Material = Enum.Material.Pavement },
	Stream = { Color = Color3.fromRGB(226, 214, 184), Material = Enum.Material.Slate },
}
MedallionKit.ZonePath = ZONE_PATH

--[[
	Refined medallion (refined areas): warm sandstone base that belongs to the path, a layered
	rim (dark gold band + cream bevel), an inset field in the type colour, a lighter secondary
	symbol in the type's shape (colour-blind cue), and the glyph on top. Same footprint, same
	walkable top and collision as the plain one.
]]
local SAND = Color3.fromRGB(226, 196, 150)
local BEVEL = Color3.fromRGB(246, 230, 196)
local GOLD_BAND = Color3.fromRGB(196, 146, 56)

local function refinedSpace(model, position: Vector3, look, colour: Color3)
	local d = MedallionKit.DIAMETER
	decor(disc(model, "RimBand", d + 0.9, 0.75, position + Vector3.new(0, 0.38, 0), GOLD_BAND, Enum.Material.Metal))
	decor(disc(model, "RimFoot", d + 1.5, 0.35, position + Vector3.new(0, 0.12, 0), Color3.fromRGB(176, 138, 96), Enum.Material.Cobblestone))
	decor(disc(model, "Bevel", d - 0.2, 0.16, position + Vector3.new(0, 1.04, 0), BEVEL, Enum.Material.Marble))
	decor(disc(model, "Recess", 8.2, 0.08, position + Vector3.new(0, 1.12, 0), colour:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.SmoothPlastic))
	decor(disc(model, "Field", 7.5, 0.1, position + Vector3.new(0, 1.15, 0), colour, Enum.Material.SmoothPlastic))
	local symbol = colour:Lerp(Color3.new(1, 1, 1), 0.38)
	local y = position + Vector3.new(0, 1.21, 0)
	if look.Shape == "Diamond" then
		decor(part({ Name = "Symbol", Size = Vector3.new(4.4, 0.05, 4.4), CFrame = CFrame.new(y) * CFrame.Angles(0, math.rad(45), 0), Color = symbol, Parent = model }))
	elseif look.Shape == "Square" then
		decor(part({ Name = "Symbol", Size = Vector3.new(4.8, 0.05, 4.8), CFrame = CFrame.new(y), Color = symbol, Parent = model }))
	elseif look.Shape == "Ring" then
		decor(disc(model, "Symbol", 6.2, 0.05, y, symbol))
		decor(disc(model, "SymbolHole", 4.6, 0.06, y + Vector3.new(0, 0.03, 0), colour)) -- 0.035 above the ring
	elseif look.Shape == "Circle" then
		decor(disc(model, "Symbol", 5, 0.05, y, symbol))
	else -- Dot (neutral)
		decor(disc(model, "Symbol", 2.6, 0.05, y, BEVEL))
	end
end

function MedallionKit.space(parent: Instance, position: Vector3, typeKey: string, spaceType, id: number, refined: boolean?, meshEligible: boolean?)
	local look = LOOK[typeKey] or LOOK.Neutral
	local model = Instance.new("Model")
	model.Name = "Space" .. id
	local d = MedallionKit.DIAMETER
	-- Base (walkable; the only collidable piece) + gold rim
	local base = disc(model, "Base", d, 1.0, position + Vector3.new(0, 0.5, 0), if refined then SAND else CERAMIC, if refined then Enum.Material.Sandstone else Enum.Material.SmoothPlastic)
	base:SetAttribute("SpaceId", id)
	base:SetAttribute("SpaceType", typeKey)
	local colour = look.Color or spaceType.Color
	local inlayY = position + Vector3.new(0, 1.05, 0)
	local meshed = meshEligible and Meshes.enabled(id) and Meshes.build(model, position, typeKey, look.Shape, colour)
	if meshed then
		base.Transparency = 1
	elseif refined then
		refinedSpace(model, position, look, colour)
	else
	decor(disc(model, "Rim", d + 0.8, 0.7, position + Vector3.new(0, 0.35, 0), RIM, Enum.Material.SmoothPlastic))

	-- Inlay shape in the type colour, just proud of the base top
	if look.Shape == "Circle" then
		decor(disc(model, "Inlay", 7.4, 0.2, inlayY, colour))
	elseif look.Shape == "Dot" then
		decor(disc(model, "Inlay", 3.2, 0.2, inlayY, colour))
	elseif look.Shape == "Ring" then
		decor(disc(model, "Inlay", 7.6, 0.2, inlayY, colour))
		decor(disc(model, "InlayHole", 4.6, 0.24, inlayY, CERAMIC, Enum.Material.SmoothPlastic))
	elseif look.Shape == "Diamond" then
		decor(part({
			Name = "Inlay",
			Size = Vector3.new(5.6, 0.2, 5.6),
			CFrame = CFrame.new(inlayY) * CFrame.Angles(0, math.rad(45), 0),
			Color = colour,
			Parent = model,
		}))
	else -- Square (rounded look comes from the Blender insert later)
		decor(part({
			Name = "Inlay",
			Size = Vector3.new(6, 0.2, 6),
			CFrame = CFrame.new(inlayY),
			Color = colour,
			Parent = model,
		}))
	end
	end

	-- Icon / glyph, readable from the turn camera and the MAP
	if look.Glyph ~= "" and (not meshed or typeKey == "Gain" or typeKey == "Lose") then
		local plate = decor(part({
			Name = "Icon",
			Size = if meshed then Vector3.new(2, 0.05, 4) else Vector3.new(6, 0.05, 6),
			-- Turned so the glyph reads upright from the board camera (which looks north).
			CFrame = CFrame.new(position + (if meshed then Vector3.new(0, 1.42, 2.65) else Vector3.new(0, if refined then 1.25 else 1.2, 0))) * CFrame.Angles(0, math.rad(-90), 0),
			Transparency = 1,
			Parent = model,
		}))
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.fromRGB(40, 30, 70)
		label.Text = look.Glyph
		label.Parent = gui
		local pad = Instance.new("UIPadding")
		local inset = UDim.new(0.18, 0)
		pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = inset, inset, inset, inset
		pad.Parent = label
	end

	model.PrimaryPart = base
	model.Parent = parent
	return base
end

-- Path segment from one medallion's edge to the next, sloping with the height change.
-- Steps in a stair run that climbs `rise` studs (~0.8 studs each, never fewer than 3).
function MedallionKit.stairCount(rise: number): number
	return math.max(3, math.ceil(math.abs(rise) / 0.8))
end

function MedallionKit.path(parent: Instance, fromTop: Vector3, toTop: Vector3, name: string, area: string?)
	local flat = Vector3.new(toTop.X - fromTop.X, 0, toTop.Z - fromTop.Z)
	local direction = flat.Unit
	local radius = MedallionKit.DIAMETER / 2 - 0.4
	local a = fromTop + direction * radius - Vector3.new(0, 0.35, 0)
	local b = toTop - direction * radius - Vector3.new(0, 0.35, 0)
	local length = (b - a).Magnitude
	if flat.Magnitude < MedallionKit.DIAMETER or length < 0.5 then
		return nil
	end
	local slope = part({
		Name = name,
		Size = Vector3.new(MedallionKit.PATH_WIDTH, 0.5, length),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = if area and ZONE_PATH[area] then ZONE_PATH[area].Color else PATH,
		Material = if area and ZONE_PATH[area] then ZONE_PATH[area].Material else Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	-- A warm edging strip under the path so it separates cleanly from the grass
	if math.abs(b.Y - a.Y) < 1.5 and not area then
		local edge = part({
			Name = name .. "_Edge",
			Size = Vector3.new(MedallionKit.PATH_WIDTH + 1.2, 0.4, length),
			CFrame = CFrame.lookAt((a + b) / 2 - Vector3.new(0, 0.12, 0), b - Vector3.new(0, 0.12, 0)),
			Color = PATH_EDGE,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		edge.CanCollide = false
		edge.CanQuery = false
		edge.CanTouch = false
		edge.CastShadow = false
	end
	-- Elevation transitions read as stairs: the slope stays (named, so gates find it) but is
	-- hidden under a run of chunky steps. Steps are ~0.8 studs high, never fewer than 3.
	local rise = b.Y - a.Y
	if math.abs(rise) >= 1.5 then
		slope.Transparency = 1
		slope.CanCollide = false
		local run = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local count = MedallionKit.stairCount(rise)
		local depth = run.Magnitude / count
		local low = math.min(a.Y, b.Y) - 0.5
		for i = 1, count do
			local t = (i - 0.5) / count
			local topY = a.Y + rise * (if rise > 0 then i / count else (i - 1) / count) + 0.2 -- end step tucks under the medallion bevel (layer 1.05 < 1.12)
			-- never on a medallion layer plane of either end space (would z-fight)
			for _, endTop in { fromTop, toTop } do
				for _, plane in MedallionKit.LayerPlanes do
					local y = endTop.Y - MedallionKit.TOP + plane
					if math.abs(topY - y) < 0.03 then
						topY = y - 0.05
					end
				end
			end
			local height = math.max(0.4, topY - low)
			local centre = a + run * t
			local step = part({
				Name = name .. "_Step" .. i,
				Size = Vector3.new(MedallionKit.PATH_WIDTH, height, depth + 0.05),
				CFrame = CFrame.lookAt(Vector3.new(centre.X, low + height / 2, centre.Z), Vector3.new(b.X, low + height / 2, b.Z)),
				Color = if area then (if i % 2 == 0 then Color3.fromRGB(214, 186, 140) else Color3.fromRGB(230, 206, 164)) elseif i % 2 == 0 then STEP_COLOUR else PATH,
				Material = if area then Enum.Material.Cobblestone else Enum.Material.SmoothPlastic,
				Parent = parent,
			})
			step.CanQuery = false
			step.CanTouch = false
		end
	end
	return slope
end

-- Active-space marker: a soft gold ring hovering just above a medallion, separate from the
-- medallion's own material (moved by BoardWorld:setActiveSpace).
function MedallionKit.highlight(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "ActiveSpace"
	local ring = decor(disc(model, "Ring", MedallionKit.DIAMETER + 1.6, 0.25, Vector3.zero, Color3.fromRGB(255, 214, 120), Enum.Material.Neon))
	ring.Transparency = 0.6
	local hole = decor(disc(model, "Hole", MedallionKit.DIAMETER + 0.4, 0.3, Vector3.zero, Color3.new(1, 1, 1)))
	hole.Transparency = 1
	model.PrimaryPart = ring
	model.Parent = parent
	return model
end

return MedallionKit
