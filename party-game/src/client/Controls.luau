--[[
	Controls
	Binds the active minigame's Info.Controls to keyboard, gamepad and an on-screen mobile
	button. Pressing one only *sends an input*; the server decides what happens.
]]

local ContextActionService = game:GetService("ContextActionService")

local Controls = {}

local GAMEPAD_BUTTONS = { Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonB }
local bound: { string } = {}

function Controls.bind(controls, send: (string) -> ())
	Controls.unbind()
	for index, control in controls do
		local bindName = "Party_" .. control.Action
		local inputs = {}
		local ok, keyCode = pcall(function()
			return (Enum.KeyCode :: any)[control.Key]
		end)
		if ok and keyCode then
			table.insert(inputs, keyCode)
		end
		if GAMEPAD_BUTTONS[index] then
			table.insert(inputs, GAMEPAD_BUTTONS[index])
		end

		ContextActionService:BindAction(bindName, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				send(control.Action)
			end
			return Enum.ContextActionResult.Sink
		end, true, table.unpack(inputs))
		ContextActionService:SetTitle(bindName, control.Label)
		table.insert(bound, bindName)
	end
end

function Controls.unbind()
	for _, bindName in bound do
		ContextActionService:UnbindAction(bindName)
	end
	table.clear(bound)
end

return Controls
