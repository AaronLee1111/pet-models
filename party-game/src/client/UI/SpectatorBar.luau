--[[
	SpectatorBar
	"👀 Spectating Doge  ◀ ▶" bar shown while the spectator camera is on.
	Buttons work with touch/mouse; Q / E (and gamepad shoulder buttons) also cycle.
]]

local ContextActionService = game:GetService("ContextActionService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local SpectatorBar = {}
SpectatorBar.__index = SpectatorBar

local BIND_NAME = "Party_SpectateCycle"

function SpectatorBar.new(screen: ScreenGui, onCycle: (number) -> ())
	local self = setmetatable({}, SpectatorBar)
	self.OnCycle = onCycle
	self.Root = make("Frame", {
		Name = "SpectatorBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(360, 56),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(28) })

	local function arrow(text: string, x: number, direction: number)
		local button = make("TextButton", {
			Name = if direction < 0 then "Previous" else "Next",
			AnchorPoint = Vector2.new(x, 0.5),
			Position = UDim2.new(x, if x == 0 then 6 else -6, 0.5, 0),
			Size = UDim2.fromOffset(48, 44),
			BackgroundColor3 = Theme.Colors.CardLight,
			Font = Theme.TitleFont,
			TextScaled = true,
			TextColor3 = Theme.Colors.Text,
			Text = text,
			Parent = self.Root,
		}, { Theme.corner(22) })
		button.Activated:Connect(function()
			self.OnCycle(direction)
		end)
	end
	arrow("◀", 0, -1)
	arrow("▶", 1, 1)

	self.Label = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -120, 0.8, 0),
		Font = Theme.TitleFont,
		Parent = self.Root,
	}, 24)
	return self
end

function SpectatorBar:show(targetName: string?)
	self.Label.Text = "👀 " .. (targetName or "Arena")
	if self.Root.Visible then
		return
	end
	self.Root.Visible = true
	ContextActionService:BindAction(BIND_NAME, function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			local back = input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL1
			self.OnCycle(if back then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end

function SpectatorBar:hide()
	if self.Root.Visible then
		ContextActionService:UnbindAction(BIND_NAME)
	end
	self.Root.Visible = false
end

return SpectatorBar
