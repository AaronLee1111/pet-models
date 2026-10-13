--[[
	ProgressBar
	Race bar along the top of the screen: one marker per participant sliding from the start
	(left) to the finish flag (right). Used instead of the chip strip by minigames with
	Info.ProgressBar = true. It is fed by the same chip list: a value like "37%" places the
	marker, and any value containing 🏁 counts as finished.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local ProgressBar = {}
ProgressBar.__index = ProgressBar

local MARKER_SIZE = 26
local MARKER_COLORS = {
	Theme.Colors.Accent,
	Theme.Colors.Hot,
	Theme.Colors.Cool,
	Theme.Colors.Good,
}

function ProgressBar.new(screen: ScreenGui)
	local self = setmetatable({}, ProgressBar)
	self.Root = make("Frame", {
		Name = "ProgressBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.new(0.86, 0, 0, 44),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	-- The track the markers slide along (leaves room for the flag on the right).
	self.Track = make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, MARKER_SIZE, 0.5, 0),
		Size = UDim2.new(1, -MARKER_SIZE * 3, 0, 12),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.1,
		Parent = self.Root,
	}, { Theme.corner(6), Theme.stroke(Theme.Colors.CardLight, 2) })
	Theme.label({
		Name = "Flag",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(MARKER_SIZE + 6, MARKER_SIZE + 6),
		Text = "🏁",
		Parent = self.Root,
	}, 26)
	self.Markers = {}
	return self
end

local function fractionOf(value): number
	if type(value) == "number" then
		return math.clamp(value / 100, 0, 1)
	end
	if type(value) ~= "string" then
		return 0
	end
	if value:find("🏁", 1, true) then
		return 1
	end
	local percent = tonumber(value:match("(%d+)%%"))
	return if percent then math.clamp(percent / 100, 0, 1) else 0
end

local function buildMarker(track: Frame, order: number)
	local color = MARKER_COLORS[(order - 1) % #MARKER_COLORS + 1]
	local stroke = Theme.stroke(Color3.new(1, 1, 1), 2)
	local frame = make("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE),
		BackgroundColor3 = color,
		Parent = track,
	}, { Theme.corner(MARKER_SIZE // 2), stroke })
	local tag = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Overlay,
		Text = "",
		Parent = frame,
	}, 14)
	return { Frame = frame, Stroke = stroke, Tag = tag }
end

function ProgressBar:update(chips, myId: string)
	local seen = {}
	for order, chip in chips do
		seen[chip.Id] = true
		local marker = self.Markers[chip.Id] or buildMarker(self.Track, order)
		self.Markers[chip.Id] = marker

		local isMe = chip.Id == myId
		marker.Tag.Text = if isMe then "YOU" else string.sub(chip.Name, 1, 1)
		marker.Stroke.Color = if isMe then Theme.Colors.Accent else Color3.new(1, 1, 1)
		marker.Stroke.Thickness = if isMe then 3 else 2
		marker.Frame.ZIndex = if isMe then 5 else 2
		local size = if isMe then MARKER_SIZE + 8 else MARKER_SIZE
		marker.Frame.Size = UDim2.fromOffset(size, size)

		local goal = UDim2.fromScale(fractionOf(chip.Value), 0.5)
		TweenService:Create(marker.Frame, TweenInfo.new(0.2, Enum.EasingStyle.Linear), { Position = goal }):Play()
	end
	for id, marker in self.Markers do
		if not seen[id] then
			marker.Frame:Destroy()
			self.Markers[id] = nil
		end
	end
end

function ProgressBar:show()
	self.Root.Visible = true
end

function ProgressBar:hide()
	self.Root.Visible = false
	for id, marker in self.Markers do
		marker.Frame:Destroy()
		self.Markers[id] = nil
	end
end

return ProgressBar
