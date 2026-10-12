--[[
	ActionBar
	Big round on-screen buttons for the minigame's actions, bottom-right above the jump
	button. Work with touch and mouse; show the keyboard key on devices with a keyboard.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local ActionBar = {}
ActionBar.__index = ActionBar

local BUTTON_SIZE = 96

function ActionBar.new(screen: ScreenGui)
	local self = setmetatable({}, ActionBar)
	self.Root = make("Frame", {
		Name = "ActionBar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -170), -- clears Roblox's mobile jump button
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE * 3 + 24),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 12),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.Connections = {}
	return self
end

function ActionBar:show(actions, send: (string) -> ())
	self:hide()
	if #actions == 0 then
		return
	end
	local showKeys = UserInputService.KeyboardEnabled
	for index, action in actions do
		local button = make("TextButton", {
			Name = "Action_" .. action.Action,
			LayoutOrder = index,
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			BackgroundColor3 = Theme.Colors.Hot,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = true,
			Parent = self.Root,
		}, { Theme.corner(BUTTON_SIZE // 2), Theme.stroke(Color3.new(1, 1, 1), 3) })
		Theme.label({
			Size = UDim2.fromScale(1, if showKeys then 0.7 else 1),
			Font = Theme.TitleFont,
			Text = action.Label,
			Parent = button,
		}, 26)
		if showKeys and action.Key then
			Theme.label({
				Position = UDim2.fromScale(0, 0.65),
				Size = UDim2.fromScale(1, 0.25),
				TextColor3 = Theme.Colors.Accent,
				Text = "[" .. action.Key .. "]",
				Parent = button,
			}, 16)
		end
		table.insert(
			self.Connections,
			button.Activated:Connect(function()
				send(action.Action)
			end)
		)
	end
	self.Root.Visible = true
end

function ActionBar:hide()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, child in self.Root:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	self.Root.Visible = false
end

return ActionBar
