--[[
	Controls
	Applies a minigame's Info.Controls on this client:
	  * Actions -> keyboard key + gamepad button (ContextActionService) AND a big on-screen
	    button (ActionBar), so keyboard, controller and touch all work out of the box
	  * Move / Jump = false -> the default Roblox movement controls (thumbstick, WASD,
	    jump button) are switched off. The server enforces the same lock independently.

	Pressing anything only *sends an input*; the server decides what happens.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Controls = {}

local DEFAULT_GAMEPAD = { "ButtonX", "ButtonY", "ButtonB" }
local bound: { string } = {}
local actionBar = nil
local movementDisabled = false

-- Roblox's PlayerModule owns WASD / thumbstick / jump. It may not exist (e.g. custom setups).
local function getPlayerControls()
	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end
	local ok, playerModule = pcall(require, module)
	return ok and playerModule and playerModule:GetControls() or nil
end

local function keyCode(name: string?): EnumItem?
	if type(name) ~= "string" then
		return nil
	end
	local ok, item = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then item else nil
end

-- The on-screen buttons live in UI/ActionBar; Main hands it over once at startup.
function Controls.setActionBar(bar)
	actionBar = bar
end

function Controls.bind(controls, send: (string) -> ())
	Controls.unbind()

	for index, action in controls.Actions do
		local bindName = "Party_" .. action.Action
		local inputs = {}
		for _, name in action.Keys or { action.Key } do
			local key = keyCode(name)
			if key then
				table.insert(inputs, key)
			end
		end
		local pad = keyCode(action.Gamepad or DEFAULT_GAMEPAD[index])
		if pad then
			table.insert(inputs, pad)
		end
		ContextActionService:BindActionAtPriority(bindName, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				send(action.Action)
			elseif inputState == Enum.UserInputState.End and action.Hold then
				send(action.Action .. "Stop")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(inputs))
		table.insert(bound, bindName)
	end

	if actionBar then
		actionBar:show(controls.Actions, send, not controls.Move)
	end

	if not controls.Move or not controls.Jump then
		local playerControls = getPlayerControls()
		if playerControls and not controls.Move then
			playerControls:Disable()
			movementDisabled = true
		end
	end
end

function Controls.unbind()
	for _, bindName in bound do
		ContextActionService:UnbindAction(bindName)
	end
	table.clear(bound)
	if actionBar then
		actionBar:hide()
	end
	if movementDisabled then
		movementDisabled = false
		local playerControls = getPlayerControls()
		if playerControls then
			playerControls:Enable()
		end
	end
end

return Controls
