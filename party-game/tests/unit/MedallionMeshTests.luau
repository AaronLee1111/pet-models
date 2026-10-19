local board = game.ServerScriptService.PartyServer.Board
local Kit = require(board.MedallionKit)
local Meshes = require(board.MedallionMeshes)
local Types = require(board.SpaceTypes)
return function()
	local passed, failed = 0, 0
	local function test(name, fn)
		local ok, err = pcall(fn)
		if ok then passed += 1 else failed += 1; warn("[MedallionMeshTests] " .. name .. ": " .. tostring(err)) end
	end
	test("slice keeps untouched comparison spaces", function()
		local mode = Meshes.Mode; Meshes.Mode = "Slice"
		assert(Meshes.enabled(5) and Meshes.enabled(6) and Meshes.enabled(7) and Meshes.enabled(8) and Meshes.enabled(30))
		assert(not Meshes.enabled(9)); Meshes.Mode = mode
	end)
	test("collider, native values, unique meshes and presentation reference", function()
		local folder = Instance.new("Folder")
		local p = Kit.space(folder, Vector3.new(12, 4, 20), "Gain", Types.Gain, 6, true, true)
		local success, err = pcall(function()
			assert(p.CanCollide and p.Size == Vector3.new(1, 10.5, 10.5))
			assert(p.Position == Vector3.new(12, 4.5, 20) and Kit.TOP == 1.2)
			assert(p:GetAttribute("SpaceType") == "Gain" and p:GetAttribute("SpaceId") == 6)
			local visual = p.Parent:FindFirstChild("MeshVisuals"); assert(visual, "mesh assets unavailable")
			assert(#visual:GetChildren() == 3)
			for _, m in visual:GetChildren() do assert(m:IsA("MeshPart") and not m.CanCollide and not m.CanQuery and not m.CanTouch) end
			assert(p.Parent.Icon.SurfaceGui.TextLabel.Text == "+3")
		end)
		folder:Destroy(); assert(success, err)
	end)
	test("missing symbol leaves no partial mesh assembly", function()
		local parent = Instance.new("Folder")
		assert(not Meshes.build(parent, Vector3.zero, "MissingType", "Circle", Color3.new(1, 0, 0)))
		assert(#parent:GetChildren() == 0); parent:Destroy()
	end)
	test("gift maps to reward and unrelated boards retain their visuals", function()
		assert(Kit.Look.Gift == Kit.Look.Reward)
		local f = Instance.new("Folder")
		local p = Kit.space(f, Vector3.zero, "Gain", Types.Gain, 6, true, false)
		assert(not p.Parent:FindFirstChild("MeshVisuals") and p.Transparency == 0); f:Destroy()
	end)
	test("scene audit detects duplicate imported meshes", function()
		local f = Instance.new("Folder")
		local p = board.MedallionAssets.SunnyLoop_Space_Base_v1:Clone();p.Parent = f;p:Clone().Parent = f
		local report = require(board.SceneAudit).run(f);f:Destroy();assert(#report.Duplicates == 1)
	end)
	print(("[MedallionMeshTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
