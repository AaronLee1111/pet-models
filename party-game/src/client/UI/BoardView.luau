--[[
	BoardView
	Everything the client shows during the board phase. Functional placeholder UI; the
	visual pass (style guide) comes later.

	  header      top centre, under Roblox's top bar: round, whose turn, dice / moves left
	  standings   left side: every seat's collectibles and coins, current turn highlighted
	  roll        big button bottom right, only on your turn (Space / ButtonA too)
	  prompt      bottom centre: fork / buy / shop choices sent to you by the server
	  camera      follows whoever's turn it is

	Only renders server state; every decision is validated on the server.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local BoardView = {}
BoardView.__index = BoardView

local ROLL_ACTION = "PartyBoardRoll"
local CAMERA_BIND = "PartyBoardCamera"
local CAMERA_OFFSET = Vector3.new(0, 42, 34)
-- Landscape phones need extra breathing room around the board so the near row and
-- world labels stay clear of the HUD and rounded screen edges. Desktop is unchanged.
local TOUCH_CAMERA_OFFSET = Vector3.new(0, 60, 50)
local MAP_OFFSET = Vector3.new(0, 115, 60) -- MAP view: high enough to see the whole board
local MAP_ACTION = "PartyBoardMap"

local myId = "player_" .. Players.LocalPlayer.UserId

-- A key that changes whenever the item list does (so buttons are only rebuilt then).
local function itemKeyOf(items): string
	local ids = {}
	for _, item in items do
		table.insert(ids, item.Id)
	end
	return table.concat(ids, ",")
end

-- send(payload) fires the input remote.
function BoardView.new(screen: ScreenGui, send: (any) -> ())
	local self = setmetatable({ Send = send, Visible = false }, BoardView)

	-- Header
	self.Header = make("Frame", {
		Name = "BoardHeader",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64), -- below Roblox's top bar
		Size = UDim2.fromOffset(460, 70),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(18), Theme.stroke(Theme.Colors.Accent, 3) })
	self.Title = Theme.label({
		Position = UDim2.fromScale(0.03, 0.05),
		Size = UDim2.fromScale(0.94, 0.5),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Parent = self.Header,
	}, 30)
	self.Subtitle = Theme.label({
		Position = UDim2.fromScale(0.03, 0.55),
		Size = UDim2.fromScale(0.94, 0.4),
		Parent = self.Header,
	}, 22)

	-- Standings (left side, below the top-left Roblox buttons)
	self.Standings = make("Frame", {
		Name = "BoardStandings",
		Position = UDim2.new(0, 12, 0, 150),
		Size = UDim2.fromOffset(230, 4 * 54 + 3 * 6),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self.Rows = {}

	-- Roll button
	self.RollButton = make("TextButton", {
		Name = "BoardRoll",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = Theme.Colors.Good,
		Font = Theme.TitleFont,
		Text = "",
		AutoButtonColor = true,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(75), Theme.stroke(Color3.new(1, 1, 1), 4) })
	self.RollLabel = Theme.label({
		Size = UDim2.fromScale(1, 0.6),
		Position = UDim2.fromScale(0, 0.12),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Overlay,
		Text = "ROLL!",
		Parent = self.RollButton,
	}, 44)
	self.RollClock = Theme.label({
		Size = UDim2.fromScale(1, 0.22),
		Position = UDim2.fromScale(0, 0.68),
		TextColor3 = Theme.Colors.Overlay,
		Parent = self.RollButton,
	}, 22)
	self.RollButton.Activated:Connect(function()
		self:roll()
	end)

	-- Item buttons (above the roll button, your turn only, before rolling)
	self.ItemBar = make("Frame", {
		Name = "BoardItems",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -186),
		Size = UDim2.fromOffset(520, 84),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.ItemKey = nil

	-- Prompt (bottom centre)
	self.Prompt = make("Frame", {
		Name = "BoardPrompt",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(620, 150),
		BackgroundColor3 = Theme.Colors.Card,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(18), Theme.stroke(Theme.Colors.Accent, 3), Theme.padding(10) })
	self.PromptText = Theme.label({
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Parent = self.Prompt,
	}, 30)
	self.PromptButtons = make("Frame", {
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		Parent = self.Prompt,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.PromptId = nil
	self.PromptEndsAt = nil

	-- MAP: inspect the whole board, the Crown, gates, traps and everyone's items
	self.MapButton = make("TextButton", {
		Name = "BoardMap",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(130, 56),
		BackgroundColor3 = Theme.Colors.Card,
		Font = Theme.TitleFont,
		TextScaled = true,
		TextColor3 = Theme.Colors.Accent,
		Text = "MAP",
		Visible = false,
		Parent = screen,
	}, { Theme.corner(14), Theme.stroke(Theme.Colors.Accent, 2), Theme.padding(8) })
	self.MapButton.Activated:Connect(function()
		self:toggleMap()
	end)
	self.MapPanel = make("ScrollingFrame", {
		Name = "BoardMapPanel",
		Position = UDim2.new(0, 12, 0, 150),
		Size = UDim2.fromOffset(330, 260),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = screen,
	}, {
		Theme.corner(14),
		Theme.padding(10),
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.MapOpen = false

	self.State = nil
	self.Layout = nil
	self.Focus = nil
	return self
end

-- Layout / state ------------------------------------------------------------------------------

function BoardView:setLayout(message)
	self.Layout = message
	local sum, count = Vector3.zero, 0
	for _, space in message.Spaces do
		sum += space.Position
		count += 1
	end
	self.Centre = if count > 0 then sum / count else Vector3.zero
end

local function seatLine(seat, plural: string): string
	return ("%d %s  ·  %d coins"):format(
		seat.Collectibles,
		if seat.Collectibles == 1 then string.sub(plural, 1, -2) else plural,
		seat.Coins
	)
end

function BoardView:setState(message)
	self.State = message
	if not self.Visible then
		return
	end
	if self.MapOpen then
		self:refreshMap()
	end

	-- Header
	local myTurn = message.TurnId == myId
	local who = if myTurn then "Your" else (message.TurnName and (message.TurnName .. "'s") or nil)
	self.Title.Text = ("%s %d / %d%s"):format(
		if message.Frenzy then "FINAL FRENZY · Round" else "Round",
		message.Round or 0,
		message.Rounds or 0,
		if who then "  ·  " .. who .. " turn" else ""
	)
	local sub = message.Text or ""
	if message.Stage == "OrderRoll" then
		self.Title.Text = ("Round %d / %d  ·  Turn order"):format(message.Round or 0, message.Rounds or 0)
		sub = if message.OrderPending and message.OrderPending[myId] then "Tap ROLL! Highest roll goes first" else (message.Text or "")
	elseif message.Stage == "Moving" and message.Remaining then
		sub = ("Rolled %d  ·  %d move%s left"):format(message.Roll or 0, message.Remaining, if message.Remaining == 1 then "" else "s")
	elseif message.Stage == "Roll" and myTurn then
		sub = if (message.Dice or 1) > 1
			then ("Tap ROLL to roll %d dice!"):format(message.Dice)
			else "Use an item, or tap ROLL to roll the die!"
	end
	self.Subtitle.Text = sub

	-- Standings rows (turn order)
	for _, row in self.Rows do
		row:Destroy()
	end
	self.Rows = {}
	for _, seat in message.Seats do
		local isTurn = seat.Id == message.TurnId
		local isMe = seat.Id == myId
		local row = make("Frame", {
			LayoutOrder = seat.Order,
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = if isMe then Theme.Colors.CardLight else Theme.Colors.Card,
			BackgroundTransparency = 0.1,
			Parent = self.Standings,
		}, { Theme.corner(12) })
		if isTurn then
			Theme.stroke(Theme.Colors.Accent, 3).Parent = row
		end
		Theme.label({
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -20, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.TitleFont,
			Text = (if isTurn then "▶ " else "") .. (if isMe then "YOU" else seat.Name) .. (if seat.IsBot then " (bot)" else ""),
			Parent = row,
		}, 22)
		local line = seatLine(seat, message.CollectiblePlural or "Crowns")
		if seat.OrderRolls and #seat.OrderRolls > 0 then
			line = "Rolled " .. table.concat(seat.OrderRolls, ", then ")
		else
			line ..= ("  ·  %d item%s"):format(#(seat.Items or {}), if #(seat.Items or {}) == 1 then "" else "s")
			if seat.Shield then
				line ..= "  ·  shield"
			end
			if seat.Underdog then
				line ..= "  ·  underdog"
			end
		end
		Theme.label({
			Position = UDim2.fromOffset(10, 30),
			Size = UDim2.new(1, -20, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.Accent,
			Text = line,
			Parent = row,
		}, 18)
		table.insert(self.Rows, row)
	end

	-- Item buttons: your turn, before rolling, no item used yet.
	local mySeat
	for _, seat in message.Seats do
		if seat.Id == myId then
			mySeat = seat
		end
	end
	local items = mySeat and mySeat.Items or {}
	local showItems = myTurn and message.Stage == "Roll" and not message.ItemUsed and #items > 0
	local itemKey = if showItems then itemKeyOf(items) else nil
	if itemKey ~= self.ItemKey then
		self.ItemKey = itemKey
		for _, child in self.ItemBar:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for slot, item in items do
			local button = make("TextButton", {
				LayoutOrder = slot,
				Size = UDim2.fromOffset(160, 84), -- >= 44pt tall after the phone HUD scale (0.55)
				BackgroundColor3 = Theme.Colors.Cool,
				Font = Theme.BodyFont,
				TextScaled = true,
				TextColor3 = Theme.Colors.Overlay,
				Text = item.Name,
				Parent = self.ItemBar,
			}, { Theme.corner(14), Theme.padding(6), make("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 10 }) })
			button.Activated:Connect(function()
				self.ItemBar.Visible = false
				self.Send({ Kind = "UseItem", Slot = slot })
			end)
		end
	end
	self.ItemBar.Visible = showItems

	-- Roll button: on your turn (or when rolling for turn order), while waiting for the roll.
	local canRoll = (myTurn and message.Stage == "Roll")
		or (message.Stage == "OrderRoll" and message.OrderPending ~= nil and message.OrderPending[myId] == true)
	if canRoll and not self.RollButton.Visible then
		Theme.pop(self.RollButton)
		ContextActionService:BindAction(ROLL_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self:roll()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	elseif not canRoll then
		ContextActionService:UnbindAction(ROLL_ACTION)
	end
	self.RollButton.Visible = canRoll
end

function BoardView:roll()
	if self.RollButton.Visible then
		self.RollButton.Visible = false
		ContextActionService:UnbindAction(ROLL_ACTION)
		self.Send({ Kind = "Roll" })
	end
end

-- Map ---------------------------------------------------------------------------------------------

local function mapLine(self, order: number, text: string, color: Color3?, swatch: Color3?)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = self.MapPanel,
	})
	if swatch then
		make("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromOffset(0, 3),
			BackgroundColor3 = swatch,
			Parent = row,
		}, { Theme.corner(4) })
	end
	Theme.label({
		Position = UDim2.fromOffset(if swatch then 26 else 0, 0),
		Size = UDim2.new(1, if swatch then -26 else 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Theme.Colors.Text,
		Text = text,
		Parent = row,
	}, 20)
end

-- Rebuilds the MAP panel from the latest state + layout.
function BoardView:refreshMap()
	for _, child in self.MapPanel:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local state, layout = self.State, self.Layout
	if not state then
		return
	end
	local order = 0
	local function line(text, color, swatch)
		order += 1
		mapLine(self, order, text, color, swatch)
	end
	line("MAP" .. (if layout and layout.Name then " · " .. layout.Name else ""), Theme.Colors.Accent)
	line(("%s: space %s · %d coins"):format(state.CollectibleName or "Crown", tostring(state.CollectibleSpace), state.CollectiblePrice or 0), Theme.Colors.Accent)
	for _, gate in state.Gates or {} do
		line(("Gate %s: %s%s"):format(gate.Id, if gate.Open then "open" else "CLOSED", if gate.Open and gate.Toll > 0 then (" · toll %d"):format(gate.Toll) else ""))
	end
	for _, trap in state.Traps or {} do
		line(("Trap on space %d (%s)"):format(trap.SpaceId, trap.Owner), Theme.Colors.Hot)
	end
	line("Players", Theme.Colors.Accent)
	for _, seat in state.Seats do
		local names = {}
		for _, item in seat.Items or {} do
			table.insert(names, item.Name)
		end
		line(("%s: %d %s, %d coins"):format(if seat.Id == myId then "You" else seat.Name, seat.Collectibles, state.CollectiblePlural or "Crowns", seat.Coins))
		line("   " .. (if #names > 0 then table.concat(names, ", ") else "no items") .. (if seat.Shield then " · shield up" else ""), Theme.Colors.Muted)
	end
	if layout and layout.Legend then
		line("Spaces", Theme.Colors.Accent)
		local legend = table.clone(layout.Legend)
		table.sort(legend, function(a, b)
			return a.Name < b.Name
		end)
		for _, entry in legend do
			line(entry.Name .. (if entry.Short ~= "" then (" (%s)"):format(entry.Short) else ""), nil, entry.Color)
		end
	end
end

function BoardView:toggleMap(open: boolean?)
	if open == nil then
		open = not self.MapOpen
	end
	self.MapOpen = open and self.Visible
	self.MapPanel.Visible = self.MapOpen
	self.Standings.Visible = self.Visible and not self.MapOpen and self.Header.Visible
	self.MapButton.Text = if self.MapOpen then "CLOSE" else "MAP"
	self.Focus = nil
	if self.MapOpen then
		self:refreshMap()
	end
end

-- Prompt ------------------------------------------------------------------------------------------

function BoardView:showPrompt(message)
	for _, child in self.PromptButtons:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	self.PromptId = message.PromptId
	self.PromptEndsAt = message.EndsAt
	if not message.PromptId then
		self.Prompt.Visible = false
		return
	end
	self.PromptText.Text = message.Prompt
	local count = #message.Options
	for index, option in message.Options do
		local button = make("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -10, 1, 0),
			BackgroundColor3 = if index == count and count > 1 then Theme.Colors.CardLight else Theme.Colors.Cool,
			Font = Theme.BodyFont,
			TextScaled = true,
			TextColor3 = if index == count and count > 1 then Theme.Colors.Text else Theme.Colors.Overlay,
			Text = option,
			Parent = self.PromptButtons,
		}, {
			Theme.corner(14),
			Theme.padding(8),
			make("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 10 }),
		})
		button.Activated:Connect(function()
			if self.PromptId == message.PromptId then
				self.Send({ Kind = "Choice", PromptId = message.PromptId, Index = index })
				self.PromptId = nil
				self.Prompt.Visible = false
			end
		end)
	end
	self.Prompt.Visible = true
	Theme.pop(self.Prompt)
end

-- Visibility + camera -----------------------------------------------------------------------------

local function turnFocus(self): Vector3?
	local state = self.State
	if not state then
		return self.Centre
	end
	for _, seat in state.Seats do
		if seat.Id == state.TurnId then
			local character = seat.Character
			local root = character and character.Parent and character:FindFirstChild("HumanoidRootPart")
			if root then
				return root.Position
			end
		end
	end
	return self.Centre
end

function BoardView:show()
	if self.Visible then
		return
	end
	self.Visible = true
	self.Header.Visible = true
	self.Standings.Visible = true
	self.MapButton.Visible = true
	ContextActionService:BindAction(MAP_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:toggleMap()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonY)
	self.Focus = nil
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local goal = if self.MapOpen then self.Centre else turnFocus(self)
		if not goal then
			return
		end
		self.Focus = if self.Focus then self.Focus:Lerp(goal, 1 - math.exp(-4 * dt)) else goal
		camera.CameraType = Enum.CameraType.Scriptable
		local playOffset = if UserInputService.TouchEnabled then TOUCH_CAMERA_OFFSET else CAMERA_OFFSET
		camera.CFrame = CFrame.lookAt(self.Focus + (if self.MapOpen then MAP_OFFSET else playOffset), self.Focus)
		-- Your piece is teleported around; if it tips over, stand it back up.
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local humanoidState = humanoid and humanoid:GetState()
		if humanoidState == Enum.HumanoidStateType.FallingDown or humanoidState == Enum.HumanoidStateType.Ragdoll then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
	if self.State then
		self:setState(self.State)
	end
end

function BoardView:hide()
	if not self.Visible then
		return
	end
	self.Visible = false
	self.Header.Visible = false
	self.Standings.Visible = false
	self.MapButton.Visible = false
	self:toggleMap(false)
	ContextActionService:UnbindAction(MAP_ACTION)
	self.RollButton.Visible = false
	self.ItemBar.Visible = false
	self.ItemKey = nil
	self.Prompt.Visible = false
	ContextActionService:UnbindAction(ROLL_ACTION)
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Keeps the board camera but hides the header, standings, roll and prompt (final standings card).
function BoardView:hidePanels()
	self.Header.Visible = false
	self.Standings.Visible = false
	self.MapButton.Visible = false
	self:toggleMap(false)
	ContextActionService:UnbindAction(MAP_ACTION)
	self.RollButton.Visible = false
	self.ItemBar.Visible = false
	self.ItemKey = nil
	self.Prompt.Visible = false
	ContextActionService:UnbindAction(ROLL_ACTION)
end

-- Per frame: countdown on the roll button.
function BoardView:update()
	if self.RollButton.Visible and self.State and self.State.RollEndsAt then
		self.RollClock.Text = ("%ds"):format(math.max(0, math.ceil(self.State.RollEndsAt - Workspace:GetServerTimeNow())))
	end
end

return BoardView
