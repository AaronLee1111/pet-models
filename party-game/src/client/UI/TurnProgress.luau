--[[
	TurnProgress
	Small secondary pill, bottom centre: "Round 2 / 5 · Turn 3 / 4", with one short status line
	under it ("Rolled 4 · 3 moves left", "Pip is deciding", bridge state).

	  local progress = TurnProgress.new(screen)
	  progress.Title.Text, progress.Subtitle.Text
	  progress.Root                 named "BoardHeader" (tests and the HUD look for it)
]]

local Theme = require(script.Parent.Theme)
local make = Theme.make

local TurnProgress = {}
TurnProgress.__index = TurnProgress

TurnProgress.SIZE = Vector2.new(520, 64) -- design px

function TurnProgress.new(screen: ScreenGui)
	local self = setmetatable({}, TurnProgress)
	self.Root = Theme.glass(make("Frame", {
		Name = "BoardHeader",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(TurnProgress.SIZE.X, TurnProgress.SIZE.Y),
		Visible = false,
		Parent = screen,
	}), 20)
	self.Title = make("TextLabel", {
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -24, 0, 28),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 24,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.Glass.Cream,
		Parent = self.Root,
	})
	self.Subtitle = make("TextLabel", {
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, 24),
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = 18,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.Glass.Gold,
		Parent = self.Root,
	})
	self.Scale = make("UIScale", { Parent = self.Root })
	return self
end

return TurnProgress
