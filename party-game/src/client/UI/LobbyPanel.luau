--[[
	LobbyPanel
	Waiting-room card (bottom centre, so the lobby stays visible). Three parts, so every
	control stays on screen whatever the screen size:
	  * header: title, countdown and the SHOP button, plus one status line (players, host,
	    bank coins) that is cut short rather than allowed to push anything out
	  * settings body: Mode, Board, Rounds, Bots and the wardrobe row. Only this part scrolls,
	    when the screen is too short to show it all (touch drag, mouse wheel, gamepad selection)
	  * right column: START for the host, a waiting note for everyone else; never scrolls
	On touch screens the card also stays between Roblox's thumbstick and jump button.
	The card fits itself between Roblox's top bar and the bottom of the screen at the HUD scale
	Main applies (LobbyPanel.fitHeight). The host can change settings and start early; everyone
	else just sees them. Wardrobe: tap a cosmetic you own to wear it, tap again to take it off.
	The server checks every change.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local LobbyPanel = {}
LobbyPanel.__index = LobbyPanel

-- Layout, in design units (Main's UIScale turns them into pixels; 52 units is 44 px at the
-- smallest waiting-room scale, 0.85).
LobbyPanel.WIDTH = 640
LobbyPanel.PADDING = 12
LobbyPanel.HEADER = 52 -- title, countdown, SHOP
LobbyPanel.INFO = 24 -- status line
LobbyPanel.GAP = 8
LobbyPanel.ROW = 52 -- one settings row (touch-sized buttons)
LobbyPanel.BOTTOM_MARGIN = 16 -- design units from the bottom of the screen
LobbyPanel.TOP_MARGIN = 8 -- pixels kept free below Roblox's top bar
LobbyPanel.CONTROL_GAP = 16 -- pixels kept free beside Roblox's thumbstick and jump button
LobbyPanel.BODY_TOP = LobbyPanel.HEADER + 4 + LobbyPanel.INFO + LobbyPanel.GAP
local BODY_TOP = LobbyPanel.BODY_TOP

--[[
	Card height (design units) for `rows` settings rows on a screen `screenHeight` pixels tall
	with `topInset` pixels of Roblox top bar, at UI scale `scale`. Tall screens show the whole
	list; shorter ones get a shorter card whose settings body scrolls. Never taller than the free
	space, never shorter than the header plus one row (so START and SHOP always fit).
	Returns height, natural height (everything showing).
]]
function LobbyPanel.fitHeight(rows: number, screenHeight: number, topInset: number, scale: number)
	local natural = LobbyPanel.PADDING * 2 + BODY_TOP + rows * LobbyPanel.ROW + math.max(0, rows - 1) * LobbyPanel.GAP
	local minimum = LobbyPanel.PADDING * 2 + BODY_TOP + LobbyPanel.ROW
	local free = (screenHeight - topInset - LobbyPanel.TOP_MARGIN) / math.max(scale, 0.01) - LobbyPanel.BOTTOM_MARGIN
	return math.max(minimum, math.min(natural, free)), natural
end

--[[
	Card width (design units): the full WIDTH, unless Roblox's touch controls sit in the bottom
	corners, in which case the card stays between them. `reserve` = pixels each side to keep
	free (0 without touch controls).
]]
function LobbyPanel.fitWidth(screenWidth: number, reserve: number, scale: number): number
	local free = (screenWidth - 2 * reserve) / math.max(scale, 0.01)
	return math.max(math.min(LobbyPanel.WIDTH, free), LobbyPanel.WIDTH * 0.7)
end

-- Pixels to keep free on each side for the thumbstick and jump button (0 when there are none).
local function touchReserve(screenWidth: number): number
	if not UserInputService.TouchEnabled then
		return 0
	end
	local touchGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		and Players.LocalPlayer.PlayerGui:FindFirstChild("TouchGui")
	local stick = touchGui and touchGui:FindFirstChild("ThumbstickStart", true)
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	local left = if stick then stick.AbsolutePosition.X + stick.AbsoluteSize.X else screenWidth * 0.14
	local right = if jump then screenWidth - jump.AbsolutePosition.X else screenWidth * 0.13
	return math.max(left, right) + LobbyPanel.CONTROL_GAP
end

-- How a board id reads to players (the server sends each board's DisplayName).
local function boardName(message, id): string
	local names = message and message.BoardNames
	return names and names[id] or tostring(id)
end

function LobbyPanel.new(screen: ScreenGui, send: (any) -> ())
	local self = setmetatable(
		{ Send = send, EndsAt = nil, Inventory = nil, LastMessage = nil, Screen = screen, Rows = 5 },
		LobbyPanel
	)

	self.Root = make("Frame", {
		Name = "WaitingRoom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -LobbyPanel.BOTTOM_MARGIN),
		Size = UDim2.fromOffset(LobbyPanel.WIDTH, 404),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(20), Theme.stroke(Theme.Colors.Accent, 3), Theme.padding(LobbyPanel.PADDING) })

	-- Header: title | countdown | SHOP
	self.Title = Theme.label({
		Size = UDim2.new(0.36, 0, 0, LobbyPanel.HEADER),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Text = "PARTY GAMES",
		Parent = self.Root,
	}, 32)
	self.Clock = Theme.label({
		Position = UDim2.fromScale(0.36, 0),
		Size = UDim2.new(0.42, -8, 0, LobbyPanel.HEADER),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.TitleFont,
		Parent = self.Root,
	}, 30)
	-- On a narrow card (phones) the title and countdown shrink to fit instead of overlapping.
	for label, size in { [self.Title] = 32, [self.Clock] = 30 } do
		label.TextScaled = true
		make("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = 14, Parent = label })
	end
	-- Opens the permanent Cosmetics Shop (bank coins). In the header so it never scrolls away.
	self.ShopButton = make("TextButton", {
		Name = "ShopButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.22, 0, 0, LobbyPanel.HEADER),
		BackgroundColor3 = Theme.Colors.Accent,
		Font = Theme.TitleFont,
		TextScaled = true,
		TextColor3 = Theme.Colors.Overlay,
		Text = "SHOP",
		Parent = self.Root,
	}, { Theme.corner(12), Theme.padding(8), make("UITextSizeConstraint", { MaxTextSize = 26 }) })
	self.ShopButton.Activated:Connect(function()
		if self.OnShop then
			self.OnShop()
		end
	end)
	self.Info = Theme.label({
		Position = UDim2.fromOffset(0, LobbyPanel.HEADER + 4),
		Size = UDim2.new(1, 0, 0, LobbyPanel.INFO),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd, -- long names never push the controls out
		Parent = self.Root,
	}, 20)

	-- Settings body: the only part that scrolls.
	self.SettingRows = make("ScrollingFrame", {
		Name = "Settings",
		Position = UDim2.fromOffset(0, BODY_TOP),
		Size = UDim2.new(0.72, 0, 1, -BODY_TOP),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Parent = self.Root,
	}, { make("UIListLayout", { Padding = UDim.new(0, LobbyPanel.GAP), SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- Right column: START (host) or a waiting note (everyone else). Never scrolls.
	self.StartButton = make("TextButton", {
		Name = "StartButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, BODY_TOP),
		Size = UDim2.new(0.26, 0, 1, -BODY_TOP),
		BackgroundColor3 = Theme.Colors.Good,
		Font = Theme.TitleFont,
		TextScaled = true,
		TextColor3 = Theme.Colors.Overlay,
		Text = "START",
		Visible = false,
		Parent = self.Root,
	}, { Theme.corner(16), Theme.padding(10), make("UITextSizeConstraint", { MaxTextSize = 34 }) })
	self.StartButton.Activated:Connect(function()
		self.Send({ Kind = "StartMatch" })
	end)
	self.WaitingNote = Theme.label({
		Name = "WaitingNote",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, BODY_TOP),
		Size = UDim2.new(0.26, 0, 1, -BODY_TOP),
		TextWrapped = true,
		TextColor3 = Theme.Colors.Muted,
		Text = "The host starts the match, or it starts when the timer ends",
		Visible = false,
		Parent = self.Root,
	}, 20)

	-- Re-fit whenever the screen or the HUD scale changes.
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:fit()
	end)
	self.Root:GetAttributeChangedSignal("HudScale"):Connect(function()
		self:fit()
	end)
	return self
end

-- Sizes the card to the screen (see LobbyPanel.fitHeight).
function LobbyPanel:fit()
	local screenHeight = self.Screen.AbsoluteSize.Y
	if screenHeight <= 0 then
		return
	end
	local scale = self.Root:GetAttribute("HudScale") or 1
	local inset = if self.Screen.IgnoreGuiInset then GuiService:GetGuiInset().Y else 0
	local height = LobbyPanel.fitHeight(self.Rows, screenHeight, inset, scale)
	local screenWidth = self.Screen.AbsoluteSize.X
	local width = LobbyPanel.fitWidth(screenWidth, touchReserve(screenWidth), scale)
	self.Root.Size = UDim2.fromOffset(width, height)
end

-- Owned cosmetics as toggles; the server confirms with a fresh Inventory message.
local function wardrobeRow(self, order: number)
	local inventory = self.Inventory or { Owned = {}, Equipped = {} }
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, LobbyPanel.ROW),
		BackgroundTransparency = 1,
		Parent = self.SettingRows,
	})
	Theme.label({
		Size = UDim2.new(0.28, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Wear",
		Parent = row,
	}, 22)
	local buttons = make("ScrollingFrame", {
		Position = UDim2.fromScale(0.28, 0),
		Size = UDim2.fromScale(0.72, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = row,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	if #inventory.Owned == 0 then
		Theme.label({
			Size = UDim2.new(1, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.Muted,
			TextWrapped = true,
			Text = "Win cosmetics at Shop and Gift spaces",
			Parent = buttons,
		}, 18)
		return
	end
	for index, item in inventory.Owned do
		local worn = inventory.Equipped[item.Slot] == item.Id
		local button = make("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(0, 120, 1, -6),
			BackgroundColor3 = if worn then Theme.Colors.Good else Theme.Colors.CardLight,
			Font = Theme.BodyFont,
			TextScaled = true,
			TextColor3 = if worn then Theme.Colors.Overlay else Theme.Colors.Text,
			Text = item.Name,
			Parent = buttons,
		}, { Theme.corner(12), Theme.padding(6), make("UITextSizeConstraint", { MaxTextSize = 20 }) })
		button.Activated:Connect(function()
			if worn then
				self.Send({ Kind = "Unequip", Slot = item.Slot })
			else
				self.Send({ Kind = "Equip", ItemId = item.Id })
			end
		end)
	end
end

-- New bank balance / wardrobe (e.g. after a shop purchase): rebuild the card's contents even
-- while the shop is covering it, without changing whether it's showing.
function LobbyPanel:setInventory(message)
	self.Inventory = message
	if self.LastMessage then
		self:render(self.LastMessage)
	end
end

local function settingRow(self, order: number, label: string, key: string, choices, selected, isHost: boolean)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, LobbyPanel.ROW),
		BackgroundTransparency = 1,
		Parent = self.SettingRows,
	})
	Theme.label({
		Size = UDim2.new(0.28, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = label,
		Parent = row,
	}, 22)
	local buttons = make("Frame", {
		Position = UDim2.fromScale(0.28, 0),
		Size = UDim2.fromScale(0.72, 1),
		BackgroundTransparency = 1,
		Parent = row,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, choice in choices do
		local isSelected = choice == selected
		local button = make("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(1 / #choices, -6, 1, 0),
			BackgroundColor3 = if isSelected then Theme.Colors.Accent else Theme.Colors.CardLight,
			BackgroundTransparency = if isHost or isSelected then 0 else 0.5,
			AutoButtonColor = isHost,
			Font = Theme.BodyFont,
			TextScaled = true,
			TextColor3 = if isSelected then Theme.Colors.Overlay else Theme.Colors.Text,
			Text = if key == "Board" then boardName(self.LastMessage, choice) else tostring(choice),
			Parent = buttons,
		}, { Theme.corner(12), Theme.padding(6), make("UITextSizeConstraint", { MaxTextSize = 24 }) })
		if isHost then
			button.Activated:Connect(function()
				self.Send({ Kind = "Setting", Key = key, Value = choice })
			end)
		end
	end
end

-- Fills the card from a waiting-room message (status line, settings, wardrobe, START).
function LobbyPanel:render(message)
	local isHost = message.HostId == Players.LocalPlayer.UserId
	self.LastMessage = message
	self.EndsAt = message.EndsAt
	self.Info.Text = ("%d / %d players  ·  bots fill empty seats  ·  %s  ·  bank: %d coins"):format(
		message.PlayerCount or 1,
		message.Seats or 4,
		if isHost then "you're the host" else ("host: %s"):format(message.HostName or "?"),
		self.Inventory and self.Inventory.BankCoins or 0
	)
	for _, child in self.SettingRows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local settings = message.Settings or {}
	local choices = message.Choices or {}
	local rows = 4 -- Mode, Rounds, Bots, wardrobe
	settingRow(self, 0, "Mode", "Mode", choices.Mode or {}, settings.Mode, isHost)
	if choices.Board and #choices.Board > 1 and settings.Mode == "Board" then
		settingRow(self, 1, "Board", "Board", choices.Board, settings.Board, isHost)
		rows += 1
	end
	settingRow(self, 2, "Rounds", "Rounds", choices.Rounds or {}, settings.Rounds, isHost)
	settingRow(self, 3, "Bots", "Difficulty", choices.Difficulty or {}, settings.Difficulty, isHost)
	wardrobeRow(self, 4)
	self.Rows = rows
	self:fit()
	self.StartButton.Visible = isHost
	self.WaitingNote.Visible = not isHost
end

function LobbyPanel:show(message)
	self:render(message)
	if not self.Root.Visible then
		self.Root.Visible = true
		Theme.pop(self.Root)
	end
end

function LobbyPanel:hide()
	self.Root.Visible = false
end

function LobbyPanel:update()
	if self.Root.Visible and self.EndsAt then
		self.Clock.Text = ("Starts in %ds"):format(math.max(0, math.ceil(self.EndsAt - Workspace:GetServerTimeNow())))
	end
end

return LobbyPanel
