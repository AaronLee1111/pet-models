--[[
	LobbyPanel
	Waiting-room card (bottom centre, so the lobby stays visible): countdown, players
	seated, and the match settings. The host can change settings and start early; everyone
	else just sees them. Below that, a wardrobe row: tap a cosmetic you own to wear it, tap
	again to take it off. The server checks every change.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local LobbyPanel = {}
LobbyPanel.__index = LobbyPanel

function LobbyPanel.new(screen: ScreenGui, send: (any) -> ())
	local self = setmetatable({ Send = send, EndsAt = nil, Inventory = nil, LastMessage = nil }, LobbyPanel)

	self.Root = make("Frame", {
		Name = "WaitingRoom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(640, 316),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(20), Theme.stroke(Theme.Colors.Accent, 3), Theme.padding(12) })

	self.Title = Theme.label({
		Size = UDim2.new(0.62, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Text = "PARTY GAMES",
		Parent = self.Root,
	}, 32)
	self.Clock = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.38, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.TitleFont,
		Parent = self.Root,
	}, 30)
	self.Info = Theme.label({
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Muted,
		Parent = self.Root,
	}, 20)

	self.SettingRows = make("Frame", {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(0.72, 0, 1, -68),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

	self.StartButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.26, 0, 1, -68),
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
	return self
end

-- Owned cosmetics as toggles; the server confirms with a fresh Inventory message.
local function wardrobeRow(self, order: number)
	local inventory = self.Inventory or { Owned = {}, Equipped = {} }
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = self.SettingRows,
	})
	-- Opens the permanent Cosmetics Shop (bank coins).
	local shopButton = make("TextButton", {
		Name = "ShopButton",
		Size = UDim2.new(0.26, 0, 1, 0),
		BackgroundColor3 = Theme.Colors.Accent,
		Font = Theme.TitleFont,
		TextScaled = true,
		TextColor3 = Theme.Colors.Overlay,
		Text = "SHOP",
		Parent = row,
	}, { Theme.corner(12), Theme.padding(8), make("UITextSizeConstraint", { MaxTextSize = 24 }) })
	shopButton.Activated:Connect(function()
		if self.OnShop then
			self.OnShop()
		end
	end)
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

function LobbyPanel:setInventory(message)
	self.Inventory = message
	if self.Root.Visible and self.LastMessage then
		self:show(self.LastMessage)
	end
end

local function settingRow(self, order: number, label: string, key: string, choices, selected, isHost: boolean)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 52),
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
			Text = tostring(choice),
			Parent = buttons,
		}, { Theme.corner(12), Theme.padding(6), make("UITextSizeConstraint", { MaxTextSize = 24 }) })
		if isHost then
			button.Activated:Connect(function()
				self.Send({ Kind = "Setting", Key = key, Value = choice })
			end)
		end
	end
end

function LobbyPanel:show(message)
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
	settingRow(self, 0, "Mode", "Mode", choices.Mode or {}, settings.Mode, isHost)
	settingRow(self, 1, "Rounds", "Rounds", choices.Rounds or {}, settings.Rounds, isHost)
	settingRow(self, 2, "Bots", "Difficulty", choices.Difficulty or {}, settings.Difficulty, isHost)
	if choices.Board and #choices.Board > 1 and settings.Mode == "Board" then
		settingRow(self, 3, "Board", "Board", choices.Board, settings.Board, isHost)
	end
	wardrobeRow(self, 4)
	self.StartButton.Visible = isHost
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
		self.Clock.Text = ("Starts in %d"):format(math.max(0, math.ceil(self.EndsAt - Workspace:GetServerTimeNow())))
	end
end

return LobbyPanel
