--[[
	VoteScreen
	Full-screen overlay with up to 3 minigame cards. Clicking a card sends a vote input;
	the counts/voter names shown are whatever the server broadcasts (never local guesses).
]]

local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local VoteScreen = {}
VoteScreen.__index = VoteScreen

function VoteScreen.new(screen: ScreenGui, onVote: (number) -> ())
	local self = setmetatable({}, VoteScreen)
	self.OnVote = onVote
	self.Cards = {}
	self.Selected = nil
	self.EndsAt = nil

	self.Root = make("Frame", {
		Name = "VoteScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = screen,
	})
	self.Title = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.9, 0.1),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		TextStrokeTransparency = 0.4,
		Text = "VOTE FOR THE NEXT MINIGAME!",
		Parent = self.Root,
	}, 56)
	self.Clock = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromScale(0.5, 0.06),
		Font = Theme.TitleFont,
		Parent = self.Root,
	}, 32)
	self.Row = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.92, 0.6),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.02, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		make("UISizeConstraint", { MaxSize = Vector2.new(1100, 460) }),
	})
	return self
end

local function buildCard(self, index: number, choice)
	local card = make("TextButton", {
		Name = "Card" .. index,
		LayoutOrder = index,
		Size = UDim2.fromScale(0.31, 1),
		BackgroundColor3 = Theme.Colors.Card,
		AutoButtonColor = true,
		Text = "",
		Parent = self.Row,
	}, { Theme.corner(18), Theme.padding(12) })
	local stroke = Theme.stroke(Theme.Colors.CardLight, 4)
	stroke.Parent = card

	Theme.label({
		Size = UDim2.fromScale(1, 0.2),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Text = choice.Name,
		Parent = card,
	}, 36)
	Theme.label({
		Position = UDim2.fromScale(0, 0.21),
		Size = UDim2.fromScale(1, 0.09),
		TextColor3 = Theme.Colors.Cool,
		Text = ("%s%s"):format(choice.Layout, if choice.Duration then ("  •  %ds"):format(choice.Duration) else ""),
		Parent = card,
	}, 20)
	Theme.label({
		Position = UDim2.fromScale(0, 0.33),
		Size = UDim2.fromScale(1, 0.37),
		TextColor3 = Theme.Colors.Muted,
		Font = Theme.BodyFont,
		Text = choice.Description,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	}, 20)
	local voters = Theme.label({
		Position = UDim2.fromScale(0, 0.72),
		Size = UDim2.fromScale(1, 0.12),
		TextColor3 = Theme.Colors.Text,
		Text = "",
		Parent = card,
	}, 18)
	local count = Theme.label({
		Position = UDim2.fromScale(0, 0.86),
		Size = UDim2.fromScale(1, 0.14),
		Font = Theme.TitleFont,
		Text = "0 votes",
		Parent = card,
	}, 28)

	card.Activated:Connect(function()
		self.Selected = index
		self:_refreshSelection()
		self.OnVote(index)
	end)

	return { Button = card, Stroke = stroke, Count = count, Voters = voters }
end

function VoteScreen:_refreshSelection()
	for index, card in self.Cards do
		local selected = index == self.Selected
		card.Stroke.Color = if selected then Theme.Colors.Accent else Theme.Colors.CardLight
		card.Button.BackgroundColor3 = if selected then Theme.Colors.CardLight else Theme.Colors.Card
	end
end

function VoteScreen:show(choices, endsAt: number)
	for _, card in self.Cards do
		card.Button:Destroy()
	end
	self.Cards = {}
	self.Selected = nil
	self.EndsAt = endsAt
	for index, choice in choices do
		self.Cards[index] = buildCard(self, index, choice)
	end
	self.Root.Visible = true
	Theme.pop(self.Row)
end

function VoteScreen:updateCounts(counts, voters)
	for index, card in self.Cards do
		local count = counts[index] or 0
		card.Count.Text = if count == 1 then "1 vote" else ("%d votes"):format(count)
		card.Voters.Text = table.concat(voters[index] or {}, ", ")
	end
end

function VoteScreen:update()
	if self.Root.Visible and self.EndsAt then
		local remaining = math.max(0, math.ceil(self.EndsAt - Workspace:GetServerTimeNow()))
		self.Clock.Text = ("⏱ %d"):format(remaining)
	end
end

function VoteScreen:hide()
	self.Root.Visible = false
end

return VoteScreen
