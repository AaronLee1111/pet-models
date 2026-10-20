--[[
	TurnMenu
	The left vertical turn menu: ROLL / ITEMS / MAP, and the item list that opens beside it.
	ROLL is selected by default; the selected row gets the gold arrow, glow and a small pulse.
	A disabled row stays visible, dimmed, and says why when you pick it.

	Input: tap / click a row (a second tap on the selected row activates it); arrow keys, W/S or
	the D-pad move; Enter or gamepad A activates; Backspace or B goes back from the item list.

	  local menu = TurnMenu.new(screen, {
	      Roll = fn(), Map = fn(), UseItem = fn(slot), Changed = fn(key) })
	  menu:setRows({ Roll = { Visible, Enabled, Reason }, Items = {...}, Map = {..., Label} })
	  menu:select(key)            "Roll" | "Items" | "Map"
	  menu:openItems(items) / menu:closeItems()
	  menu:bind() / menu:unbind() keyboard + gamepad while the menu is up
	  menu.Root, menu.Rows.Roll.Button ("BoardRoll"), menu.Rows.Map.Button ("BoardMap"),
	  menu.ItemPanel ("BoardItems": item buttons have LayoutOrder = slot)
]]

local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local TurnMenu = {}
TurnMenu.__index = TurnMenu

TurnMenu.ROW = Vector2.new(240, 84) -- design px; 84 * 0.55 (smallest phone scale) = 46 px tall
TurnMenu.GAP = 8
TurnMenu.ITEM_ROW = Vector2.new(380, 84)
local ORDER = { "Roll", "Items", "Map" }
local NAV_ACTION = "PartyTurnMenuNav"
local CREAM, GOLD, DEEP = Theme.Glass.Cream, Theme.Glass.Gold, Theme.Glass.Deep

-- Original icons drawn from frames (crisp at any size) ------------------------------------------

local function dieIcon(parent)
	local face = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		Rotation = -10,
		BackgroundColor3 = CREAM,
		Parent = parent,
	}, { Theme.corner(8), Theme.stroke(GOLD, 2) })
	for _, p in { { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.5, 0.5 }, { 0.25, 0.75 }, { 0.75, 0.75 } } do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(p[1], p[2]),
			Size = UDim2.fromScale(0.2, 0.2),
			BackgroundColor3 = DEEP,
			Parent = face,
		}, { Theme.corner(99) })
	end
end

local function cardIcon(parent)
	for i, rotation in { -14, 8 } do
		local card = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.44 + (i - 1) * 0.12, 0.5),
			Size = UDim2.fromScale(0.42, 0.6),
			Rotation = rotation,
			BackgroundColor3 = if i == 2 then CREAM else Color3.fromRGB(120, 200, 180),
			Parent = parent,
		}, { Theme.corner(6), Theme.stroke(GOLD, 2) })
		if i == 2 then
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.TitleFont,
				TextScaled = true,
				TextColor3 = GOLD,
				Text = "★",
				Parent = card,
			})
		end
	end
end

local function mapIcon(parent)
	for i = 1, 3 do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.3 + (i - 1) * 0.2, 0.5),
			Size = UDim2.fromScale(0.22, 0.6),
			Rotation = if i == 2 then 8 else -8,
			BackgroundColor3 = if i == 2 then Color3.fromRGB(150, 215, 190) else CREAM,
			BorderSizePixel = 0,
			Parent = parent,
		}, { Theme.stroke(GOLD, 1.5) })
	end
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.56, 0.42),
		Size = UDim2.fromScale(0.16, 0.16),
		BackgroundColor3 = Color3.fromRGB(230, 80, 80),
		Parent = parent,
	}, { Theme.corner(99) })
end

local ICONS = { Roll = dieIcon, Items = cardIcon, Map = mapIcon }
local LABELS = { Roll = "ROLL", Items = "ITEMS", Map = "MAP" }
local NAMES = { Roll = "BoardRoll", Items = "BoardItemsButton", Map = "BoardMap" }

local function newRow(parent, key: string, order: number, size: Vector2, onClick)
	local button = Theme.glass(make("TextButton", {
		Name = NAMES[key] or key,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size.X, size.Y),
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	}), 20)
	local iconHolder = make("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(size.Y - 20, size.Y - 20),
		BackgroundColor3 = DEEP,
		BackgroundTransparency = 0.3,
		Parent = button,
	}, { Theme.corner(99) })
	local label = make("TextLabel", {
		Position = UDim2.fromOffset(size.Y, 8),
		Size = UDim2.new(1, -size.Y - 8, 0, 40),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = CREAM,
		Parent = button,
	})
	local note = make("TextLabel", {
		Position = UDim2.fromOffset(size.Y, 48),
		Size = UDim2.new(1, -size.Y - 8, 0, 26),
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = GOLD,
		Parent = button,
	})
	local arrow = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -2, 0.5, 0),
		Size = UDim2.fromOffset(26, 40),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 34,
		TextColor3 = GOLD,
		Text = "▶",
		Visible = false,
		Parent = button,
	}, { make("UIStroke", { Color = DEEP, Thickness = 2 }) })
	local row = {
		Key = key,
		Button = button,
		Icon = iconHolder,
		Label = label,
		Note = note,
		Arrow = arrow,
		Stroke = button:FindFirstChildOfClass("UIStroke"),
		Scale = make("UIScale", { Parent = button }),
		Enabled = true,
		Reason = nil,
	}
	button.Activated:Connect(function()
		onClick(row)
	end)
	return row
end

function TurnMenu.new(screen: ScreenGui, handlers)
	local self = setmetatable({ Handlers = handlers, Rows = {}, Selected = "Roll", ItemRows = {}, ItemsOpen = false }, TurnMenu)
	self.Root = make("Frame", {
		Name = "TurnMenu",
		Size = UDim2.fromOffset(TurnMenu.ROW.X, 3 * TurnMenu.ROW.Y + 2 * TurnMenu.GAP),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	self.Scale = make("UIScale", { Parent = self.Root })
	local rows = make("Frame", {
		Name = "Rows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, { make("UIListLayout", { Padding = UDim.new(0, TurnMenu.GAP), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for order, key in ORDER do
		local row = newRow(rows, key, order, TurnMenu.ROW, function(row)
			if self.Selected == row.Key or not row.Enabled then
				self:activate(row.Key)
			else
				self:select(row.Key)
			end
		end)
		row.Label.Text = LABELS[key]
		ICONS[key](row.Icon)
		self.Rows[key] = row
	end

	-- Item list: opens to the right of the menu, same glass, with Back at the bottom.
	self.ItemPanel = make("Frame", {
		Name = "BoardItems",
		Position = UDim2.new(1, 34, 0, 0),
		Size = UDim2.fromOffset(TurnMenu.ITEM_ROW.X, TurnMenu.ITEM_ROW.Y),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Root,
	}, { make("UIListLayout", { Padding = UDim.new(0, TurnMenu.GAP), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self:select("Roll")
	return self
end

-- spec[key] = { Visible = bool, Enabled = bool, Reason = string?, Note = string?, Label = string? }
function TurnMenu:setRows(spec)
	for key, row in self.Rows do
		local s = spec[key] or {}
		row.Button.Visible = s.Visible ~= false
		row.Enabled = s.Enabled ~= false
		row.Reason = s.Reason
		row.Label.Text = s.Label or LABELS[key]
		row.Label.TextColor3 = if row.Enabled then CREAM else Theme.Glass.Disabled
		row.Button.BackgroundTransparency = if row.Enabled then Theme.Glass.Transparency else 0.45
		row.Icon.BackgroundTransparency = if row.Enabled then 0.3 else 0.6
		row.BaseNote = s.Note or ""
		row.Note.Text = row.BaseNote
		row.Note.TextColor3 = GOLD
	end
	if not (self.Rows[self.Selected] and self.Rows[self.Selected].Button.Visible) then
		for _, key in ORDER do
			if self.Rows[key].Button.Visible then
				self:select(key)
				break
			end
		end
	end
	self:refreshSelection()
end

function TurnMenu:refreshSelection()
	for key, row in self.Rows do
		local selected = key == self.Selected and not self.ItemsOpen
		local lit = key == self.Selected -- ITEMS stays lit while its list is open
		row.Arrow.Visible = selected
		row.Stroke.Thickness = if lit then 4 else 2
		row.Button.BackgroundColor3 = if lit then Color3.fromRGB(44, 128, 112) else Theme.Glass.Fill
		-- A disabled row explains itself while it's picked.
		row.Note.Text = if selected and not row.Enabled and row.Reason then row.Reason else row.BaseNote or ""
		row.Note.TextColor3 = if selected and not row.Enabled then Color3.fromRGB(255, 190, 170) else GOLD
	end
	for _, item in self.ItemRows do
		local selected = self.ItemsOpen and item.Key == self.ItemSelected
		item.Arrow.Visible = selected
		item.Stroke.Thickness = if selected then 4 else 2
		item.Button.BackgroundColor3 = if selected then Color3.fromRGB(44, 128, 112) else Theme.Glass.Fill
	end
end

local function pulse(row)
	row.Scale.Scale = 0.94
	TweenService:Create(row.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function TurnMenu:select(key: string)
	if self.Selected ~= key then
		Theme.tick(0.2)
	end
	self.Selected = key
	self:refreshSelection()
	local row = self.Rows[key]
	if row then
		pulse(row)
	end
	if self.Handlers.Changed then
		self.Handlers.Changed(key)
	end
end

function TurnMenu:activate(key: string)
	local row = self.Rows[key]
	if not row or not row.Button.Visible then
		return
	end
	if self.Selected ~= key then
		self:select(key)
	end
	if not row.Enabled then
		-- Say why, with a small shake.
		self:refreshSelection()
		local x = row.Button.Position
		TweenService:Create(row.Button, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Position = x + UDim2.fromOffset(6, 0) }):Play()
		return
	end
	pulse(row)
	if key == "Roll" and self.Handlers.Roll then
		self.Handlers.Roll()
	elseif key == "Items" then
		self:openItems(self.Items or {})
	elseif key == "Map" and self.Handlers.Map then
		self.Handlers.Map()
	end
end

function TurnMenu:setItems(items)
	local ids = {}
	for _, item in items do
		table.insert(ids, item.Id)
	end
	local key = table.concat(ids, ",")
	self.Items = items
	if self.ItemsOpen and key ~= self.ItemsKey then
		self:openItems(items)
	end
	self.ItemsKey = key
end

function TurnMenu:openItems(items)
	self.Items = items
	for _, item in self.ItemRows do
		item.Button:Destroy()
	end
	self.ItemRows = {}
	local list = {}
	for slot, item in items do
		table.insert(list, { Key = slot, Item = item })
	end
	table.insert(list, { Key = "Back" })
	for index, entry in list do
		local row = newRow(self.ItemPanel, if entry.Item then "Item" .. entry.Key else "Back", if entry.Item then entry.Key else 99, TurnMenu.ITEM_ROW, function(row)
			if self.ItemSelected == entry.Key then
				self:activateItem(entry.Key)
			else
				self.ItemSelected = entry.Key
				Theme.tick(0.2)
				self:refreshSelection()
			end
		end)
		row.Key = entry.Key
		if entry.Item then
			row.Label.Text = entry.Item.Name
			row.Label.TextSize = 28
			row.Note.Text = entry.Item.Description or ""
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.TitleFont,
				TextScaled = true,
				TextColor3 = CREAM,
				Text = Theme.itemGlyph(entry.Item.Id),
				Parent = row.Icon,
			}, { Theme.padding(8) })
		else
			row.Label.Text = "Back"
			row.Note.Text = "Roll without an item"
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.TitleFont,
				TextScaled = true,
				TextColor3 = CREAM,
				Text = "◀",
				Parent = row.Icon,
			}, { Theme.padding(12) })
		end
		row.Index = index
		table.insert(self.ItemRows, row)
	end
	self.ItemsOpen = true
	self.ItemSelected = list[1].Key
	self.ItemPanel.Visible = true
	Theme.pop(self.ItemPanel)
	self:refreshSelection()
end

function TurnMenu:closeItems()
	if not self.ItemsOpen then
		return
	end
	self.ItemsOpen = false
	self.ItemPanel.Visible = false
	self.Selected = "Roll"
	self:refreshSelection()
	if self.Handlers.Changed then
		self.Handlers.Changed("Roll")
	end
end

function TurnMenu:activateItem(key)
	if key == "Back" then
		self:closeItems()
	elseif type(key) == "number" and self.Handlers.UseItem then
		self.Handlers.UseItem(key)
		self:closeItems()
	end
end

local function step(self, direction: number)
	if self.ItemsOpen then
		local index = 1
		for i, row in self.ItemRows do
			if row.Key == self.ItemSelected then
				index = i
			end
		end
		index = math.clamp(index + direction, 1, #self.ItemRows)
		self.ItemSelected = self.ItemRows[index].Key
		Theme.tick(0.2)
		self:refreshSelection()
		return
	end
	local visible = {}
	for _, key in ORDER do
		if self.Rows[key].Button.Visible then
			table.insert(visible, key)
		end
	end
	local index = table.find(visible, self.Selected) or 1
	local nextKey = visible[math.clamp(index + direction, 1, #visible)]
	if nextKey then
		self:select(nextKey)
	end
end

function TurnMenu:bind()
	ContextActionService:BindAction(NAV_ACTION, function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Up or key == Enum.KeyCode.W or key == Enum.KeyCode.DPadUp then
			step(self, -1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S or key == Enum.KeyCode.DPadDown then
			step(self, 1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			if self.ItemsOpen then
				self:activateItem(self.ItemSelected)
			else
				self:activate(self.Selected)
			end
		elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then
			self:closeItems()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.Return, Enum.KeyCode.ButtonA, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
end

function TurnMenu:unbind()
	ContextActionService:UnbindAction(NAV_ACTION)
end

return TurnMenu
