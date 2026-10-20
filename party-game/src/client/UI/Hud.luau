--[[
	Hud
	Always-on pieces of the screen: round timer, minigame status line, the big centre
	banner (3-2-1 / GO! / FINISH!), the toast feed, and the lobby message pill.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local Hud = {}
Hud.__index = Hud

-- Phones get a smaller, shorter-lived feed so it doesn't cover the left side of the arena.
local TOUCH = game:GetService("UserInputService").TouchEnabled
local MAX_TOASTS = if TOUCH then 2 else 4
local TOAST_LIFETIME = if TOUCH then 2.5 else 3.5
local TOAST_HEIGHT = if TOUCH then 26 else 36
local TOAST_TEXT_SIZE = if TOUCH then 14 else 20
local TOAST_WIDTH = if TOUCH then 0.24 else 0.3
local TOAST_MIN_WIDTH = if TOUCH then 170 else 220
-- Phones on the board: the left column belongs to the standings and MAP, so the feed moves to
-- the top right, under Roblox's top bar, as a narrow column of two-line toasts.
local BOARD_TOAST_WIDTH = if TOUCH then 210 else 300
local BOARD_TOAST_HEIGHT = if TOUCH then 34 else 46
local BOARD_TOAST_TEXT_SIZE = if TOUCH then 12 else 17

function Hud.new(screen: ScreenGui)
	local self = setmetatable({}, Hud)

	-- Timer pill (top centre)
	self.TimerFrame = make("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(150, 52),
		BackgroundColor3 = Theme.Colors.Card,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(26), Theme.stroke(Theme.Colors.Accent, 3) })
	self.TimerLabel = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.TitleFont,
		Text = "0:00",
		Parent = self.TimerFrame,
	}, 40)

	-- Status line under the timer
	self.StatusLabel = Theme.label({
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0.8, 0, 0, 34),
		TextStrokeTransparency = 0.3,
		Text = "",
		Visible = false,
		Parent = screen,
	}, 30)

	-- Big centre banner
	self.Banner = Theme.label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.25),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		TextStrokeTransparency = 0,
		Text = "",
		Visible = false,
		Parent = screen,
	}, 140)
	self.BannerToken = 0

	-- Toast feed (left side, newest at the bottom)
	self.ToastList = make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromScale(TOAST_WIDTH, 0.4),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		make("UISizeConstraint", { MinSize = Vector2.new(TOAST_MIN_WIDTH, 0) }),
	})
	self.ToastCount = 0
	self.BoardToasts = false

	-- Lobby pill (bottom centre)
	self.LobbyFrame = make("Frame", {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.6, 0, 0, 50),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(25), Theme.make("UISizeConstraint", { MaxSize = Vector2.new(560, 50) }) })
	self.LobbyLabel = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.TitleFont,
		Parent = self.LobbyFrame,
	}, 26)

	self.TimerEndsAt = nil
	self.LobbyText = nil
	self.LobbyEndsAt = nil
	return self
end

-- Called every frame by the client main script.
function Hud:update()
	local now = Workspace:GetServerTimeNow()
	if self.TimerEndsAt then
		local remaining = self.TimerEndsAt - now
		self.TimerLabel.Text = Theme.formatTime(remaining)
		self.TimerLabel.TextColor3 = if remaining <= 10 then Theme.Colors.Hot else Theme.Colors.Text
	end
	if self.LobbyText then
		local text = self.LobbyText
		if self.LobbyEndsAt then
			text ..= ("  %d"):format(math.max(0, math.ceil(self.LobbyEndsAt - now)))
		end
		self.LobbyLabel.Text = text
	end
end

function Hud:setTimer(endsAt: number?)
	self.TimerEndsAt = endsAt
	self.TimerFrame.Visible = endsAt ~= nil
end

function Hud:setStatus(text: string?)
	self.StatusLabel.Text = text or ""
	self.StatusLabel.Visible = text ~= nil and text ~= ""
end

function Hud:setLobby(text: string?, endsAt: number?)
	self.LobbyText = text
	self.LobbyEndsAt = endsAt
	self.LobbyFrame.Visible = text ~= nil
end

-- Pops a big message in the middle, then fades it after `hold` seconds.
function Hud:showBanner(text: string, color: Color3?, hold: number?)
	self.BannerToken += 1
	local token = self.BannerToken
	local banner = self.Banner
	banner.Text = text
	banner.TextColor3 = color or Theme.Colors.Accent
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0
	banner.Visible = true
	Theme.pop(banner)
	task.delay(hold or 0.8, function()
		if self.BannerToken ~= token then
			return -- replaced by a newer banner
		end
		local fade = TweenService:Create(banner, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if self.BannerToken == token then
			banner.Visible = false
		end
	end)
end

-- Removes every toast at once (e.g. when the results card opens, so none peek out behind it).
function Hud:clearToasts()
	for _, child in self.ToastList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

-- Board layout for the feed (see BOARD_TOAST_*); minigames keep the left-side feed.
function Hud:setBoardToasts(on: boolean)
	if on == self.BoardToasts then
		return
	end
	self.BoardToasts = on
	self:clearToasts()
	local list = self.ToastList
	local constraint = list:FindFirstChildOfClass("UISizeConstraint")
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if on then
		-- Right side, below the standings strip and Roblox's player list: the left side holds
		-- the turn menu and the avatar.
		list.AnchorPoint = Vector2.new(1, 0)
		list.Position = UDim2.new(1, -10, 0.34, 0)
		list.Size = UDim2.fromOffset(BOARD_TOAST_WIDTH, MAX_TOASTS * (BOARD_TOAST_HEIGHT + 4))
		constraint.MinSize = Vector2.zero
		layout.Padding = UDim.new(0, 4)
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
	else
		list.AnchorPoint = Vector2.new(0, 0.5)
		list.Position = UDim2.new(0, 12, 0.5, 0)
		list.Size = UDim2.fromScale(TOAST_WIDTH, 0.4)
		constraint.MinSize = Vector2.new(TOAST_MIN_WIDTH, 0)
		layout.Padding = UDim.new(0, 6)
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
end

function Hud:toast(text: string)
	self.ToastCount += 1
	local board = self.BoardToasts
	local toast = make("Frame", {
		LayoutOrder = self.ToastCount,
		Size = UDim2.new(1, 0, 0, if board then BOARD_TOAST_HEIGHT else TOAST_HEIGHT),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.2,
		Parent = self.ToastList,
	}, { Theme.corner(10), Theme.padding(if board then 4 else 6) })
	local label
	if board then
		-- Two lines at a fixed, readable size; anything longer ends in "…".
		label = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.BodyFont,
			TextColor3 = Theme.Colors.Text,
			TextSize = BOARD_TOAST_TEXT_SIZE,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = Theme.shortWords(text),
			Parent = toast,
		})
	else
		label = Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = toast,
		}, TOAST_TEXT_SIZE)
	end

	-- Keep the feed short.
	local toasts = {}
	for _, child in self.ToastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - MAX_TOASTS do
		toasts[i]:Destroy()
	end

	task.delay(TOAST_LIFETIME, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

return Hud
