--[[
	SceneAmbience
	Small decorative motion for board scenes, run locally on each client (nothing replicates per
	frame). Board scene builders mark models with attributes:
	  AmbientSpin  degrees per second around the model's pivot (AmbientAxis "X" | "Y" | "Z")
	  AmbientBob   studs of gentle up-and-down drift
	Used by SkyGardenScene: waterwheel, crown on the Crown Pavilion, balloons, kites, floating
	islands. Only models inside workspace.PartyBoard are animated; nothing runs without a board.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SceneAmbience = {}

local entries = {} -- { Model, Base: CFrame, Spin, Axis, Bob, Phase }
local boardFolder = nil
local connection = nil

local function collect(folder: Instance)
	table.clear(entries)
	for _, d in folder:GetDescendants() do
		if d:IsA("Model") then
			local spin, bob = d:GetAttribute("AmbientSpin"), d:GetAttribute("AmbientBob")
			if spin or bob then
				table.insert(entries, {
					Model = d,
					Base = d:GetPivot(),
					Spin = spin,
					Axis = d:GetAttribute("AmbientAxis") or "Y",
					Bob = bob,
					Phase = (#entries * 1.7) % (math.pi * 2),
				})
			end
		end
	end
end

local function step()
	if not boardFolder or not boardFolder.Parent then
		boardFolder = nil
		table.clear(entries)
		return
	end
	local t = os.clock()
	for _, e in entries do
		local cf = e.Base
		if e.Bob then
			cf += Vector3.new(0, math.sin(t * 0.8 + e.Phase) * e.Bob, 0)
		end
		if e.Spin then
			local angle = math.rad(e.Spin * t)
			local turn = if e.Axis == "X" then CFrame.Angles(angle, 0, 0)
				elseif e.Axis == "Z" then CFrame.Angles(0, 0, angle)
				else CFrame.Angles(0, angle, 0)
			cf = cf * turn
		end
		e.Model:PivotTo(cf)
	end
end

function SceneAmbience.start()
	if connection then
		return
	end
	local function watch(child: Instance)
		if child.Name == "PartyBoard" then
			boardFolder = child
			task.defer(collect, child) -- after replication settles
			task.delay(3, function()
				if boardFolder == child then
					collect(child)
				end
			end)
		end
	end
	for _, child in Workspace:GetChildren() do
		watch(child)
	end
	Workspace.ChildAdded:Connect(watch)
	connection = RunService.RenderStepped:Connect(step)
end

return SceneAmbience
