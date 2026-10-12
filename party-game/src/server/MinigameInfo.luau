--[[
	MinigameInfo
	Validates a minigame module and fills in defaults for its Info table, so the rest of
	the framework (and the client) can rely on a complete, predictable shape:

	  Info = {
	    Name, Description          strings
	    Duration                   seconds
	    Layout                     "FFA" | "1v3" | "2v2"
	    Camera = {                 optional, defaults to AngledOverhead
	      Mode = "AngledOverhead" | "FollowBehind" | "SideView",
	      ...any Config.CameraModes[Mode] number to override (Height, Distance, ...)
	    },
	    Controls = {               optional, defaults to free movement + no actions
	      Move = true,             false = can't walk (server sets WalkSpeed 0)
	      Jump = true,             false = can't jump
	      WalkSpeed = 16,
	      Actions = { { Action = "Pass", Label = "Pass!", Key = "E" } },
	    },
	    ProgressLabel = "Score",   optional default label for the player chips
	  }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local MinigameInfo = {}

local REQUIRED_FUNCTIONS = { "Setup", "Start", "Cleanup", "GetResults" }

-- Returns an error string, or nil if the module is usable.
function MinigameInfo.validate(definition): string?
	if type(definition) ~= "table" then
		return "module must return a table"
	end
	local info = definition.Info
	if type(info) ~= "table" then
		return "missing Info table"
	end
	if type(info.Name) ~= "string" or type(info.Description) ~= "string" then
		return "Info.Name and Info.Description must be strings"
	end
	if type(info.Duration) ~= "number" or info.Duration <= 0 then
		return "Info.Duration must be a positive number"
	end
	if not table.find({ "FFA", "1v3", "2v2" }, info.Layout) then
		return "Info.Layout must be FFA, 1v3 or 2v2"
	end
	local camera = info.Camera
	if camera ~= nil and (type(camera) ~= "table" or not Config.CameraModes[camera.Mode]) then
		return "Info.Camera.Mode must be AngledOverhead, FollowBehind or SideView"
	end
	local controls = info.Controls
	if controls ~= nil then
		if type(controls) ~= "table" then
			return "Info.Controls must be a table"
		end
		for _, action in controls.Actions or {} do
			if type(action.Action) ~= "string" or type(action.Label) ~= "string" then
				return "each Info.Controls.Actions entry needs Action and Label strings"
			end
		end
	end
	for _, name in REQUIRED_FUNCTIONS do
		if type(definition[name]) ~= "function" then
			return ("missing function %s"):format(name)
		end
	end
	return nil
end

-- Info with every optional field filled in. Safe to send to clients.
function MinigameInfo.normalize(id: string, info)
	local cameraIn = info.Camera or {}
	local mode = cameraIn.Mode or Config.DefaultCameraMode
	local camera = table.clone(Config.CameraModes[mode])
	for key, value in cameraIn do
		camera[key] = value
	end
	camera.Mode = mode

	local controlsIn = info.Controls or {}
	local actions = {}
	for _, action in controlsIn.Actions or {} do
		table.insert(actions, {
			Action = action.Action,
			Label = action.Label,
			Key = action.Key, -- Enum.KeyCode name, e.g. "E"
			Gamepad = action.Gamepad, -- optional Enum.KeyCode name, e.g. "ButtonX"
		})
	end
	local controls = {
		Move = controlsIn.Move ~= false,
		Jump = controlsIn.Jump ~= false,
		WalkSpeed = controlsIn.WalkSpeed or Config.DefaultWalkSpeed,
		Actions = actions,
	}

	return {
		Id = id,
		Name = info.Name,
		Description = info.Description,
		Layout = info.Layout,
		Duration = info.Duration,
		Camera = camera,
		Controls = controls,
		ProgressLabel = info.ProgressLabel,
	}
end

return MinigameInfo
