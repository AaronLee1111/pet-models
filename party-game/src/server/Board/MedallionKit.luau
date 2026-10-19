--[[
	MedallionKit
	Studio build of the board-space kit used by boards with Style = "Medallion" (Sunny Loop v2).
	Same dimensions as the Blender kit (docs/SunnyLoopV2.md, "Board-space kit"), so the Blender
	meshes can replace these parts one for one later:

	  base     round ceramic medallion, 10.5 studs across, 1.2 tall, gold rim (one mesh, all types)
	  inlay    the type's colour as a SHAPE: circle, diamond, rounded square or ring (colour-blind
	           safe: shape + icon + colour all differ by type)
	  icon     the type's symbol on top (text glyph until the rendered icon set exists)
	  path     sandy path segment between two medallion edges, following the height change

	  MedallionKit.TOP              height of the walkable top above the space's position
	  MedallionKit.space(parent, position, typeKey, spaceType, id) -> base Part
	  MedallionKit.path(parent, fromTop, toTop, name) -> Part?
]]

local MedallionKit = {}

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

function MedallionKit.space(parent: Instance, position: Vector3, typeKey: string, spaceType, id: number)
	local look = LOOK[typeKey] or LOOK.Neutral
	local model = Instance.new("Model")
	model.Name = "Space" .. id
	local d = MedallionKit.DIAMETER
	-- Base (walkable; the only collidable piece) + gold rim
	local base = disc(model, "Base", d, 1.0, position + Vector3.new(0, 0.5, 0), CERAMIC, Enum.Material.SmoothPlastic)
	base:SetAttribute("SpaceId", id)
	base:SetAttribute("SpaceType", typeKey)
	decor(disc(model, "Rim", d + 0.8, 0.7, position + Vector3.new(0, 0.35, 0), RIM, Enum.Material.SmoothPlastic))

	-- Inlay shape in the type colour, just proud of the base top
	local inlayY = position + Vector3.new(0, 1.05, 0)
	local colour = look.Color or spaceType.Color
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

	-- Icon / glyph, readable from the turn camera and the MAP
	if look.Glyph ~= "" then
		local plate = decor(part({
			Name = "Icon",
			Size = Vector3.new(6, 0.05, 6),
			-- Turned so the glyph reads upright from the board camera (which looks north).
			CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(-90), 0),
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
function MedallionKit.path(parent: Instance, fromTop: Vector3, toTop: Vector3, name: string)
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
		Color = PATH,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	-- A warm edging strip under the path so it separates cleanly from the grass
	if math.abs(b.Y - a.Y) < 1.5 then
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
		local count = math.max(3, math.ceil(math.abs(rise) / 0.8))
		local depth = run.Magnitude / count
		local low = math.min(a.Y, b.Y) - 0.5
		for i = 1, count do
			local t = (i - 0.5) / count
			local topY = a.Y + rise * (if rise > 0 then i / count else (i - 1) / count) + 0.25
			local height = math.max(0.4, topY - low)
			local centre = a + run * t
			local step = part({
				Name = name .. "_Step" .. i,
				Size = Vector3.new(MedallionKit.PATH_WIDTH, height, depth + 0.05),
				CFrame = CFrame.lookAt(Vector3.new(centre.X, low + height / 2, centre.Z), Vector3.new(b.X, low + height / 2, b.Z)),
				Color = if i % 2 == 0 then STEP_COLOUR else PATH,
				Material = Enum.Material.SmoothPlastic,
				Parent = parent,
			})
			step.CanQuery = false
			step.CanTouch = false
		end
	end
	return slope
end

return MedallionKit
