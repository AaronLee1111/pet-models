--[[
	Icons (DRAFT, not built into the game; moves to src/client/UI/Icons.luau on approval)
	One place that maps semantic icon names to images, so UI code never repeats asset ids.

	  Icons.image(name, state?)  -> { Image, ImageRectOffset, ImageRectSize, ImageColor3, ImageTransparency }
	                                 state: "Normal" | "Selected" | "Disabled" (default "Normal")
	  Icons.prompt(action)       -> the input prompt name for the current device:
	                                 "Confirm" -> "KeySpace" | "XboxA" | "PlayStationCross" | "GamepadAction" | "Tap"

	Atlas ids stay nil until the icon sheet is approved and uploaded; Icons.image returns nil then,
	and callers keep their text label. Cells are filled in when the production atlas is built.
]]

local UserInputService = game:GetService("UserInputService")

local Icons = {}

local CREAM = Color3.fromRGB(255, 248, 228)
local GOLD = Color3.fromRGB(240, 198, 96)
local GREY = Color3.fromRGB(150, 170, 165)

Icons.AtlasId = nil -- "rbxassetid://…" after upload approval
local CELL = 128

-- name = { Cell = index in the atlas (row-major), Tint = recolour with state colours? }
Icons.Registry = {
	Map = { Cell = 0, Tint = true },
	Back = { Cell = 1, Tint = true },
	Close = { Cell = 2, Tint = true },
	Check = { Cell = 3, Tint = true },
	Previous = { Cell = 4, Tint = true },
	Next = { Cell = 5, Tint = true },
	Route = { Cell = 6, Tint = true },
	Gate = { Cell = 7, Tint = true },
	Locked = { Cell = 8, Tint = true },
	Warning = nil, -- no suitable icon in the approved packs (see SOURCES.md / review)
	Timer = { Cell = 9, Tint = true },
	Placement = { Cell = 10, Tint = true },
	Spectate = nil, -- no suitable icon in the approved packs
	Select = { Cell = 11, Tint = true },
	Pointer = { Cell = 12, Tint = false },
	KeySpace = { Cell = 13, Tint = false },
	KeyArrows = { Cell = 14, Tint = false },
	KeyW = { Cell = 15, Tint = false },
	GamepadAction = { Cell = 16, Tint = false },
	XboxA = { Cell = 17, Tint = false },
	PlayStationCross = { Cell = 18, Tint = false },
	Tap = { Cell = 19, Tint = false },
	Move = { Cell = 20, Tint = false },
	Jump = { Cell = 21, Tint = true },
	NoMove = { Cell = 22, Tint = false }, -- drawn over Move
	Finish = { Cell = 23, Tint = true },
}

function Icons.image(name: string, state: string?)
	local entry = Icons.Registry[name]
	if not entry or not Icons.AtlasId then
		return nil
	end
	local columns = 1024 // CELL
	local colour = if not entry.Tint then Color3.new(1, 1, 1) elseif state == "Selected" then GOLD elseif state == "Disabled" then GREY else CREAM
	return {
		Image = Icons.AtlasId,
		ImageRectOffset = Vector2.new((entry.Cell % columns) * CELL, (entry.Cell // columns) * CELL),
		ImageRectSize = Vector2.new(CELL, CELL),
		ImageColor3 = colour,
		ImageTransparency = if state == "Disabled" then 0.5 else 0,
	}
end

-- Xbox vs PlayStation: Roblox reports the connected pad's name for a button ("ButtonCross" on a
-- PlayStation pad). Anything unknown falls back to the neutral prompt.
-- shortcut: verify GetStringForKeyCode on real Xbox and PlayStation pads at integration time.
function Icons.prompt(action: string): string?
	if action ~= "Confirm" then
		return nil
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Tap"
	elseif last.Name:find("Gamepad") then
		local ok, label = pcall(UserInputService.GetStringForKeyCode, UserInputService, Enum.KeyCode.ButtonA)
		if ok and label == "ButtonCross" then
			return "PlayStationCross"
		elseif ok and label == "ButtonA" then
			return "XboxA"
		end
		return "GamepadAction"
	end
	return "KeySpace"
end

return Icons
