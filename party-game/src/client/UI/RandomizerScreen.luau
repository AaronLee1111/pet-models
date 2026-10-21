--[[
	RandomizerScreen
	The minigame pick, shown as a roulette: every game this round could pick in a list, one
	highlighted at a time, speeding through and slowing onto the minigame the server already
	chose; the header then names its category ("2 vs 2 MINIGAME"; duels say DUEL from the
	start). No input, no votes.

	  local screen = RandomizerScreen.new(parent)
	  screen:show(message)   the Select phase message (Candidates, Start, Steps, StartsAt, ...)
	  screen:update()        every frame
	  screen:hide()

	Where the highlight is depends only on server time and the server's Start / Steps, so every
	client shows the same thing, and a client that joins late picks it up mid-spin.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Canvas = require(script.Parent.Canvas)
local Theme = require(script.Parent.Theme)
local make = Theme.make

local RandomizerScreen = {}
RandomizerScreen.__index = RandomizerScreen

local VISIBLE = 7 -- rows on screen (5 on landscape phones); longer lists scroll around the highlight
local PHONE_VISIBLE = 5
local ROW_H, GAP = 68, 12
local ACTIVE = Color3.fromRGB(226, 78, 122) -- saturated party accent
local EASE = 2.4 -- higher = slows down harder at the end

-- Rows moved so far at fraction u (0..1) of the spin: fast first, easing onto the last row.
function RandomizerScreen.moved(steps: number, u: number): number
	u = math.clamp(u, 0, 1)
	return math.floor((1 - (1 - u) ^ EASE) * steps + 1e-6)
end

function RandomizerScreen.new(parent: Instance)
	local self = setmetatable({}, RandomizerScreen)
	self.Root, self.Canvas = Canvas.new(parent, "Randomizer")
	self.Title = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(640, 34),
		Size = UDim2.fromOffset(1100, 70),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 60,
		TextColor3 = Theme.Glass.Gold,
		Parent = self.Canvas,
	}, { make("UIStroke", { Color = Theme.Glass.Deep, Thickness = 3 }) })
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(640, 112),
		Size = UDim2.fromOffset(1000, 4),
		BackgroundColor3 = Theme.Glass.Gold,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = self.Canvas,
	})
	self.List = make("Frame", {
		Position = UDim2.fromOffset(190, 140),
		Size = UDim2.fromOffset(900, VISIBLE * ROW_H + (VISIBLE - 1) * GAP),
		BackgroundTransparency = 1,
		Parent = self.Canvas,
	})
	self.Rows = {}
	for i = 1, VISIBLE do
		local row = make("Frame", {
			Position = UDim2.fromOffset(0, (i - 1) * (ROW_H + GAP)),
			Size = UDim2.fromOffset(900, ROW_H),
			BackgroundColor3 = Theme.Glass.Cream,
			BackgroundTransparency = 0.82,
			Parent = self.List,
		}, { Theme.corner(16) })
		local stroke = Theme.stroke(Theme.Glass.Gold, 3)
		stroke.Transparency = 1
		stroke.Parent = row
		local label = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.TitleFont,
			TextSize = 38,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Theme.Glass.Cream,
			TextTransparency = 0.35,
			Parent = row,
		})
		self.Rows[i] = { Frame = row, Label = label, Stroke = stroke, Scale = make("UIScale", { Parent = row }) }
	end
	return self
end

function RandomizerScreen:show(message)
	self.Message = message
	self.Title.Text = message.Title or "MINIGAME"
	self.LastIndex = nil
	self.Revealed = false
	-- Short lists sit centred; long ones use every row and scroll.
	local count = #message.Candidates
	self.Window = if Canvas.wide(self.Root) then PHONE_VISIBLE else VISIBLE
	self.Shown = math.min(self.Window, count)
	local top = (self.Window - self.Shown) * (ROW_H + GAP) / 2
	for i, row in self.Rows do
		row.Frame.Visible = i <= self.Shown
		row.Frame.Position = UDim2.fromOffset(0, top + (i - 1) * (ROW_H + GAP))
	end
	self.Root.Visible = true
	self:update()
end

function RandomizerScreen:hide()
	self.Root.Visible = false
	self.Message = nil
end

-- Which candidate is highlighted now (1-based), and whether the spin has finished.
function RandomizerScreen:current(): (number, boolean)
	local m = self.Message
	local count = #m.Candidates
	local u = (Workspace:GetServerTimeNow() - m.StartsAt) / math.max(0.1, m.SpinEndsAt - m.StartsAt)
	local moved = RandomizerScreen.moved(m.Steps, u)
	return (m.Start - 1 + moved) % count + 1, u >= 1
end

function RandomizerScreen:update()
	local m = self.Message
	if not (m and self.Root.Visible) then
		return
	end
	Canvas.fit(self.Root, self.Canvas, 160 + self.Window * (ROW_H + GAP))
	local count = #m.Candidates
	local index, done = self:current()
	if done then
		index = m.ResultIndex -- the server's pick, whatever this client's clock says
	end
	-- Rows: a window of names around the highlight (all of them when the list is short).
	local first = if count <= self.Window then 1 else index - math.floor(self.Window / 2)
	for i = 1, self.Shown do
		local candidate = (first + i - 2) % count + 1
		local row = self.Rows[i]
		local active = candidate == index
		row.Label.Text = m.Candidates[candidate]
		row.Frame.BackgroundColor3 = if active then ACTIVE else Theme.Glass.Cream
		row.Frame.BackgroundTransparency = if active then 0 else 0.82
		row.Stroke.Transparency = if active then 0 else 1
		row.Label.TextTransparency = if active then 0 else 0.35
		row.Label.TextSize = if active then 42 else 38
	end
	if index ~= self.LastIndex and not done then
		self.LastIndex = index
		Theme.tick(0.18, 1.3)
	end
	if done and not self.Revealed then
		self.Revealed = true
		self.Title.Text = m.ResultTitle or self.Title.Text -- "2 vs 2 MINIGAME" arrives with the pick
		Theme.tick(0.5, 0.75) -- confirm
		for i = 1, self.Shown do
			local row = self.Rows[i]
			if row.Frame.BackgroundTransparency == 0 then
				row.Scale.Scale = 1
				TweenService:Create(row.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true), { Scale = 1.07 }):Play()
			end
		end
	end
end

return RandomizerScreen
