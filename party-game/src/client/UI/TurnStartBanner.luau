--[[
	TurnStartBanner
	"Aaron, start!": a wide translucent glass band across the upper gameplay area at the start
	of every turn. Slides in, holds, slides out; the board stays visible through it.

	  local banner = TurnStartBanner.new(screen)
	  banner:play(text, short, onDone)    short = bot version
	  banner.Root                         BoardView sets its top (below Roblox's top bar)

	Timing: in 0.2 s, hold 0.85 s, out 0.2 s (bots: 0.15 / 0.5 / 0.15).
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local TurnStartBanner = {}
TurnStartBanner.__index = TurnStartBanner

TurnStartBanner.HEIGHT = 110 -- design px

function TurnStartBanner.new(screen: ScreenGui)
	local self = setmetatable({ Playing = 0 }, TurnStartBanner)
	self.Root = make("Frame", {
		Name = "TurnStartBanner",
		Size = UDim2.new(1, 0, 0, TurnStartBanner.HEIGHT),
		BackgroundColor3 = Theme.Glass.Deep,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		Parent = screen,
	}, {
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.2, 0),
				NumberSequenceKeypoint.new(0.8, 0),
				NumberSequenceKeypoint.new(1, 0.6),
			}),
		}),
	})
	-- Thin gold rules above and below
	for _, y in { 0, 1 } do
		make("Frame", {
			AnchorPoint = Vector2.new(0, y),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = Theme.Glass.Gold,
			BorderSizePixel = 0,
			Parent = self.Root,
		})
	end
	self.Label = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 70),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 72,
		TextColor3 = Theme.Glass.Cream,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = self.Root,
	}, { make("UIStroke", { Color = Theme.Glass.Deep, Thickness = 3 }) })
	self.Scale = make("UIScale", { Parent = self.Label })
	return self
end

function TurnStartBanner:play(text: string, short: boolean?, onDone: (() -> ())?)
	self.Playing += 1
	local token = self.Playing
	local inTime, hold, outTime = 0.2, 0.85, 0.2
	if short then
		inTime, hold, outTime = 0.15, 0.5, 0.15
	end
	self.Label.Text = text
	self.Label.Position = UDim2.fromScale(-0.3, 0.5)
	self.Root.BackgroundTransparency = 1
	self.Root.Visible = true
	Theme.tick(0.3)
	TweenService:Create(self.Root, TweenInfo.new(inTime), { BackgroundTransparency = 0.3 }):Play()
	TweenService:Create(self.Label, TweenInfo.new(inTime + 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	task.delay(inTime + hold, function()
		if self.Playing ~= token then
			return
		end
		TweenService:Create(self.Root, TweenInfo.new(outTime), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.Label, TweenInfo.new(outTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(1.3, 0.5) }):Play()
		task.delay(outTime, function()
			if self.Playing ~= token then
				return
			end
			self.Root.Visible = false
			if onDone then
				onDone()
			end
		end)
	end)
end

function TurnStartBanner:stop()
	self.Playing += 1
	self.Root.Visible = false
end

return TurnStartBanner
