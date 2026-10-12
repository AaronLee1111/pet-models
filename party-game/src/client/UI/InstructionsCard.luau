--[[
	InstructionsCard
	"How to play" card shown while the server builds the arena and teleports everyone:
	name, layout, description, controls, and (for 1v3 / 2v2) who is on which team.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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
	self.Controls = Theme.label({
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.13),
		TextColor3 = Theme.Colors.Good,
		Parent = self.Root,
	}, 24)
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

local function controlsText(controls): string
	local parts = {}
	if controls.Move and controls.Jump then
		table.insert(parts, "🕹 Move + Jump")
	elseif controls.Move then
		table.insert(parts, "🕹 Move (no jumping)")
	else
		table.insert(parts, "🔒 You can't walk this round")
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	for _, action in controls.Actions do
		if touch or not action.Key then
			table.insert(parts, ("👆 %s button"):format(action.Label))
		else
			table.insert(parts, ("[%s] %s"):format(action.Key, action.Label))
		end
	end
	return table.concat(parts, "    ")
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
	self.Controls.Text = controlsText(minigame.Controls)
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
