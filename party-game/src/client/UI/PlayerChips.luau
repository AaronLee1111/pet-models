--[[
	PlayerChips
	The strip of four player chips under the timer: name, team colour, the live value the
	minigame reports with ReportProgress, and a crossed-out look once eliminated.
]]

local Theme = require(script.Parent.Theme)
local make = Theme.make

local PlayerChips = {}
PlayerChips.__index = PlayerChips

function PlayerChips.new(screen: ScreenGui)
	local self = setmetatable({}, PlayerChips)
	self.Root = make("Frame", {
		Name = "PlayerChips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.new(0.9, 0, 0, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		make("UISizeConstraint", { MaxSize = Vector2.new(700, 60) }),
	})
	self.Chips = {} -- Id -> widgets
	return self
end

local function buildChip(parent: Instance, order: number)
	local frame = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromScale(0.24, 1),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.1,
		Parent = parent,
	}, { Theme.corner(12), Theme.padding(4) })
	local stroke = Theme.stroke(Theme.Colors.CardLight, 2)
	stroke.Parent = frame
	local name = Theme.label({
		Size = UDim2.fromScale(1, 0.4),
		Parent = frame,
	}, 16)
	local value = Theme.label({
		Position = UDim2.fromScale(0, 0.4),
		Size = UDim2.fromScale(1, 0.4),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Parent = frame,
	}, 22)
	local caption = Theme.label({
		Position = UDim2.fromScale(0, 0.8),
		Size = UDim2.fromScale(1, 0.2),
		TextColor3 = Theme.Colors.Muted,
		Parent = frame,
	}, 11)
	return { Frame = frame, Stroke = stroke, Name = name, Value = value, Caption = caption }
end

function PlayerChips:update(chips, myId: string)
	local seen = {}
	for order, chip in chips do
		seen[chip.Id] = true
		local widgets = self.Chips[chip.Id] or buildChip(self.Root, order)
		self.Chips[chip.Id] = widgets
		widgets.Frame.LayoutOrder = order

		local isMe = chip.Id == myId
		widgets.Name.Text = (if chip.IsBot then "🤖 " else "") .. (if isMe then "YOU" else chip.Name)
		widgets.Value.Text = if chip.Eliminated
			then "❌ " .. (if chip.Value ~= nil then tostring(chip.Value) else "OUT")
			elseif chip.Value ~= nil then tostring(chip.Value)
			else "—"
		widgets.Caption.Text = chip.Label or ""
		widgets.Stroke.Color = if isMe
			then Theme.Colors.Accent
			elseif chip.Team then Theme.TeamColors[chip.Team]
			else Theme.Colors.CardLight
		widgets.Stroke.Thickness = if isMe then 3 else 2
		widgets.Frame.BackgroundTransparency = if chip.Eliminated then 0.6 else 0.1
		widgets.Value.TextColor3 = if chip.Eliminated then Theme.Colors.Muted else Theme.Colors.Accent
	end
	for id, widgets in self.Chips do
		if not seen[id] then
			widgets.Frame:Destroy()
			self.Chips[id] = nil
		end
	end
end

function PlayerChips:show()
	self.Root.Visible = true
end

function PlayerChips:hide()
	self.Root.Visible = false
	for id, widgets in self.Chips do
		widgets.Frame:Destroy()
		self.Chips[id] = nil
	end
end

return PlayerChips
