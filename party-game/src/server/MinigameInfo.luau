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
	      TouchZoom = 1           optional: replaces Config.TouchCamera's Zoom on phones/tablets
	      TouchLookAhead = 6      optional: replaces Config.TouchCamera's LookAhead on phones/tablets
	    },
	    Controls = {               optional, defaults to free movement + no actions
	      Move = true,             false = can't walk (server sets WalkSpeed 0)
	      Jump = true,             false = can't jump
	      WalkSpeed = 16,
	      Actions = { { Action = "Pass", Label = "Pass!", Key = "E" } },
	        per action, optional:  Keys = { "A", "Left" }  several keys instead of one Key
	                               Gamepads = { "DPadLeft", "ButtonL1" }  several pad buttons
	                               Hold = true             OnInput gets "<Action>" on press and
	                                                       "<Action>Stop" on release
	                               Side = "Left"           on-screen button goes bottom-left
	    },
	    ProgressLabel = "Score",   optional default label for the player chips
	    ClientModule = "IceDash",  optional: name of a module in client/Minigames that Main starts
	                               for the round (its messages arrive in OnClientMessage)
	    ProgressBar = true,        optional: show a race bar along the top instead of the chips;
	                               report values like "37%" (anything with 🏁 counts as 100%)
	    Tutorial = {               optional: the pre-minigame tutorial screen (see below)
	      Objective = "Pass the potato before it explodes.",   short primary objective
	      Rule = "Holding it when it pops knocks you out.",    optional, one short rule
	      Win = "Last player standing wins.",                  optional win condition
	      Controls = { { Label = "STEER", Actions = { "Left", "Right" } } },
	                               optional action lines (default: one per action); the
	                               MOVE / JUMP / NO WALKING lines always come from Controls
	      Preview = { ... },       optional looping demo, declarative only (validatePreview)
	    },
	  }

	Tutorial.Preview is data, never code; TutorialPreview (client) plays it in a ViewportFrame:
	  Loop = 5                     seconds, 3..8; everything resets each loop
	  Camera = { Position = Vector3, LookAt = Vector3 }
	  Actors = { { Start = Vector3, Team = 1? } }       1..4 avatars (the round's participants)
	  Props = { { Id = "Potato", Shape = "Ball", Size = Vector3, Position = Vector3,
	              Color = Color3, Transparency = 0?, Neon = false? } }          up to 40
	  Steps = { { At = 1.2, <subject>, <change> } }                           up to 80
	    subject: Actor = index | Prop = id | (none: a caption over the whole preview)
	    change:  To = Vector3 (+ Time) move · Jump = true · Visible = bool · Attach = actor index
	             or 0 (prop rides on an actor's head / lets go) · Color = Color3 · Pulse = true
	             · Caption = "PASS!" (short text over the actor, or the preview)
	Missing or invalid previews fall back to a generic one; the round never fails over it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local MinigameInfo = {}

local REQUIRED_FUNCTIONS = { "Setup", "Start", "Cleanup", "GetResults" }
local SHAPES = { Block = true, Ball = true, Cylinder = true }
local STEP_KEYS = { At = true, Actor = true, Prop = true, To = true, Time = true, Jump = true, Visible = true, Attach = true, Color = true, Pulse = true, Caption = true }

local function shortText(value, max: number): boolean
	return type(value) == "string" and #value > 0 and #value <= max
end

-- Returns an error string, or nil if `preview` is a valid declarative preview.
function MinigameInfo.validatePreview(preview): string?
	if type(preview) ~= "table" then
		return "Preview must be a table"
	end
	if type(preview.Loop) ~= "number" or preview.Loop < 3 or preview.Loop > 8 then
		return "Preview.Loop must be 3..8 seconds"
	end
	local camera = preview.Camera
	if type(camera) ~= "table" or typeof(camera.Position) ~= "Vector3" or typeof(camera.LookAt) ~= "Vector3" then
		return "Preview.Camera needs Position and LookAt Vector3s"
	end
	local actors = preview.Actors
	if type(actors) ~= "table" or #actors < 1 or #actors > 4 then
		return "Preview.Actors must list 1..4 actors"
	end
	for _, actor in actors do
		if type(actor) ~= "table" or typeof(actor.Start) ~= "Vector3" or (actor.Team ~= nil and actor.Team ~= 1 and actor.Team ~= 2) then
			return "each actor needs a Start Vector3 (and Team 1/2 or nil)"
		end
	end
	local props = preview.Props or {}
	if type(props) ~= "table" or #props > 40 then
		return "Preview.Props must be a list of at most 40"
	end
	local ids = {}
	for _, prop in props do
		if type(prop) ~= "table" or not shortText(prop.Id, 24) or not SHAPES[prop.Shape]
			or typeof(prop.Size) ~= "Vector3" or typeof(prop.Position) ~= "Vector3" or typeof(prop.Color) ~= "Color3" then
			return "each prop needs Id, Shape (Block/Ball/Cylinder), Size, Position and Color"
		end
		ids[prop.Id] = true
	end
	local steps = preview.Steps or {}
	if type(steps) ~= "table" or #steps > 80 then
		return "Preview.Steps must be a list of at most 80"
	end
	for index, step in steps do
		if type(step) ~= "table" or type(step.At) ~= "number" or step.At < 0 or step.At > preview.Loop then
			return ("step %d: At must be within the loop"):format(index)
		end
		for key in step do
			if not STEP_KEYS[key] then
				return ("step %d: unknown key %s"):format(index, tostring(key))
			end
		end
		if step.Actor ~= nil and (type(step.Actor) ~= "number" or not actors[step.Actor]) then
			return ("step %d: no actor %s"):format(index, tostring(step.Actor))
		end
		if step.Prop ~= nil and not ids[step.Prop] then
			return ("step %d: no prop %s"):format(index, tostring(step.Prop))
		end
		if step.To ~= nil and typeof(step.To) ~= "Vector3" or step.Time ~= nil and type(step.Time) ~= "number"
			or step.Color ~= nil and typeof(step.Color) ~= "Color3" or step.Caption ~= nil and not shortText(step.Caption, 20)
			or step.Attach ~= nil and (type(step.Attach) ~= "number" or (step.Attach ~= 0 and not actors[step.Attach])) then
			return ("step %d: bad value"):format(index)
		end
	end
	return nil
end

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
	if not table.find({ "FFA", "1v3", "2v2", "Duel" }, info.Layout) then
		return "Info.Layout must be FFA, 1v3, 2v2 or Duel"
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
	local tutorial = info.Tutorial
	if tutorial ~= nil then
		if type(tutorial) ~= "table" or not shortText(tutorial.Objective, 90) then
			return "Info.Tutorial needs a short Objective (90 characters max)"
		end
		for _, key in { "Rule", "Win" } do
			if tutorial[key] ~= nil and not shortText(tutorial[key], 90) then
				return ("Info.Tutorial.%s must be a short string"):format(key)
			end
		end
		for _, line in tutorial.Controls or {} do
			if type(line) ~= "table" or not shortText(line.Label, 20) then
				return "each Info.Tutorial.Controls line needs a short Label"
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
			Key = action.Key or (action.Keys and action.Keys[1]), -- Enum.KeyCode name, e.g. "E"
			Keys = action.Keys, -- optional list of Enum.KeyCode names (overrides Key for binding)
			Gamepad = action.Gamepad, -- optional Enum.KeyCode name, e.g. "ButtonX"
			Gamepads = action.Gamepads, -- optional list of Enum.KeyCode names (overrides Gamepad)
			Hold = action.Hold == true, -- also sends "<Action>Stop" when released
			Side = action.Side, -- "Left" puts the on-screen button in the bottom-left corner
			Color = if typeof(action.Color) == "Color3" then action.Color else nil, -- on-screen button colour
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
		Tutorial = MinigameInfo.tutorial(id, info, controls),
		Description = info.Description,
		Layout = info.Layout,
		Duration = info.Duration,
		Camera = camera,
		Controls = controls,
		ProgressLabel = info.ProgressLabel,
		ProgressBar = info.ProgressBar == true,
		ClientModule = if type(info.ClientModule) == "string" then info.ClientModule else nil,
	}
end

-- An action's short label: "Pass!" -> "PASS".
local function word(label: string): string
	local text = string.upper(string.gsub(label, "[!%.]", ""))
	return if text == "" then "GO" else text
end

-- The tutorial screen's data: objective lines, control lines (each naming the actions it
-- shows) and the preview (nil = the client's generic preview). Never fails.
function MinigameInfo.tutorial(id: string, info, controls)
	local tutorial = info.Tutorial or {}
	-- Movement first, always from the real controls (overrides can't misstate it), then the
	-- action lines: Tutorial.Controls if given, else one per action.
	local lines = {}
	if not controls.Move then
		table.insert(lines, { Label = "NO WALKING", Actions = {}, NoMove = true })
	elseif controls.Jump then
		table.insert(lines, { Label = "MOVE", Actions = {}, Move = true })
		table.insert(lines, { Label = "JUMP", Actions = {}, Jump = true })
	else
		table.insert(lines, { Label = "MOVE", Note = "No jumping", Actions = {}, Move = true })
	end
	if type(tutorial.Controls) == "table" then
		for _, line in tutorial.Controls do
			table.insert(lines, { Label = line.Label, Actions = line.Actions or {} })
		end
	else
		for _, action in controls.Actions do
			table.insert(lines, { Label = word(action.Label), Actions = { action.Action } })
		end
	end
	local preview = tutorial.Preview
	if preview ~= nil then
		local problem = MinigameInfo.validatePreview(preview)
		if problem then
			warn(("[MinigameInfo] %s: tutorial preview ignored (%s)"):format(id, problem))
			preview = nil
		end
	end
	return {
		Objective = tutorial.Objective or info.Description,
		Rule = tutorial.Rule,
		Win = tutorial.Win,
		Controls = lines,
		Preview = preview,
	}
end

return MinigameInfo
