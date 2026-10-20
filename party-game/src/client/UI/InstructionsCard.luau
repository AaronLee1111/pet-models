--[[
	InstructionsCard
	"How to play" card shown while the server builds the arena and teleports everyone:
	name, layout, description, controls, and (for 1v3 / 2v2) who is on which team.
]]

local Workspace = game:GetService("Workspace")

local Icons = require(script.Parent.Icons)
local InputHint = require(script.Parent.InputHint)
local Theme = require(script.Parent.Theme)
local make = Theme.make

local InstructionsCard = {}
InstructionsCard.__index = InstructionsCard

function InstructionsCard.new(screen: ScreenGui)
	local self = setmetatable({}, InstructionsCard)
	self.EndsAt = nil

	self.Root = make("Frame", {
		Name = "Instructions",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		BackgroundColor3 = Theme.Colors.Card,
		Visible = false,
		Parent = screen,
	}, {
		Theme.corner(22),
		Theme.stroke(Theme.Colors.Accent, 4),
		Theme.padding(18),
		make("UISizeConstraint", { MaxSize = Vector2.new(720, 460) }),
	})

	self.Title = Theme.label({
		Size = UDim2.fromScale(1, 0.18),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Parent = self.Root,
	}, 52)
	self.Layout = Theme.label({
		Position = UDim2.fromScale(0, 0.19),
		Size = UDim2.fromScale(1, 0.08),
		TextColor3 = Theme.Colors.Cool,
		Parent = self.Root,
	}, 22)
	self.Description = Theme.label({
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(1, 0.28),
		Parent = self.Root,
	}, 26)
	-- Controls: one row of [prompt icon] text items, centred (see controlParts).
	self.Controls = make("Frame", {
		Name = "Controls",
		Position = UDim2.fromScale(0, 0.585),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y, -- a long row wraps onto a second line (icons stay >= 24 px)
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10), -- between items and between wrapped lines
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
		}),
	})
	self.Teams = Theme.label({
		Position = UDim2.fromScale(0, 0.74),
		Size = UDim2.fromScale(1, 0.12),
		RichText = true,
		Parent = self.Root,
	}, 20)
	self.Clock = Theme.label({
		Position = UDim2.fromScale(0, 0.88),
		Size = UDim2.fromScale(1, 0.12),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Muted,
		Parent = self.Root,
	}, 24)
	return self
end

-- The controls line as parts: { Icon = atlas name?, Overlay = atlas name?, Key = KeyCode name?,
-- Letter = native text drawn on the icon?, Text = what it says }. mode = InputHint.mode(): touch shows the tap prompt
-- and the button label only, a keyboard shows the key, a gamepad its controller button. Inputs
-- the atlas has no prompt for keep the old "[KEY]" text.
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

-- Draws the parts into the Controls row. light = the card is a light panel (outline / dark cells).
local function renderControls(self, parts, light: boolean)
	for _, child in self.Controls:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rowHeight = self.Root.AbsoluteSize.Y * 0.13 -- one line's share of the card
	local iconSize = math.floor(math.clamp(rowHeight * 0.8, 24, 40))
	local textSize = math.floor(math.clamp(rowHeight * 0.45, 14, 24))
	local textColour = if light then Theme.Glass.Deep else Theme.Colors.Good
	for order, part in parts do
		local item = make("Frame", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, iconSize),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = self.Controls,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
		})
		local props = part.Icon and Icons.image(part.Icon, nil, light)
		if props then
			local icon = make("ImageLabel", {
				Name = "Icon_" .. part.Icon,
				LayoutOrder = 1,
				Size = UDim2.fromOffset(iconSize, iconSize),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				Parent = item,
			})
			for key, value in props do
				(icon :: any)[key] = value
			end
			local overlay = part.Overlay and Icons.image(part.Overlay, nil, light)
			if overlay then
				local layer = make("ImageLabel", { Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = icon })
				for key, value in overlay do
					(layer :: any)[key] = value
				end
			end
			if part.Letter then
				make("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Font = Theme.TitleFont,
					TextScaled = true,
					TextColor3 = Theme.Glass.Deep,
					Text = part.Letter,
					Parent = icon,
				}, { make("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0) }) })
			end
		end
		make("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, iconSize),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Theme.BodyFont,
			TextSize = textSize,
			TextColor3 = textColour,
			Text = part.Text,
			Parent = item,
		})
	end
end

local function teamsText(participants, myId: string): string
	local teams = { {}, {} }
	for _, participant in participants do
		if participant.Team then
			local name = participant.Name
			if participant.Id == myId then
				name = "<b>YOU</b>"
			end
			table.insert(teams[participant.Team], name)
		end
	end
	if #teams[1] == 0 then
		return ""
	end
	local function hex(color: Color3)
		return color:ToHex()
	end
	return ('<font color="#%s">%s</font>   vs   <font color="#%s">%s</font>'):format(
		hex(Theme.TeamColors[1]),
		table.concat(teams[1], ", "),
		hex(Theme.TeamColors[2]),
		table.concat(teams[2], ", ")
	)
end

function InstructionsCard:show(minigame, participants, endsAt: number, myId: string)
	self.EndsAt = endsAt
	self.Title.Text = minigame.Name
	self.Layout.Text = ("%s  •  %d seconds"):format(minigame.Layout, minigame.Duration)
	self.Description.Text = minigame.Description
	local bg = self.Root.BackgroundColor3
	local light = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B > 0.6
	renderControls(self, InstructionsCard.controlParts(minigame.Controls, InputHint.mode()), light)
	self.Teams.Text = teamsText(participants, myId)
	self.Root.Visible = true
	Theme.pop(self.Root)
end

function InstructionsCard:update()
	if self.Root.Visible and self.EndsAt then
		local remaining = math.max(0, math.ceil(self.EndsAt - Workspace:GetServerTimeNow()))
		self.Clock.Text = ("Get ready... %d"):format(remaining)
	end
end

function InstructionsCard:hide()
	self.Root.Visible = false
end

return InstructionsCard
