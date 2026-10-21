--[[
	BoardView
	Everything the client shows during the board phase, in the board-turn format from the
	style guide (UI & Visual Style.md):

	  1. Turn start: "Aaron, start!" banner (TurnStartBanner) across the upper area, the active
	     avatar large lower-left (ActivePlayerPortrait), the close turn camera on their piece.
	  2. Active turn: four-player standings across the top (PlayerStandingsStrip), the
	     ROLL / ITEMS / MAP menu on the left (TurnMenu, your turn only), the avatar lower-left,
	     "Round 2 / 5 · Turn 3 / 4" at the bottom (TurnProgress), and with ROLL picked a
	     physical die above your character (DicePrompt). Rolling throws it (BoardDice).
	  3. Prompts (fork / shop / Crown) stay the bottom-centre card; MAP is the whole-board view.

	Only renders server state; every decision is validated on the server. Instance names the
	tests and the onboarding pointer use: BoardRoll (ROLL row), BoardItems (item list),
	BoardMap (MAP row), BoardHeader (progress pill), BoardStandings (strip), BoardPrompt.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ActivePlayerPortrait = require(script.Parent.ActivePlayerPortrait)
local BoardDice = require(script.Parent.BoardDice)
local BoardIntro = require(script.Parent.BoardIntro)
local BoardMotion = require(script.Parent.BoardMotion)
local DicePrompt = require(script.Parent.DicePrompt)
local PlayerStandingsStrip = require(script.Parent.PlayerStandingsStrip)
local Theme = require(script.Parent.Theme)
local TurnMenu = require(script.Parent.TurnMenu)
local TurnProgress = require(script.Parent.TurnProgress)
local TurnStartBanner = require(script.Parent.TurnStartBanner)
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
-- Diorama boards (Presentation = "Diorama", Sunny Loop v2): a closer turn camera on the active
-- piece and the route just ahead; MAP stays the whole-board view. Phones sit a little farther
-- back so the HUD columns never cover the neighbouring spaces.
local DIORAMA_OFFSET = Vector3.new(0, 20, 23)
local DIORAMA_TOUCH_OFFSET = Vector3.new(0, 23, 27)
local DIORAMA_LOOKAHEAD = 0.35 -- how far the focus leans toward the next space
local DIORAMA_FORK_ZOOM = 1.45 -- pull back at a fork so both routes are in view
-- While a prompt card covers the bottom of the screen, aim a little south of the subject so it
-- sits in the visible upper part instead of behind the card.
local DIORAMA_PROMPT_SHIFT = Vector3.new(0, 0, 9)
local DIORAMA_DECIDE_ZOOM = 1.2 -- shops, Crown offers and other choices: a little more context
local MAP_ACTION = "PartyBoardMap"

local myId = "player_" .. Players.LocalPlayer.UserId

local TOUCH = UserInputService.TouchEnabled
local NAME_LENGTH = 14 -- longer names end in "…" in prompts, toasts and the MAP
local HEADER_NAME_LENGTH = 10 -- the status line is shorter still
local MAP_TEXT_SIZE = if TOUCH then 17 else 20
-- Roblox's own UI on desktop: the legacy chat window (top-left, ~30% wide, ~25% tall) and the
-- player list (top-right). The standings and the menu stay out of both.
local CHAT_WIDTH, CHAT_HEIGHT, PLAYER_LIST_WIDTH = 0.3, 0.25, 262

-- send(payload) fires the input remote.
function BoardView.new(screen: ScreenGui, send: (any) -> (), playerGui: PlayerGui?)
	local self = setmetatable({ Send = send, Visible = false, PanelsHidden = false }, BoardView)

	self.Progress = TurnProgress.new(screen)
	self.Header = self.Progress.Root
	self.Title = self.Progress.Title
	self.Subtitle = self.Progress.Subtitle

	self.Strip = PlayerStandingsStrip.new(screen)
	self.Standings = self.Strip.Root

	self.Banner = TurnStartBanner.new(screen)
	self.Portrait = ActivePlayerPortrait.new(screen)

	self.Menu = TurnMenu.new(screen, {
		Roll = function()
			self:roll()
		end,
		Map = function()
			self:toggleMap()
		end,
		UseItem = function(slot)
			self.Send({ Kind = "UseItem", Slot = slot })
		end,
		Changed = function()
			self:refresh()
		end,
	})
	self.RollButton = self.Menu.Rows.Roll.Button
	self.MapButton = self.Menu.Rows.Map.Button
	self.ItemsButton = self.Menu.Rows.Items.Button
	self.ItemBar = self.Menu.ItemPanel
	self.ItemsOffered = false

	self.DicePrompt = DicePrompt.new(playerGui or Players.LocalPlayer:WaitForChild("PlayerGui"), function()
		self:roll()
	end)

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
	self.MapPanel = Theme.glass(make("ScrollingFrame", {
		Name = "BoardMapPanel",
		Size = UDim2.fromOffset(330, 260),
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = screen,
	}), 14)
	Theme.padding(10).Parent = self.MapPanel
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.MapPanel })
	self.MapScale = make("UIScale", { Parent = self.MapPanel })
	self.MapOpen = false

	self.State = nil
	self.Layout = nil
	self.Focus = nil
	self.Zoom = 1
	self.Dice = BoardDice.new()
	self.Opening = BoardIntro.new(screen, send)

	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:layout()
	end)
	self:layout()
	return self
end

-- Places every panel from the viewport size, Roblox's top bar and its chat / player list.
-- Design sizes are for a 720 px tall screen; phones scale down, never below a 44 px tap row.
function BoardView:layout()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local w, h = viewport.X, viewport.Y
	local top = GuiService:GetGuiInset().Y
	local s = math.clamp(h / 720, 0.55, 1)

	-- Standings: centred in the free strip of the top edge (between the chat window and the
	-- player list on desktop). Chips are designed 220 px wide; a narrow gap scales the whole
	-- strip down (text included) rather than squeezing names, never below 0.6.
	local left = if TOUCH then 12 else math.max(12, w * CHAT_WIDTH + 8)
	local right = if TOUCH then w - 12 else w - PLAYER_LIST_WIDTH
	local design = 4 * 220 + 3 * PlayerStandingsStrip.GAP
	local stripScale = math.clamp(math.min(s, (right - left) / design), 0.6, 1)
	local chipWidth = math.clamp(((right - left) / stripScale - 3 * PlayerStandingsStrip.GAP) / 4, 150, 240)
	self.Strip.Scale.Scale = stripScale
	self.Strip:setChipWidth(chipWidth)
	local stripTop = top + 6
	self.Standings.Position = UDim2.fromOffset((left + right) / 2, stripTop)
	local stripBottom = stripTop + (PlayerStandingsStrip.CHIP_HEIGHT + 14) * stripScale

	-- Banner: the upper gameplay area, never under the top bar.
	self.Banner.Root.Position = UDim2.fromOffset(0, top + math.max(8, h * 0.06))
	self.Banner.Root.Size = UDim2.new(1, 0, 0, TurnStartBanner.HEIGHT * s)
	self.Banner.Scale.Scale = s

	-- Menu: left edge, below the standings (and, on desktop, below the chat window).
	local menuScale = math.max(s, 0.55)
	local menuTop = if TOUCH then stripBottom + 6 else math.max(stripBottom + 10, top + h * CHAT_HEIGHT + 12)
	self.Menu.Scale.Scale = menuScale
	self.Menu.Root:SetAttribute("HudScale", menuScale) -- Theme.pop animates back to this
	self.Menu.Root.Position = UDim2.fromOffset(30 * menuScale + 8, menuTop)
	local menuBottom = menuTop + (3 * TurnMenu.ROW.Y + 2 * TurnMenu.GAP) * menuScale

	-- MAP panel under the CLOSE row.
	local mapScale = math.max(s, 0.75)
	self.MapScale.Scale = mapScale
	self.MapPanel.Position = UDim2.fromOffset(12, menuTop + (TurnMenu.ROW.Y + TurnMenu.GAP) * menuScale)
	self.MapPanel.Size = UDim2.fromOffset(330, math.min(260, (h - 12 - (menuTop + (TurnMenu.ROW.Y + TurnMenu.GAP) * menuScale)) / mapScale))

	-- Avatar: lower-left, the big (turn-start) version at most ~42% of the screen height; the
	-- normal one only when it fits under the menu.
	local portraitScale = math.min(s, h * 0.42 / ActivePlayerPortrait.BIG.Y)
	self.Portrait.Scale.Scale = portraitScale
	self.Portrait.Root.Position = UDim2.fromOffset(10, h - 6)
	self.PortraitFits = h - 6 - menuBottom >= ActivePlayerPortrait.NORMAL.Y * portraitScale * 0.75

	-- Progress: bottom centre, lifted above the prompt card while one is up.
	local progressScale = math.max(s, 0.6)
	self.Progress.Scale.Scale = progressScale
	local promptScale = self.Prompt:GetAttribute("HudScale") or 1
	local bottom = if self.Prompt.Visible then h - (20 + 150) * promptScale - 8 else h - 10
	self.Header.Position = UDim2.fromOffset(w / 2, bottom)
end

-- Layout / state ------------------------------------------------------------------------------

function BoardView:setLayout(message)
	self.Layout = message
	self.SpaceById = {}
	for _, space in message.Spaces do
		self.SpaceById[space.Id] = space
	end
	local sum, count = Vector3.zero, 0
	for _, space in message.Spaces do
		sum += space.Position
		count += 1
	end
	self.Centre = if count > 0 then sum / count else Vector3.zero
end

local function seatById(state, id)
	for _, seat in (state and state.Seats) or {} do
		if seat.Id == id then
			return seat
		end
	end
	return nil
end

function BoardView:isDiorama(): boolean
	return self.Layout ~= nil and self.Layout.Presentation == "Diorama"
end

function BoardView:setState(message)
	self.State = message
	if not self.Visible then
		return
	end
	-- Thrown dice: everyone sees the active piece throw; the roller's own throw already started.
	if message.Stage == "Moving" and message.RollId and message.DiceFaces then
		local seat = seatById(message, message.TurnId)
		self.Dice:reveal(seat and seat.Character, message.DiceFaces, message.RollId, seat ~= nil and seat.IsBot)
	end
	if self.MapOpen then
		self:refreshMap()
	end

	-- A new turn: the "start!" banner first, then the turn controls.
	if message.Stage == "Roll" and message.TurnId then
		local key = ("%s:%s"):format(tostring(message.Round), message.TurnId)
		if key ~= self.IntroKey then
			self.IntroKey = key
			self:playIntro(seatById(message, message.TurnId))
		end
	end

	-- Progress pill: round and turn, and one short status line.
	local myTurn = message.TurnId == myId
	local turnSeat = seatById(message, message.TurnId)
	self.Title.Text = ("%s %d / %d%s"):format(
		if message.Frenzy then "FINAL FRENZY · Round" else "Round",
		message.Round or 0,
		message.Rounds or 0,
		if turnSeat then ("  ·  Turn %d / %d"):format(turnSeat.Order, #message.Seats) else ""
	)
	local sub = message.Text or ""
	if message.Stage == "OrderRoll" then
		self.Title.Text = ("Round %d / %d  ·  Turn order"):format(message.Round or 0, message.Rounds or 0)
		sub = if message.OrderPending and message.OrderPending[myId] then "Roll! Highest roll goes first" else (message.Text or "")
	elseif message.Stage == "Moving" and message.Remaining then
		sub = ("Rolled %d  ·  %d move%s left"):format(message.Roll or 0, message.Remaining, if message.Remaining == 1 then "" else "s")
	elseif message.Stage == "Roll" and myTurn then
		sub = if (message.Dice or 1) > 1 then ("Your turn  ·  rolling %d dice"):format(message.Dice) else "Your turn"
	end
	if message.Bridge and message.Stage ~= "RotationWarning" and message.Stage ~= "Rotating" then
		sub ..= " · " .. message.Bridge.Alignment .. " → " .. message.Bridge.NextAlignment
	end
	if message.Bridge and message.Stage == "Roll" then
		for _, seat in message.Seats do
			local dock = seat.Zone and message.Bridge.Docks[seat.Zone]
			if seat.Id == message.TurnId and dock and not dock.Open then
				sub = "Exit CLOSED · keep looping · " .. message.Bridge.Alignment .. " → " .. message.Bridge.NextAlignment
			end
		end
	end
	self.Subtitle.Text = Theme.shortWords(sub, HEADER_NAME_LENGTH + 2)

	self.Strip:render(message, myId)
	self:refresh()
end

-- Turn-start handoff: banner + big avatar; the controls appear when the banner leaves.
function BoardView:playIntro(seat)
	if not seat then
		return
	end
	local name = if seat.Id == myId then Players.LocalPlayer.DisplayName else seat.Name
	self.IntroActive = true
	self.IntroSeat = seat
	self.Menu:closeItems()
	self.Menu:select("Roll")
	self.Banner:play(Theme.shortWords(name, 12) .. ", start!", seat.IsBot, function()
		self.IntroActive = false
		self:refresh()
	end)
	self:refresh()
end

-- What's on screen right now, from the latest state and the local flags (intro, MAP, items).
function BoardView:refresh()
	local state = self.State
	if not (self.Visible and state) then
		return
	end
	-- The board-opening intro owns the screen: no HUD, no input until it ends.
	local panels = not self.PanelsHidden and not self.Opening.Active and state.Stage ~= "Intro"
	local intro = self.IntroActive and panels
	local myTurn = state.TurnId == myId
	local stage = state.Stage
	local mySeat = seatById(state, myId)
	local items = mySeat and mySeat.Items or {}
	local canRoll = (myTurn and stage == "Roll")
		or (stage == "OrderRoll" and state.OrderPending ~= nil and state.OrderPending[myId] == true)
	local prompting = self.Prompt.Visible

	self.Standings.Visible = panels and not intro
	self.Header.Visible = panels and not intro

	-- Menu: your roll (turn or turn order), or the MAP's CLOSE row.
	local itemsUsable = myTurn and stage == "Roll" and not state.ItemUsed and #items > 0
	local menuShown = panels and not intro and not prompting and (canRoll or self.MapOpen)
	self.ItemsOffered = menuShown and canRoll and itemsUsable
	self.Menu:setItems(items)
	self.Menu:setRows({
		Roll = { Visible = canRoll and not self.MapOpen },
		Items = {
			Visible = canRoll and not self.MapOpen,
			Enabled = itemsUsable,
			Reason = if stage == "OrderRoll" then "Items unlock on your turn"
				elseif state.ItemUsed then "One item per turn"
				else "No items yet",
			Note = if #items > 0 then ("%d held"):format(#items) else "",
		},
		Map = {
			Visible = true,
			Label = if self.MapOpen then "CLOSE" else "MAP",
			Note = if self.MapOpen then "Back to the turn" else "Whole board",
		},
	})
	if not itemsUsable then
		self.Menu:closeItems()
	end
	if menuShown and not self.Menu.Root.Visible then
		self.Menu.Root.Visible = true
		self.Menu:select(if self.MapOpen then "Map" else "Roll")
		self.Menu:bind()
		Theme.pop(self.Menu.Root)
	elseif not menuShown and self.Menu.Root.Visible then
		self.Menu.Root.Visible = false
		self.Menu:closeItems()
		self.Menu:unbind()
	end
	self.RollButton.Visible = menuShown and canRoll and not self.MapOpen

	-- Space rolls while ROLL is the picked row (Enter / gamepad A activate any row).
	local rollKey = self.RollButton.Visible and self.Menu.Selected == "Roll" and not self.Menu.ItemsOpen
	if rollKey and not self.RollBound then
		ContextActionService:BindAction(ROLL_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self:roll()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Space)
	elseif not rollKey and self.RollBound then
		ContextActionService:UnbindAction(ROLL_ACTION)
	end
	self.RollBound = rollKey

	-- Avatar: big during the banner, normal on your own turn, gone while moving or on the MAP.
	local turnSeat = seatById(state, state.TurnId)
	if intro and self.IntroSeat then
		self.Portrait:show(self.IntroSeat.Character, "Big")
	elseif panels and myTurn and stage == "Roll" and not self.MapOpen and self.PortraitFits then
		self.Portrait:show(turnSeat and turnSeat.Character, "Normal")
	else
		self.Portrait:hide()
	end

	-- The physical die above your character while ROLL is picked.
	if rollKey and myTurn and stage == "Roll" and not prompting then
		local hint = if UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad")
			then "Press A to roll"
			elseif TOUCH then "Tap the die"
			else "Press Space or click the die"
		self.DicePrompt:show(Players.LocalPlayer.Character, hint)
	else
		self.DicePrompt:hide()
	end
	self:layout()
end

function BoardView:roll()
	if not self.RollButton.Visible then
		return
	end
	self.RollButton.Visible = false
	self.DicePrompt:hide()
	if self.RollBound then
		ContextActionService:UnbindAction(ROLL_ACTION)
		self.RollBound = false
	end
	local state = self.State
	-- Your own turn: the throw starts on the press, the number lands when the server's roll
	-- arrives. (Turn-order rolls stay instant.)
	if state and state.Stage == "Roll" and state.TurnId == myId then
		self.Dice:throw(Players.LocalPlayer.Character, state.Dice or 1)
		self.Portrait:hide()
	end
	self.Send({ Kind = "Roll" })
end

-- Map ---------------------------------------------------------------------------------------------

local function mapLine(self, order: number, text: string, color: Color3?, swatch: Color3?)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y, -- long lines wrap instead of shrinking
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
	make("TextLabel", {
		Position = UDim2.fromOffset(if swatch then 26 else 0, 0),
		Size = UDim2.new(1, if swatch then -26 else 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = MAP_TEXT_SIZE,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = color or Theme.Colors.Text,
		Text = Theme.shortWords(text, NAME_LENGTH),
		Parent = row,
	})
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
	if state.Bridge then
  line("Bridge " .. state.Bridge.Alignment .. " · next " .. state.Bridge.NextAlignment,Theme.Colors.Accent)
  line("Rotates after round " .. state.Bridge.NextRound .. " · Moon Dial ready round " .. state.Bridge.DialReadyRound)
  for _,dock in state.Bridge.Docks do line(dock.Name .. ": " .. (if dock.Open then "OPEN" else "EXIT CLOSED · local loop")) end
 end
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
	self.Focus = nil
	if self.MapOpen then
		self.Menu:select("Map")
		self:refreshMap()
	else
		self.Menu:select("Roll")
	end
	self:refresh()
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
	self.PromptMessage = message -- Kind / Routes / Price: read by the first-action guidance
	if not message.PromptId then
		self.Prompt.Visible = false
		self:refresh()
		return
	end
	self.PromptText.Text = Theme.shortWords(message.Prompt, NAME_LENGTH)
	local count = #message.Options
	for index, option in message.Options do
		local button = make("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -10, 1, 0),
			BackgroundColor3 = if index == count and count > 1 then Theme.Colors.CardLight else Theme.Colors.Cool,
			Font = Theme.BodyFont,
			TextScaled = true,
			TextColor3 = if index == count and count > 1 then Theme.Colors.Text else Theme.Colors.Overlay,
			Text = Theme.shortWords(option, NAME_LENGTH),
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
				self:refresh()
			end
		end)
	end
	self.Prompt.Visible = true
	Theme.pop(self.Prompt)
	self:refresh()
end

-- Visibility + camera -----------------------------------------------------------------------------

-- Diorama turn camera: where to look and how far back. Follows the active piece, leaning
-- toward the next space; pulls back at forks (both routes) and while someone is choosing.
local function dioramaShot(self): (Vector3?, number)
	local state = self.State
	if not state then
		return self.Centre, 1
	end
	if state.Stage == "OrderRoll" or state.Stage == "OrderDone" then
		local sum, count = Vector3.zero, 0
		for _, seat in state.Seats do
			local root = seat.Character and seat.Character.Parent and seat.Character:FindFirstChild("HumanoidRootPart")
			if root then
				sum += root.Position
				count += 1
			end
		end
		return if count > 0 then sum / count else self.Centre, 1.15
	end
	local seat = seatById(state, state.TurnId)
	local space = seat and self.SpaceById and self.SpaceById[seat.SpaceId]
	local root = seat and seat.Character and seat.Character.Parent and seat.Character:FindFirstChild("HumanoidRootPart")
	local here = if root then root.Position elseif space then space.Position else self.Centre
	if not space or not here then
		return here, 1
	end
	local nextIds = space.Next or {}
	if state.Stage == "Deciding" and #nextIds >= 2 then
		local sum, count = space.Position, 1
		for _, id in nextIds do
			local first = self.SpaceById[id]
			if first then
				sum += first.Position
				count += 1
				local second = first.Next and self.SpaceById[first.Next[1]]
				if second then
					sum += second.Position
					count += 1
				end
			end
		end
		return sum / count + DIORAMA_PROMPT_SHIFT, DIORAMA_FORK_ZOOM
	end
	local ahead = nextIds[1] and self.SpaceById[nextIds[1]]
	local focus = if ahead then here:Lerp(ahead.Position, DIORAMA_LOOKAHEAD) else here
	if state.Stage == "Deciding" then
		return focus + DIORAMA_PROMPT_SHIFT, DIORAMA_DECIDE_ZOOM
	end
	if state.Stage == "Moving" and ahead then
		-- Running: look one or two spaces ahead, and pull back for turns and climbs so the next
		-- stretch of route stays in view.
		local beyond = ahead.Next and ahead.Next[1] and self.SpaceById[ahead.Next[1]]
		local target = if beyond then (ahead.Position + beyond.Position) / 2 else ahead.Position
		local zoom = 1 + math.clamp(math.abs(target.Y - here.Y) / 14, 0, 0.25)
		if beyond then
			local first, second = ahead.Position - space.Position, beyond.Position - ahead.Position
			if first.Magnitude > 0 and second.Magnitude > 0 and first.Unit:Dot(second.Unit) < 0.8 then
				zoom += 0.1
			end
		end
		return here:Lerp(target, DIORAMA_LOOKAHEAD), zoom
	end
	return focus, 1
end

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
	self.PanelsHidden = false
	if self.Visible then
		self:refresh()
		return
	end
	self.Visible = true
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
		local festival = self.Layout and self.Layout.Festival
		local diorama = self:isDiorama() and not self.MapOpen
		local goal, zoom = nil, 1
		if self.MapOpen or festival then
			goal = self.Centre
		elseif diorama then
			goal, zoom = dioramaShot(self)
		else
			goal = turnFocus(self)
		end
		if not goal then
			return
		end
		self.Focus = if self.Focus then self.Focus:Lerp(goal, 1 - math.exp(-4 * dt)) else goal
		self.Zoom += (zoom - self.Zoom) * (1 - math.exp(-3 * dt))
		camera.CameraType = Enum.CameraType.Scriptable
		-- MAP view, else the phone (touch) offset, else the desktop offset; the festival board
		-- overrides all of them with its own whole-board framing.
		local offset = if self.MapOpen
			then MAP_OFFSET
			elseif UserInputService.TouchEnabled then TOUCH_CAMERA_OFFSET
			else CAMERA_OFFSET
		if diorama then
			offset = (if UserInputService.TouchEnabled then DIORAMA_TOUCH_OFFSET else DIORAMA_OFFSET) * self.Zoom
		elseif self.MapOpen and self:isDiorama() then
			-- MAP over a diorama board: slide the board right so the MAP panel (left) doesn't
			-- cover it, and see it from a little lower so terraces and stairs read.
			offset = Vector3.new(0, 112, 72)
		end
		if festival then
			local aspect = camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
			local distance = math.max(190, 190 / math.max(0.5, aspect))
			offset = Vector3.new(0, distance, distance * 0.38)
		end
		local aim = self.Focus
		if self.MapOpen and self:isDiorama() then
			-- Aim right of the board centre so the board sits in the free right part of the screen
			-- (the MAP panel covers the left). Offsets alone would only tilt the view.
			aim += Vector3.new(-30, 0, 0)
		end
		camera.CFrame = CFrame.lookAt(aim + offset, aim)
		-- Board-opening intro: its own shots, blending into this camera at the end.
		local shot, blend = self.Opening:camera()
		if shot then
			camera.CFrame = shot:Lerp(camera.CFrame, blend * blend * (3 - 2 * blend))
		end
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

-- Everything off: banner, standings, menu, avatar, die prompt, progress, prompt card, MAP.
local function clearPanels(self)
	self.Banner:stop()
	self.IntroActive = false
	self.Header.Visible = false
	self.Standings.Visible = false
	self:toggleMap(false)
	self.Menu.Root.Visible = false
	self.Menu:closeItems()
	self.Menu:unbind()
	self.RollButton.Visible = false
	self.ItemsOffered = false
	self.Portrait:hide()
	self.DicePrompt:hide()
	self.Prompt.Visible = false
	ContextActionService:UnbindAction(ROLL_ACTION)
	self.RollBound = false
end

function BoardView:hide()
	BoardMotion.stopAll()
	self.Opening:finish()
	if not self.Visible then
		return
	end
	self.Visible = false -- first: clearPanels' MAP reset calls refresh(), which must not re-show panels
	clearPanels(self)
	ContextActionService:UnbindAction(MAP_ACTION)
	self.Dice:clear()
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Keeps the board camera but hides every panel (final standings card).
function BoardView:hidePanels()
	self.PanelsHidden = true
	clearPanels(self)
	ContextActionService:UnbindAction(MAP_ACTION)
end

-- Server presentation messages: a move segment (BoardMove) and the board intro (BoardIntro).
function BoardView:move(message)
	BoardMotion.play(message)
end

function BoardView:playOpening(message)
	self.Opening:play(message)
	self:refresh()
end

-- Per frame: moving pieces, the intro, and the roll countdown on the ROLL row.
function BoardView:update(dt: number?)
	BoardMotion.update(dt or 1 / 60)
	local opening = self.Opening.Active
	self.Opening:update(dt or 1 / 60)
	if opening and not self.Opening.Active then
		self:refresh() -- intro over: the HUD comes back
	end
	local row = self.Menu.Rows.Roll
	if self.RollButton.Visible and self.State and self.State.RollEndsAt then
		row.BaseNote = ("%ds left"):format(math.max(0, math.ceil(self.State.RollEndsAt - Workspace:GetServerTimeNow())))
		row.Note.Text = row.BaseNote
	end
end

return BoardView
