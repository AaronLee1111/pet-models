--[[
	InstructionsCard
	The pre-minigame tutorial screen (Instructions phase), on a 1280x720 canvas:

	  title                    the minigame's name, with its layout ("2 vs 2")
	  left  (~60%)             looping in-engine demonstration (TutorialPreview)
	  under it                 objective, one rule, the win condition
	  right                    CONTROLS: one line per control, with the atlas prompt for this
	                           device (keyboard / Xbox / PlayStation / neutral pad / touch);
	                           your team when the layout has teams
	  bottom                   every participant's avatar with waiting / ready / bot / left,
	                           and a big READY button (unlocks after one preview loop)

	  local card = InstructionsCard.new(screen, send)
	  card:show(message, myId)        the Instructions phase message
	  card:setReady(readyIds, leftIds) from TutorialReady messages
	  card:update()                    every frame
	  card:hide()

	The server decides when the round starts (everyone ready, or the timeout); READY only asks.
]]

local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local ActivePlayerPortrait = require(script.Parent.ActivePlayerPortrait)
local Canvas = require(script.Parent.Canvas)
local Icons = require(script.Parent.Icons)
local InputHint = require(script.Parent.InputHint)
local Theme = require(script.Parent.Theme)
local TutorialPreview = require(script.Parent.TutorialPreview)
local make = Theme.make

local InstructionsCard = {}
InstructionsCard.__index = InstructionsCard

local READY_ACTION = "PartyTutorialReady"
local LAYOUT_NAMES = { FFA = "FREE-FOR-ALL", ["2v2"] = "2 vs 2", ["1v3"] = "1 vs 3", Duel = "DUEL" }
local TEAM_NAMES = { "RED TEAM", "BLUE TEAM" }
local CREAM, GOLD, DEEP = Theme.Glass.Cream, Theme.Glass.Gold, Theme.Glass.Deep

-- Legacy one-line controls summary (kept for logs and tests) ---------------------------------

function InstructionsCard.controlParts(controls, mode: string)
	local parts = {}
	if controls.Move and controls.Jump then
		table.insert(parts, { Icon = "Move", Text = "Move + Jump" })
	elseif controls.Move then
		table.insert(parts, { Icon = "Move", Text = "Move (no jumping)" })
	else
		table.insert(parts, { Icon = "Move", Overlay = "NoMove", Text = "You can't walk this round" })
	end
	for index, action in controls.Actions do
		local name = if mode == "Mouse"
			then InputHint.keyFor(action)
			elseif mode == "Gamepad" then InputHint.gamepadFor(action, index)
			else nil
		local icon = name and InputHint.prompt(name)
		if mode == "Touch" then
			table.insert(parts, { Icon = "Tap", Text = ("%s button"):format(action.Label) })
		elseif icon then
			table.insert(parts, { Icon = icon, Key = name, Letter = if icon == "GamepadAction" then InputHint.keyName(name) else nil, Text = action.Label })
		elseif name then
			table.insert(parts, { Text = ("[%s] %s"):format(InputHint.keyName(name), action.Label) })
		else
			table.insert(parts, { Text = action.Label })
		end
	end
	return parts
end

-- Plain-text version of the same line (logs, tests, screen readers).
function InstructionsCard.controlsText(controls, mode: string): string
	local out = {}
	for _, part in InstructionsCard.controlParts(controls, mode) do
		table.insert(out, if part.Key then ("[%s] %s"):format(InputHint.keyName(part.Key), part.Text) else part.Text)
	end
	return table.concat(out, "    ")
end

-- Tutorial control lines -------------------------------------------------------------------

--[[
	The tutorial's control lines for this device: { { Label, Note?, Icons = { prompt } } }
	where prompt = { Icon = atlas name, Overlay = atlas name?, Letter = native text on the icon? }
	or { KeyText = "1" } for a key the atlas has no prompt for. Touch never shows key prompts.
]]
function InstructionsCard.controlLines(tutorialLines, controls, mode: string)
	local byName = {}
	for index, action in controls.Actions do
		byName[action.Action] = { Action = action, Index = index }
	end
	local out = {}
	for _, line in tutorialLines do
		local prompts, seen = {}, {}
		local function add(prompt)
			local key = (prompt.Icon or "") .. (prompt.Letter or "") .. (prompt.KeyText or "")
			if not seen[key] then
				seen[key] = true
				table.insert(prompts, prompt)
			end
		end
		if line.NoMove then
			add({ Icon = "Move", Overlay = "NoMove" })
		elseif line.Move then
			if mode == "Mouse" then
				for _, key in { "KeyW", "KeyA", "KeyS", "KeyD" } do
					add({ Icon = key })
				end
			else
				add({ Icon = "Move" })
			end
		elseif line.Jump then
			if mode == "Mouse" then
				add({ Icon = "KeySpace" })
			elseif mode == "Gamepad" then
				local icon = InputHint.prompt("ButtonA")
				add({ Icon = icon, Letter = if icon == "GamepadAction" then "A" else nil })
			else
				add({ Icon = "Tap" })
			end
		end
		for _, actionName in line.Actions or {} do
			local found = byName[actionName]
			if not found then
				continue
			end
			if mode == "Touch" then
				add({ Icon = "Tap" })
				continue
			end
			local name = if mode == "Gamepad" then InputHint.gamepadFor(found.Action, found.Index) else InputHint.keyFor(found.Action)
			local icon = name and InputHint.prompt(name)
			if icon then
				add({ Icon = icon, Letter = if icon == "GamepadAction" then InputHint.keyName(name) else nil })
			elseif name then
				add({ KeyText = InputHint.keyName(name) })
			end
		end
		table.insert(out, { Label = line.Label, Note = line.Note, Icons = prompts })
	end
	return out
end

-- Screen ------------------------------------------------------------------------------------

local function label(props, parent)
	local defaults = { BackgroundTransparency = 1, Font = Theme.TitleFont, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }
	for key, value in props do
		defaults[key] = value
	end
	defaults.Parent = parent
	return make("TextLabel", defaults)
end

local function setIcon(image: ImageLabel, props)
	for key, value in props do
		(image :: any)[key] = value
	end
end

function InstructionsCard.new(screen: ScreenGui, send: ((any) -> ())?)
	local self = setmetatable({ Send = send, Chips = {} }, InstructionsCard)
	self.EndsAt = nil
	self.Root, self.Canvas = Canvas.new(screen, "Instructions")
	local c = self.Canvas

	self.Title = label({ Position = UDim2.fromOffset(40, 16), Size = UDim2.fromOffset(560, 70), TextSize = 56 }, c)
	self.Layout = label({
		Position = UDim2.fromOffset(600, 30),
		Size = UDim2.fromOffset(170, 44),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
		TextColor3 = DEEP,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, c)
	Theme.corner(14).Parent = self.Layout

	-- Left: preview
	self.PreviewHolder = make("Frame", {
		Position = UDim2.fromOffset(40, 96),
		Size = UDim2.fromOffset(730, 382),
		BackgroundTransparency = 1,
		Parent = c,
	}, { Theme.corner(18), Theme.stroke(GOLD, 4) })
	self.Preview = TutorialPreview.new(self.PreviewHolder)

	-- Under it: objective + one short line
	self.Description = label({ Position = UDim2.fromOffset(40, 486), Size = UDim2.fromOffset(730, 40), TextSize = 32 }, c)
	self.Rule = label({ Position = UDim2.fromOffset(40, 528), Size = UDim2.fromOffset(730, 32), TextSize = 24, Font = Theme.BodyFont, TextColor3 = GOLD }, c)
	self.Win = label({ Position = UDim2.fromOffset(40, 562), Size = UDim2.fromOffset(730, 32), TextSize = 24, Font = Theme.BodyFont }, c)

	-- Right: controls
	self.ControlsPanel = Theme.glass(make("Frame", {
		Position = UDim2.fromOffset(796, 96),
		Size = UDim2.fromOffset(444, 382),
		Parent = c,
	}), 20)
	label({ Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(400, 36), Text = "CONTROLS", TextSize = 30, TextColor3 = GOLD }, self.ControlsPanel)
	self.Controls = make("Frame", {
		Name = "Controls",
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.fromOffset(412, 260),
		BackgroundTransparency = 1,
		Parent = self.ControlsPanel,
	}, { make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self.Teams = label({ Position = UDim2.fromOffset(20, 332), Size = UDim2.fromOffset(404, 36), TextSize = 25, RichText = true }, self.ControlsPanel)

	-- Bottom: readiness chips + READY
	self.ChipRow = make("Frame", {
		Position = UDim2.fromOffset(40, 604),
		Size = UDim2.fromOffset(940, 104),
		BackgroundTransparency = 1,
		Parent = c,
	}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self.ReadyButton = make("TextButton", {
		Name = "TutorialReady",
		Position = UDim2.fromOffset(996, 604),
		Size = UDim2.fromOffset(244, 104), -- >= 44 pt tall at the smallest phone scale (~0.5)
		BackgroundColor3 = GOLD,
		AutoButtonColor = true,
		Text = "",
		Parent = c,
	}, { Theme.corner(22), Theme.stroke(CREAM, 3) })
	self.ReadyIcon = make("ImageLabel", {
		Position = UDim2.fromOffset(16, 26),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Parent = self.ReadyButton,
	})
	self.ReadyText = label({
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -80, 1, 0),
		TextSize = 38,
		TextColor3 = DEEP,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, self.ReadyButton)
	self.ReadyButton.Activated:Connect(function()
		self:ready()
	end)
	self.Clock = label({ Position = UDim2.fromOffset(796, 486), Size = UDim2.fromOffset(444, 40), TextSize = 28, TextColor3 = Theme.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Right }, c)
	self.BaseY = {}
	for _, item in { self.Description, self.Rule, self.Win, self.Clock, self.ChipRow, self.ReadyButton } do
		self.BaseY[item] = item.Position.Y.Offset
	end
	self.Compact = false
	return self
end

local function teamsText(participants, myId: string): string
	local mine
	for _, participant in participants do
		if participant.Id == myId then
			mine = participant.Team
		end
	end
	if not mine then
		return ""
	end
	local mates = {}
	for _, participant in participants do
		if participant.Team == mine and participant.Id ~= myId then
			table.insert(mates, participant.Name)
		end
	end
	local colour = Theme.TeamColors[mine]:ToHex()
	local with = if #mates > 0 then " with " .. table.concat(mates, ", ") else " (on your own)"
	return ('<font color="#%s">%s</font>%s'):format(colour, TEAM_NAMES[mine] or "TEAM", with)
end

local function renderControls(self, lines)
	for _, child in self.Controls:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, line in lines do
		local row = make("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(412, 62), BackgroundTransparency = 1, Parent = self.Controls })
		label({ Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(200, if line.Note then 40 else 62), Text = line.Label, TextSize = 30 }, row)
		if line.Note then
			label({ Position = UDim2.fromOffset(4, 38), Size = UDim2.fromOffset(200, 24), Text = line.Note, TextSize = 22, Font = Theme.BodyFont, TextColor3 = GOLD }, row)
		end
		-- the prompts sit on a cream tile (a light panel: outline / dark-tinted cells)
		local tile = make("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(412, 0),
			Size = UDim2.fromOffset(0, 62),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = CREAM,
			Parent = row,
		}, {
			Theme.corner(14),
			make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for index, prompt in line.Icons do
			if prompt.KeyText then
				make("TextLabel", {
					LayoutOrder = index,
					Size = UDim2.fromOffset(46, 46),
					BackgroundColor3 = CREAM,
					Font = Theme.TitleFont,
					TextSize = 28,
					TextColor3 = DEEP,
					Text = prompt.KeyText,
					Parent = tile,
				}, { Theme.corner(10), Theme.stroke(DEEP, 3) })
				continue
			end
			local props = Icons.image(prompt.Icon, nil, true)
			if not props then
				continue
			end
			local icon = make("ImageLabel", { LayoutOrder = index, Size = UDim2.fromOffset(50, 50), BackgroundTransparency = 1, Parent = tile })
			setIcon(icon, props)
			local overlay = prompt.Overlay and Icons.image(prompt.Overlay, nil, true)
			if overlay then
				setIcon(make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = icon }), overlay)
			end
			if prompt.Letter then
				make("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Font = Theme.TitleFont,
					TextSize = 24,
					TextColor3 = DEEP,
					Text = prompt.Letter,
					Parent = icon,
				})
			end
		end
	end
end

local function chip(self, participant, myId)
	local isMe = participant.Id == myId
	local frame = Theme.glass(make("Frame", { Size = UDim2.fromOffset(226, 104), Parent = self.ChipRow }), 20)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if participant.Team then
		stroke.Color = Theme.TeamColors[participant.Team]
		stroke.Thickness = 3
	end
	if isMe then
		stroke.Thickness = 5
		stroke.Color = if participant.Team then Theme.TeamColors[participant.Team] else GOLD
	end
	local portrait = make("ViewportFrame", {
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = DEEP,
		Ambient = Color3.fromRGB(210, 210, 210),
		LightColor = Color3.fromRGB(255, 244, 220),
		Parent = frame,
	}, { Theme.corner(999), Theme.stroke(if isMe then GOLD else CREAM, 2) })
	if not ActivePlayerPortrait.mount(portrait, participant.Character, "Head") then
		-- no avatar to show (not loaded yet): their initial instead of an empty circle
		label({ Size = UDim2.fromScale(1, 1), Text = string.upper(string.sub(participant.Name or "?", 1, 1)), TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center }, portrait)
	end
	label({ Position = UDim2.fromOffset(100, 14), Size = UDim2.fromOffset(118, 36), Text = if isMe then "YOU" else participant.Name, TextSize = 28 }, frame)
	if participant.IsBot then
		label({ Position = UDim2.fromOffset(160, 76), Size = UDim2.fromOffset(56, 22), Text = "BOT", TextSize = 18, TextColor3 = Theme.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Right }, frame)
	end
	local status = label({ Position = UDim2.fromOffset(100, 50), Size = UDim2.fromOffset(118, 30), TextSize = 24, Font = Theme.BodyFont }, frame)
	local check = make("ImageLabel", { Position = UDim2.fromOffset(62, 62), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, Visible = false, Parent = frame })
	local props = Icons.image("Check", "Selected")
	if props then
		setIcon(check, props)
	end
	return { Frame = frame, Status = status, Check = check }
end

-- Wide, short screens (landscape phones): a shorter preview and everything below it moved up,
-- so the canvas (and its text) can scale up. COMPACT = design pixels saved.
local COMPACT = 110
local function applyLayout(self, compact: boolean)
	if self.Compact == compact then
		return
	end
	self.Compact = compact
	local d = if compact then COMPACT else 0
	self.PreviewHolder.Size = UDim2.fromOffset(730, 382 - d)
	self.ControlsPanel.Size = UDim2.fromOffset(444, 382 - d)
	self.Teams.Position = UDim2.fromOffset(20, 332 - d)
	for item, base in self.BaseY do
		item.Position = UDim2.fromOffset(item.Position.X.Offset, base - d)
	end
end

function InstructionsCard:show(message, myId: string)
	local minigame = message.Minigame
	local tutorial = minigame.Tutorial or {}
	self.Message = message
	self.MyId = myId
	self.EndsAt = message.EndsAt
	self.ReadyAt = message.ReadyAt or 0
	self.IsReady = false
	self.Title.Text = minigame.Name
	self.Layout.Text = LAYOUT_NAMES[minigame.Layout] or minigame.Layout
	self.Description.Text = tutorial.Objective or minigame.Description
	-- no rule line: the win condition moves up into its place
	self.Rule.Text = tutorial.Rule or tutorial.Win or ""
	self.Win.Text = if tutorial.Rule then tutorial.Win or "" else ""
	self.Teams.Text = teamsText(message.Participants or {}, myId)
	self.Mode = InputHint.mode()
	renderControls(self, InstructionsCard.controlLines(tutorial.Controls or {}, minigame.Controls, self.Mode))

	self.Playing = false
	for _, participant in message.Participants or {} do
		self.Playing = self.Playing or participant.Id == myId
	end
	for _, child in self.ChipRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.Chips = {}
	for _, participant in message.Participants or {} do
		self.Chips[participant.Id] = chip(self, participant, myId)
	end
	self:setReady({}, {}) -- the server sends the ready list right after the phase
	self.Preview:play(tutorial.Preview, message.Participants)
	self.Root.Visible = true
	ContextActionService:UnbindAction(READY_ACTION)
	if self.Playing then
		ContextActionService:BindAction(READY_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				self:ready()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	end
	self:update()
end

function InstructionsCard:ready()
	if not self.Playing or self.IsReady or Workspace:GetServerTimeNow() < self.ReadyAt then
		return
	end
	self.IsReady = true
	Theme.tick(0.35, 1.1)
	if self.Send then
		self.Send({ Kind = "TutorialReady" })
	end
	self:update()
end

-- Ready / left ids from the server.
function InstructionsCard:setReady(ready, left)
	local readyIds, leftIds = ready or {}, left or {}
	if self.MyId and readyIds[self.MyId] then
		self.IsReady = true
	end
	for id, c in self.Chips do
		local isReady, gone = readyIds[id] == true, leftIds[id] == true
		c.Check.Visible = isReady
		c.Status.Text = if gone then "LEFT" elseif isReady then "READY" else "WAITING"
		c.Status.TextColor3 = if gone then Theme.Glass.Disabled elseif isReady then GOLD else Theme.Colors.Muted
		c.Frame.BackgroundTransparency = if isReady then 0.05 else 0.35
	end
end

function InstructionsCard:update()
	if not (self.Root.Visible and self.EndsAt) then
		return
	end
	applyLayout(self, Canvas.wide(self.Root))
	Canvas.fit(self.Root, self.Canvas, if self.Compact then 720 - COMPACT else 720)
	local now = Workspace:GetServerTimeNow()
	self.Clock.Text = ("Starts in %d"):format(math.max(0, math.ceil(self.EndsAt - now)))
	-- READY: hidden for spectators; locked until the preview has played once
	local button = self.ReadyButton
	button.Visible = self.Playing == true
	local locked = now < self.ReadyAt
	local prompt = if self.Mode == "Touch" then "Tap" elseif self.Mode == "Gamepad" then (InputHint.prompt("ButtonA") or "GamepadAction") else "KeySpace"
	local props = Icons.image(prompt, nil, true)
	local showIcon = props ~= nil and not self.IsReady and not locked
	self.ReadyIcon.Visible = showIcon
	if props then
		setIcon(self.ReadyIcon, props)
	end
	-- the label takes the whole button when there's no prompt icon
	self.ReadyText.Position = UDim2.fromOffset(if showIcon then 70 else 10, 0)
	self.ReadyText.Size = UDim2.new(1, if showIcon then -80 else -20, 1, 0)
	if self.IsReady then
		self.ReadyText.Text = "READY!"
		button.BackgroundColor3 = Color3.fromRGB(150, 200, 170)
	elseif locked then
		self.ReadyText.Text = ("READY IN %d"):format(math.ceil(self.ReadyAt - now))
		button.BackgroundColor3 = Theme.Glass.Disabled
	else
		self.ReadyText.Text = "READY"
		button.BackgroundColor3 = GOLD
	end
	button.AutoButtonColor = not (self.IsReady or locked)
end

function InstructionsCard:hide()
	self.Root.Visible = false
	self.EndsAt = nil
	self.Preview:stop()
	ContextActionService:UnbindAction(READY_ACTION)
end

return InstructionsCard
