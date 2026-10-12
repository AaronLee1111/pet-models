--[[
	ResultsScreen
	Placements and coins awarded, exactly as the server ranked them.
]]

local Theme = require(script.Parent.Theme)
local make = Theme.make

local ResultsScreen = {}
ResultsScreen.__index = ResultsScreen

function ResultsScreen.new(screen: ScreenGui)
	local self = setmetatable({}, ResultsScreen)

	self.Root = make("Frame", {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.75),
		BackgroundColor3 = Theme.Colors.Card,
		Visible = false,
		Parent = screen,
	}, {
		Theme.corner(22),
		Theme.stroke(Theme.Colors.Accent, 4),
		Theme.padding(18),
		make("UISizeConstraint", { MaxSize = Vector2.new(680, 500) }),
	})
	self.Title = Theme.label({
		Size = UDim2.fromScale(1, 0.16),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Parent = self.Root,
	}, 46)
	self.List = make("Frame", {
		Position = UDim2.fromScale(0, 0.2),
		Size = UDim2.fromScale(1, 0.8),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0.03, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	return self
end

local function buildRow(parent: Instance, index: number, row, isMe: boolean)
	local placeColor = Theme.PlacementColors[row.Placement] or Theme.PlacementColors[4]
	local frame = make("Frame", {
		LayoutOrder = index,
		Size = UDim2.fromScale(1, 0.22),
		BackgroundColor3 = if isMe then Theme.Colors.CardLight else Theme.Colors.Overlay,
		Parent = parent,
	}, { Theme.corner(12), Theme.padding(6) })
	if isMe then
		Theme.stroke(Theme.Colors.Accent, 2).Parent = frame
	end

	Theme.label({
		Size = UDim2.fromScale(0.16, 1),
		Font = Theme.TitleFont,
		TextColor3 = placeColor,
		Text = Theme.ordinal(row.Placement),
		Parent = frame,
	}, 34)
	local name = (if row.IsBot then "🤖 " else "") .. row.Name .. (if isMe then " (you)" else "")
	Theme.label({
		Position = UDim2.fromScale(0.18, 0),
		Size = UDim2.fromScale(0.46, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if row.Team then Theme.TeamColors[row.Team] else Theme.Colors.Text,
		Text = name,
		Parent = frame,
	}, 26)
	Theme.label({
		Position = UDim2.fromScale(0.64, 0),
		Size = UDim2.fromScale(0.16, 1),
		Font = Theme.TitleFont,
		TextColor3 = if row.Coins > 0 then Theme.Colors.Accent else Theme.Colors.Muted,
		Text = ("+%d 🪙"):format(row.Coins),
		Parent = frame,
	}, 28)
	Theme.label({
		Position = UDim2.fromScale(0.8, 0),
		Size = UDim2.fromScale(0.2, 1),
		TextColor3 = Theme.Colors.Muted,
		Text = ("Total %d"):format(row.Total),
		Parent = frame,
	}, 20)
end

function ResultsScreen:show(minigame, rows, myId: string)
	for _, child in self.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	self.Title.Text = ("🏆 %s — Results"):format(minigame.Name)
	for index, row in rows do
		buildRow(self.List, index, row, row.Id == myId)
	end
	self.Root.Visible = true
	Theme.pop(self.Root)
end

function ResultsScreen:hide()
	self.Root.Visible = false
end

return ResultsScreen
