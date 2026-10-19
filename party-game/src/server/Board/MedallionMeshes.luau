-- Blender-authored geometry; imported templates share the same mesh content IDs.
local Kit = {}
local templates = script.Parent:WaitForChild("MedallionAssets")
local content = game:GetService("ContentProvider")
local ready = {}
local slice = { [5] = true, [6] = true, [7] = true, [8] = true, [30] = true }
Kit.Mode = "Slice"
function Kit.enabled(id)
	return Kit.Mode == "All" or (Kit.Mode == "Slice" and slice[id] == true)
end
local function template(kind)
	local name = "SunnyLoop_Space_" .. kind .. "_v1"
	local mesh = templates:FindFirstChild(name)
	if not mesh or not mesh:IsA("MeshPart") then return nil end
	if ready[name] == nil then
		local loaded = true
		local ok = pcall(function()
			content:PreloadAsync({ mesh }, function(_, status)
				if status ~= Enum.AssetFetchStatus.Success then loaded = false end
			end)
		end)
		ready[name] = ok and loaded
	end
	return if ready[name] then mesh else nil
end
function Kit.build(parent, position, typeKey, shape, colour)
	local symbolKey = if typeKey == "Gift" then "Reward" else typeKey
	local base = template("Base")
	local insert = template("Inlay_" .. shape)
	local symbol = if symbolKey ~= "Neutral" then template("Symbol_" .. symbolKey) else nil
	if not base or not insert or (symbolKey ~= "Neutral" and not symbol) then return false end
	local folder = Instance.new("Folder")
	folder.Name = "MeshVisuals"
	for _, source in { base, insert, symbol } do
		local mesh = source:Clone()
		local offset = source.CFrame
		-- Ring symbols are recessed into the exposed bed instead of floating above its hole.
		if source == symbol and shape == "Ring" then offset -= Vector3.new(0, 0.34, 0) end
		mesh.CFrame = CFrame.new(position) * CFrame.Angles(0, math.pi, 0) * offset
		mesh.Color = if source == insert then colour else if source == symbol then Color3.fromRGB(247, 224, 173) else Color3.new(1, 1, 1)
		mesh.Anchored = true
		mesh.CanCollide, mesh.CanTouch, mesh.CanQuery = false, false, false
		mesh.CastShadow = false
		mesh.Parent = folder
	end
	folder.Parent = parent
	parent:SetAttribute("MedallionMeshVersion", 1)
	return true
end
return Kit
