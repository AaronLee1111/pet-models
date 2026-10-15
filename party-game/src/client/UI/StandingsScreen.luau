--[[
	StandingsScreen
	End-of-match screens, in order (message.Stage):
	  Before   standings before the bonus awards
	  Bonus    which bonus went to whom (one Crown each)
	  Final    final standings: collectibles first, coins break ties (ranked by the server)
]]

local Theme = require(script.Parent.Theme)
local make = Theme.make

local StandingsScreen = {}
StandingsScreen.__index = StandingsScreen

function StandingsScreen.new(screen: ScreenGui)
	local self = setmetatable({}, StandingsScreen)
	self.Root = make("Frame", {
		Name = "Standings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.78),
		BackgroundColor3 = Theme.Colors.Card,
		Visible = false,
		Parent = screen,
	}, {
		Theme.corner(22),
		Theme.stroke(Theme.Colors.Accent, 4),
		Theme.padding(16),
		make("UISizeConstraint", { MaxSize = Vector2.new(680, 500) }),
	})
	self.Title = Theme.label({
		Size = UDim2.fromScale(1, 0.16),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Parent = self.Root,
	}, 44)
	self.List = make("Frame", {
		Position = UDim2.fromScale(0, 0.2),
		Size = UDim2.fromScale(1, 0.8),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, { make("UIListLayout", { Padding = UDim.new(0.03, 0), SortOrder = Enum.SortOrder.LayoutOrder }) })
	return self
end

local function showBonuses(self, message, myId: string)
	self.Title.Text = "Bonus awards!"
	local plural = message.CollectiblePlural or "Crowns"
	for index, bonus in message.Bonuses or {} do
		local names, mine = {}, false
		for _, winner in bonus.Winners do
			table.insert(names, if winner.Id == myId then "You" else winner.Name)
			mine = mine or winner.Id == myId
		end
		local frame = make("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 0.28),
			BackgroundColor3 = if mine then Theme.Colors.CardLight else Theme.Colors.Overlay,
			Parent = self.List,
		}, { Theme.corner(12), Theme.padding(6) })
		Theme.label({
			Size = UDim2.fromScale(0.5, 0.55),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.TitleFont,
			TextColor3 = Theme.Colors.Accent,
			Text = bonus.Name,
			Parent = frame,
		}, 28)
		Theme.label({
			Position = UDim2.fromScale(0, 0.55),
			Size = UDim2.fromScale(0.5, 0.45),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.Muted,
			Text = bonus.Description,
			Parent = frame,
		}, 18)
		Theme.label({
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.5, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = if #names > 0
				then ("%s  +%d %s"):format(table.concat(names, ", "), bonus.Crowns, if bonus.Crowns == 1 then string.sub(plural, 1, -2) else plural)
				else "Nobody",
			Parent = frame,
		}, 24)
	end
end

function StandingsScreen:show(message, myId: string)
	for _, child in self.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	self.Root.Visible = true
	if message.Stage == "Bonus" then
		showBonuses(self, message, myId)
		Theme.pop(self.Root)
		return
	end
	local rows = message.Rows or {}
	local winner = rows[1]
	local tied = rows[2] ~= nil and rows[2].Placement == 1
	if message.Stage == "Before" then
		self.Title.Text = "Standings before bonuses"
	elseif not winner then
		self.Title.Text = "Match over"
	elseif tied then
		self.Title.Text = "It's a tie for 1st!"
	elseif winner.Id == myId then
		self.Title.Text = "You win the match!"
	else
		self.Title.Text = ("%s wins the match!"):format(winner.Name)
	end
	local plural = message.CollectiblePlural or "Crowns"
	for index, row in rows do
		local isMe = row.Id == myId
		local frame = make("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 0.22),
			BackgroundColor3 = if isMe then Theme.Colors.CardLight else Theme.Colors.Overlay,
			Parent = self.List,
		}, { Theme.corner(12), Theme.padding(6) })
		if isMe then
			Theme.stroke(Theme.Colors.Accent, 2).Parent = frame
		end
		Theme.label({
			Size = UDim2.fromScale(0.16, 1),
			Font = Theme.TitleFont,
			TextColor3 = Theme.PlacementColors[row.Placement] or Theme.PlacementColors[4],
			Text = Theme.ordinal(row.Placement),
			Parent = frame,
		}, 34)
		Theme.label({
			Position = UDim2.fromScale(0.18, 0),
			Size = UDim2.fromScale(0.4, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = row.Name .. (if row.IsBot then " (bot)" else "") .. (if isMe then " (you)" else ""),
			Parent = frame,
		}, 26)
		Theme.label({
			Position = UDim2.fromScale(0.58, 0),
			Size = UDim2.fromScale(0.22, 1),
			Font = Theme.TitleFont,
			TextColor3 = Theme.Colors.Accent,
			Text = ("%d %s"):format(row.Collectibles, plural),
			Parent = frame,
		}, 26)
		Theme.label({
			Position = UDim2.fromScale(0.8, 0),
			Size = UDim2.fromScale(0.2, 1),
			TextColor3 = Theme.Colors.Muted,
			Text = ("%d coins"):format(row.Coins),
			Parent = frame,
		}, 22)
	end
	self.Root.Visible = true
	Theme.pop(self.Root)
end

function StandingsScreen:hide()
	self.Root.Visible = false
end

return StandingsScreen
