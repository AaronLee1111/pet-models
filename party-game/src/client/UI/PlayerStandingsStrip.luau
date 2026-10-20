--[[
	PlayerStandingsStrip
	Four compact chips across the top safe area, in turn order: round avatar portrait, name
	(cut with "…", never shrunk), Crowns, coins, placement, one held-item badge. The active
	player's chip gets the gold glow and a ▼ pointer; your own chip says YOU.

	  local strip = PlayerStandingsStrip.new(screen)
	  strip:render(state, myId)
	  strip:setChipWidth(px)      design px; BoardView fits the row between chat and player list
	  strip.Root                  named "BoardStandings" (tests and the HUD look for it)
]]

local Theme = require(script.Parent.Theme)
local ActivePlayerPortrait = require(script.Parent.ActivePlayerPortrait)
local make = Theme.make

local PlayerStandingsStrip = {}
PlayerStandingsStrip.__index = PlayerStandingsStrip

PlayerStandingsStrip.CHIP_HEIGHT = 72
PlayerStandingsStrip.GAP = 8

-- Placement by Crowns, then coins; equal players share a place.
function PlayerStandingsStrip.placements(seats): { [string]: number }
	local sorted = table.clone(seats)
	table.sort(sorted, function(a, b)
		if a.Collectibles ~= b.Collectibles then
			return a.Collectibles > b.Collectibles
		end
		return a.Coins > b.Coins
	end)
	local places = {}
	for index, seat in sorted do
		local before = sorted[index - 1]
		local same = before and before.Collectibles == seat.Collectibles and before.Coins == seat.Coins
		places[seat.Id] = if same then places[before.Id] else index
	end
	return places
end

function PlayerStandingsStrip.new(screen: ScreenGui)
	local self = setmetatable({ Chips = {}, ChipWidth = 230 }, PlayerStandingsStrip)
	self.Root = make("Frame", {
		Name = "BoardStandings",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(4 * 230 + 3 * PlayerStandingsStrip.GAP, PlayerStandingsStrip.CHIP_HEIGHT + 14),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, PlayerStandingsStrip.GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.Scale = make("UIScale", { Parent = self.Root })
	return self
end

function PlayerStandingsStrip:setChipWidth(width: number)
	self.ChipWidth = width
	self.Root.Size = UDim2.fromOffset(4 * width + 3 * PlayerStandingsStrip.GAP, PlayerStandingsStrip.CHIP_HEIGHT + 14)
	for _, chip in self.Chips do
		chip.Frame.Size = UDim2.fromOffset(width, PlayerStandingsStrip.CHIP_HEIGHT)
	end
end

-- Portrait on the left with its place ("1st") and held-item badges on it, so the name and
-- the Crown / coin line get the whole right side even on a narrow chip.
local function newChip(self, id: string)
	local h = PlayerStandingsStrip.CHIP_HEIGHT
	local frame = Theme.glass(make("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(self.ChipWidth, h),
		Parent = self.Root,
	}), 18)
	local chip = { Frame = frame, Id = id }
	chip.Stroke = frame:FindFirstChildOfClass("UIStroke")
	chip.Portrait = make("ViewportFrame", {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.fromOffset(h - 12, h - 12),
		BackgroundColor3 = Theme.Glass.Deep,
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(210, 210, 210),
		LightColor = Color3.fromRGB(255, 244, 220),
		Parent = frame,
	}, { Theme.corner(999), Theme.stroke(Theme.Glass.Gold, 2) })
	chip.Name = make("TextLabel", {
		Position = UDim2.fromOffset(h + 6, 6),
		Size = UDim2.new(1, -(h + 10), 0, 28),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.Glass.Cream,
		Parent = frame,
	})
	chip.Stats = make("TextLabel", {
		Position = UDim2.fromOffset(h + 6, 38),
		Size = UDim2.new(1, -(h + 10), 0, 26),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.Glass.Gold,
		Parent = frame,
	})
	-- Place: a small pill across the bottom of the portrait
	chip.Place = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0, h / 2, 1, -1),
		Size = UDim2.fromOffset(40, 20),
		BackgroundColor3 = Theme.Glass.Deep,
		Font = Theme.TitleFont,
		TextSize = 16,
		TextColor3 = Theme.Glass.Cream,
		Parent = frame,
	}, { Theme.corner(10), Theme.stroke(Theme.Glass.Gold, 1) })
	-- Held item: a small badge on the portrait's top-right
	chip.Item = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(h - 14, 0),
		Size = UDim2.fromOffset(26, 22),
		BackgroundColor3 = Theme.Glass.Deep,
		Font = Theme.TitleFont,
		TextSize = 14,
		TextColor3 = Theme.Glass.Cream,
		Visible = false,
		Parent = frame,
	}, { Theme.corner(8), Theme.stroke(Theme.Glass.Gold, 1) })
	-- Active pointer under the chip
	chip.Pointer = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(24, 16),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 18,
		TextColor3 = Theme.Glass.Gold,
		Text = "▼",
		Visible = false,
		Parent = frame,
	})
	self.Chips[id] = chip
	return chip
end

function PlayerStandingsStrip:render(state, myId: string)
	local places = PlayerStandingsStrip.placements(state.Seats)
	local seen = {}
	for _, seat in state.Seats do
		seen[seat.Id] = true
		local chip = self.Chips[seat.Id] or newChip(self, seat.Id)
		local isTurn = seat.Id == state.TurnId
		local isMe = seat.Id == myId
		chip.Frame.LayoutOrder = seat.Order
		chip.Name.Text = if isMe then "YOU" else seat.Name
		chip.Stats.Text = if seat.OrderRolls and #seat.OrderRolls > 0
			then "Rolled " .. table.concat(seat.OrderRolls, ", ")
			else ("👑%d  💰%d"):format(seat.Collectibles, seat.Coins)
		chip.Place.Text = Theme.ordinal(places[seat.Id] or 4)
		chip.Place.TextColor3 = Theme.PlacementColors[places[seat.Id] or 4] or Theme.Glass.Cream
		chip.Place.Visible = not (seat.OrderRolls and #seat.OrderRolls > 0)
		local items = seat.Items or {}
		chip.Item.Visible = #items > 0
		chip.Item.Text = if #items > 0 then Theme.itemGlyph(items[1].Id) .. (if #items > 1 then "+" .. (#items - 1) else "") else ""
		chip.Item.Size = UDim2.fromOffset(if #items > 1 then 38 else 26, 22)
		-- Active player: thick gold edge, warmer fill and the pointer; you: a cream inner edge.
		chip.Stroke.Thickness = if isTurn then 4 else if isMe then 2.5 else 1.5
		chip.Stroke.Color = if isTurn then Theme.Glass.Gold elseif isMe then Theme.Glass.Cream else Theme.Glass.Gold
		chip.Frame.BackgroundColor3 = if isTurn then Color3.fromRGB(40, 120, 104) else Theme.Glass.Fill
		chip.Pointer.Visible = isTurn
		if chip.Character ~= seat.Character then
			chip.Character = seat.Character
			ActivePlayerPortrait.mount(chip.Portrait, seat.Character, "Head")
		end
	end
	for id, chip in self.Chips do
		if not seen[id] then
			chip.Frame:Destroy()
			self.Chips[id] = nil
		end
	end
end

return PlayerStandingsStrip
