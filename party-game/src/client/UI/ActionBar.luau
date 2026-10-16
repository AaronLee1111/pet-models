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
local ABOVE_JUMP_BUTTON = -170 -- bottom offset that clears Roblox's mobile jump button
local BOTTOM_CORNER = -28 -- used when movement is locked, so there is no jump button to clear

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
	-- Second column in the bottom-left corner for actions with Side = "Left" (e.g. steer left).
	self.LeftRoot = make("Frame", {
		Name = "ActionBarLeft",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -170),
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

-- `low` = sit in the bottom corners (thumb reach) instead of above the jump button.
function ActionBar:show(actions, send: (string) -> (), low: boolean?)
	self:hide()
	local offset = if low then BOTTOM_CORNER else ABOVE_JUMP_BUTTON
	self.Root.Position = UDim2.new(1, -24, 1, offset)
	self.LeftRoot.Position = UDim2.new(0, 24, 1, offset)
	if #actions == 0 then
		return
	end
	-- Key hints only off touch screens: phones (and Studio's phone emulator) can report a
	-- keyboard and even a mouse, so any touch screen gets the plain button.
	local showKeys = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
	for index, action in actions do
		local button = make("TextButton", {
			Name = "Action_" .. action.Action,
			LayoutOrder = index,
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			BackgroundColor3 = action.Color or Theme.Colors.Hot,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = true,
			Parent = if action.Side == "Left" then self.LeftRoot else self.Root,
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
		if action.Hold then
			-- Press and hold: send on finger/mouse down, "<Action>Stop" when that same input ends.
			table.insert(
				self.Connections,
				button.InputBegan:Connect(function(input)
					if
						input.UserInputType ~= Enum.UserInputType.Touch
						and input.UserInputType ~= Enum.UserInputType.MouseButton1
					then
						return
					end
					send(action.Action)
					local released
					released = input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							released:Disconnect()
							send(action.Action .. "Stop")
						end
					end)
					table.insert(self.Connections, released)
				end)
			)
		else
			table.insert(
				self.Connections,
				button.Activated:Connect(function()
					send(action.Action)
				end)
			)
		end
	end
	self.Root.Visible = true
	self.LeftRoot.Visible = true
end

function ActionBar:hide()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, root in { self.Root, self.LeftRoot } do
		for _, child in root:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		root.Visible = false
	end
end

return ActionBar
