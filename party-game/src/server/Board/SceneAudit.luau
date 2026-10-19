--[[
	SceneAudit
	Finds geometry that z-fights or is duplicated in a built board (used by the unit tests and
	handy from the Studio command bar).

	  SceneAudit.run(folder) -> report
	    report.Coplanar   { { A, B, Y } }  two visible upward faces at the same height (within
	                                       PLANE_EPS) whose footprints overlap, with different
	                                       colour or material (these flicker)
	    report.Duplicates { { A, B } }     same class, shape, size and CFrame (exact copies)
	    report.Checked    number of horizontal faces examined

	Only flat, upward-facing tops are compared (block tops, upright cylinder ends): those are
	where every flicker on the boards has come from. Invisible parts (Transparency 1) are ignored.
]]

local SceneAudit = {}

SceneAudit.PLANE_EPS = 0.015 -- faces closer than this flicker at board-camera distance
local SAMPLES = 5

local function visible(p: BasePart): boolean
	return p.Transparency < 0.99 and p.LocalTransparencyModifier < 0.99
end

-- The part's upward face as { Y, Kind, CFrame, HalfX, HalfZ | Radius }, or nil.
local function topFace(p: BasePart)
	if not p:IsA("Part") then
		return nil
	end
	local cf = p.CFrame
	if p.Shape == Enum.PartType.Block then
		local up = cf.UpVector
		if math.abs(up.Y) > 0.999 then
			return { Y = cf.Position.Y + math.sign(up.Y) * p.Size.Y / 2, Kind = "Rect", CFrame = cf, HalfX = p.Size.X / 2, HalfZ = p.Size.Z / 2 }
		end
	elseif p.Shape == Enum.PartType.Cylinder then
		local axis = cf.RightVector
		if math.abs(axis.Y) > 0.999 then
			return { Y = cf.Position.Y + p.Size.X / 2, Kind = "Circle", Centre = cf.Position, Radius = math.min(p.Size.Y, p.Size.Z) / 2 }
		end
	end
	return nil
end

local function inside(face, point: Vector3): boolean
	if face.Kind == "Circle" then
		local d = Vector2.new(point.X - face.Centre.X, point.Z - face.Centre.Z)
		return d.Magnitude < face.Radius - 0.05
	end
	local l = face.CFrame:PointToObjectSpace(point)
	return math.abs(l.X) < face.HalfX - 0.05 and math.abs(l.Z) < face.HalfZ - 0.05
end

-- Points spread over a face (to test overlap without exact polygon clipping).
local function samples(face): { Vector3 }
	local points = {}
	for i = 0, SAMPLES - 1 do
		for j = 0, SAMPLES - 1 do
			local u, v = (i + 0.5) / SAMPLES * 2 - 1, (j + 0.5) / SAMPLES * 2 - 1
			if face.Kind == "Circle" then
				if u * u + v * v <= 1 then
					table.insert(points, face.Centre + Vector3.new(u * face.Radius * 0.95, 0, v * face.Radius * 0.95))
				end
			else
				table.insert(points, face.CFrame:PointToWorldSpace(Vector3.new(u * face.HalfX * 0.95, 0, v * face.HalfZ * 0.95)))
			end
		end
	end
	return points
end

-- A point on a face counts only if nothing visible sits right on top of it (a face buried
-- under another surface can't flicker on screen). `faces` = every horizontal face.
local function exposed(point: Vector3, y: number, faces, self1, self2): boolean
	for _, f in faces do
		if f.Part ~= self1 and f.Part ~= self2 and f.Y > y + SceneAudit.PLANE_EPS and f.Y < y + 3 and inside(f, point) then
			return false
		end
	end
	return true
end

local function overlaps(a, b, cover): boolean
	for _, list in { { samples(a), b }, { samples(b), a } } do
		for _, p in list[1] do
			if inside(list[2], p) and exposed(p, a.Y, cover(p), a.Part, b.Part) then
				return true
			end
		end
	end
	return false
end

function SceneAudit.run(folder: Instance)
	local report = { Coplanar = {}, Duplicates = {}, Checked = 0 }
	local buckets = {}
	local signatures = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and visible(d) then
			local sig = table.concat({ d.ClassName, tostring((d :: any).Shape), tostring(d.Size), tostring(d.CFrame) }, "|")
			if signatures[sig] then
				table.insert(report.Duplicates, { signatures[sig], d })
			else
				signatures[sig] = d
			end
			local face = topFace(d)
			if face then
				face.Part = d
				report.Checked += 1
				face.Index = report.Checked
				local key = math.floor(face.Y / SceneAudit.PLANE_EPS + 0.5)
				buckets[key] = buckets[key] or {}
				table.insert(buckets[key], face)
			end
		end
	end
	-- faces above a point: a coarse XZ grid of every horizontal face, for the cover check
	local CELL = 16
	local grid = {}
	for _, list in buckets do
		for _, f in list do
			local lo, hi
			if f.Kind == "Circle" then
				lo, hi = f.Centre - Vector3.new(f.Radius, 0, f.Radius), f.Centre + Vector3.new(f.Radius, 0, f.Radius)
			else
				local r = math.sqrt(f.HalfX ^ 2 + f.HalfZ ^ 2)
				lo, hi = f.CFrame.Position - Vector3.new(r, 0, r), f.CFrame.Position + Vector3.new(r, 0, r)
			end
			for gx = math.floor(lo.X / CELL), math.floor(hi.X / CELL) do
				for gz = math.floor(lo.Z / CELL), math.floor(hi.Z / CELL) do
					local k = gx * 100000 + gz
					grid[k] = grid[k] or {}
					table.insert(grid[k], f)
				end
			end
		end
	end
	local function cover(p: Vector3)
		return grid[math.floor(p.X / CELL) * 100000 + math.floor(p.Z / CELL)] or {}
	end
	local seen = {}
	for key, list in buckets do
		local near = {}
		for k = key - 1, key + 1 do
			for _, f in buckets[k] or {} do
				table.insert(near, f)
			end
		end
		for _, a in list do
			for _, b in near do
				if a.Part ~= b.Part and math.abs(a.Y - b.Y) < SceneAudit.PLANE_EPS then
					local pa, pb = a.Part, b.Part
					local ia, ib = a.Index, b.Index
					local id = if ia < ib then ia * 100000 + ib else ib * 100000 + ia
					if not seen[id] then
						seen[id] = true
						local differs = pa.Color ~= pb.Color or pa.Material ~= pb.Material
						if differs and overlaps(a, b, cover) then
							table.insert(report.Coplanar, { A = pa, B = pb, Y = a.Y })
						end
					end
				end
			end
		end
	end
	return report
end

--[[
	Parts that intrude into a board space's playable disc (radius `radius` around each space's
	Base, from its top up to 4 studs): scenery like bridge rails must stop at the space edge.
	Parts inside the space's own model, paths (Path*), and the ActiveSpace ring are allowed.
]]
function SceneAudit.intrusions(folder: Instance, radius: number?)
	local r = radius or 4.2
	local bases = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Base" and d:GetAttribute("SpaceId") then
			table.insert(bases, d)
		end
	end
	local found = {}
	for _, d in folder:GetDescendants() do
		if not d:IsA("BasePart") or not visible(d) or string.sub(d.Name, 1, 4) == "Path" then
			continue
		end
		local model = d:FindFirstAncestorWhichIsA("Model")
		if model and (model.Name == "ActiveSpace" or string.match(model.Name, "^Space%d+$")) then
			continue
		end
		local cf, size = d.CFrame, d.Size
		for _, base in bases do
			local top = base.Position.Y + base.Size.X / 2
			-- closest point of the part's box to the space centre line, at disc height
			local centre = Vector3.new(base.Position.X, math.clamp(cf.Position.Y, top, top + 4), base.Position.Z)
			local l = cf:PointToObjectSpace(centre)
			local clamped = Vector3.new(math.clamp(l.X, -size.X / 2, size.X / 2), math.clamp(l.Y, -size.Y / 2, size.Y / 2), math.clamp(l.Z, -size.Z / 2, size.Z / 2))
			local p = cf:PointToWorldSpace(clamped)
			local flat = Vector2.new(p.X - base.Position.X, p.Z - base.Position.Z).Magnitude
			if flat < r and p.Y > top + 0.05 and p.Y < top + 4 then
				table.insert(found, { Part = d, SpaceId = base:GetAttribute("SpaceId") })
				break
			end
		end
	end
	return found
end

-- "Name/Name (count)" summary of the worst offenders, for logs.
function SceneAudit.summary(report, limit: number?): string
	local counts = {}
	for _, c in report.Coplanar do
		local key = c.A.Name .. "/" .. c.B.Name
		counts[key] = (counts[key] or 0) + 1
	end
	local list = {}
	for k, n in counts do
		table.insert(list, { k, n })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local out = {}
	for i = 1, math.min(limit or 25, #list) do
		table.insert(out, ("%s x%d"):format(list[i][1], list[i][2]))
	end
	return ("%d coplanar, %d duplicates, %d faces checked\n%s"):format(#report.Coplanar, #report.Duplicates, report.Checked, table.concat(out, "\n"))
end

return SceneAudit
