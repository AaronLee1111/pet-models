--[[
	InputHint
	Which kind of input this player is using, and how to name a control for it:
	  "Touch"    any touch screen (phones and Studio's phone emulator can report a keyboard
	             too, so touch wins: no keyboard text on a touch screen)
	  "Gamepad"  the last input came from a controller
	  "Mouse"    everything else (mouse + keyboard)
]]

local UserInputService = game:GetService("UserInputService")

local Icons = require(script.Parent.Icons)

local InputHint = {}

function InputHint.mode(): string
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	if UserInputService.TouchEnabled then
		return "Touch"
	end
	return "Mouse"
end

-- "TAP" / "CLICK" / "PRESS"
function InputHint.verb(mode: string): string
	return if mode == "Touch" then "TAP" elseif mode == "Gamepad" then "PRESS" else "CLICK"
end

local KEY_NAMES = {
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Left = "LEFT",
	Right = "RIGHT",
	Up = "UP",
	Down = "DOWN",
	Return = "ENTER",
	LeftShift = "SHIFT",
}

-- KeyCode name -> what's printed on it: "Space" -> "SPACE", "ButtonA" -> "A", "One" -> "1".
function InputHint.keyName(name: string?): string?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if KEY_NAMES[name] then
		return KEY_NAMES[name]
	end
	if string.sub(name, 1, 6) == "Button" then
		return string.upper(string.sub(name, 7))
	end
	if string.sub(name, 1, 4) == "DPad" then
		return "D-PAD " .. string.upper(string.sub(name, 5))
	end
	return string.upper(name)
end

-- Atlas prompt for a KeyCode name on this device ("Space" -> KeySpace, "ButtonA" -> XboxA /
-- PSCross / GamepadAction), or nil when the atlas has no prompt for it (callers keep the text).
function InputHint.prompt(name: string?): string?
	local ok, keyCode = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok and keyCode then Icons.button(keyCode) else nil
end

-- The gamepad button a minigame action is bound to (Controls uses the same defaults).
local DEFAULT_GAMEPAD = { "ButtonX", "ButtonY", "ButtonB" }
function InputHint.gamepadFor(action, index: number): string?
	if type(action.Gamepads) == "table" and action.Gamepads[1] then
		return action.Gamepads[1]
	end
	return action.Gamepad or DEFAULT_GAMEPAD[index]
end

function InputHint.keyFor(action): string?
	if type(action.Keys) == "table" and action.Keys[1] then
		return action.Keys[1]
	end
	return action.Key
end

-- An action's button label as one short word: "Mash!" -> "MASH".
function InputHint.actionWord(label: string?): string
	local word = string.upper(string.gsub(label or "", "[!%.]", ""))
	return if word == "" then "GO" else word
end

return InputHint
