--[[
	Events
	What can happen on an Event space. One is picked at random by Weight.

	Each event:
	  Id       unique
	  Name     headline shown to everyone
	  Weight   relative chance
	  Apply    function(match, seat, rng) -> string   does the thing, returns the feed line

	Board pieces that change space here are moved in the world by BoardGame afterwards.
	To add an event: append an entry. Keep the numbers here so they're easy to tune.
]]

local function others(match, seat)
	local list = {}
	for _, other in match.Seats do
		if other ~= seat then
			table.insert(list, other)
		end
	end
	return list
end

return {
	{
		Id = "LuckyFind",
		Name = "Lucky Find",
		Weight = 3,
		Apply = function(match, seat)
			local delta = match:changeCoins(seat, 5)
			return ("%s found %d coins on the ground"):format(seat.Participant.Name, delta)
		end,
	},
	{
		Id = "PartyBus",
		Name = "Party Bus",
		Weight = 2,
		Apply = function(match)
			for _, each in match.Seats do
				match:changeCoins(each, 2)
			end
			return "Everyone gets 2 coins"
		end,
	},
	{
		Id = "LeakyPocket",
		Name = "Leaky Pocket",
		Weight = 2,
		Apply = function(match, seat)
			local delta, shielded = match:changeCoins(seat, -5)
			if shielded then
				return ("%s's Coin Shield saved their coins and broke"):format(seat.Participant.Name)
			end
			return ("%s dropped %d coins"):format(seat.Participant.Name, -delta)
		end,
	},
	{
		Id = "SwapSpots",
		Name = "Swap Spots",
		Weight = 2,
		Apply = function(match, seat, rng)
			local candidates = others(match, seat)
			local other = candidates[rng:NextInteger(1, #candidates)]
			seat.SpaceId, other.SpaceId = other.SpaceId, seat.SpaceId
			return ("%s swapped places with %s"):format(seat.Participant.Name, other.Participant.Name)
		end,
	},
	{
		Id = "HelpingHand",
		Name = "Helping Hand",
		Weight = 1,
		Apply = function(match)
			local richest, poorest = match.Seats[1], match.Seats[1]
			for _, each in match.Seats do
				if match:coinsOf(each) > match:coinsOf(richest) then
					richest = each
				end
				if match:coinsOf(each) < match:coinsOf(poorest) then
					poorest = each
				end
			end
			if richest == poorest or match:coinsOf(richest) == match:coinsOf(poorest) then
				return "Everyone has the same coins, so nothing happens"
			end
			local taken, shielded = match:changeCoins(richest, -5)
			if shielded then
				return ("%s's Coin Shield kept their coins and broke"):format(richest.Participant.Name)
			end
			local given = -taken
			match:changeCoins(poorest, given)
			return ("%s gives %d coins to %s"):format(richest.Participant.Name, given, poorest.Participant.Name)
		end,
	},
	{
		Id = "CollectibleMoves",
		Name = "On the Move",
		Weight = 1,
		Apply = function(match)
			match:relocateCollectible()
			return ("The %s moved to a new space!"):format(match.CollectibleName)
		end,
	},
	{
		Id = "ItemDrop",
		Name = "Item Drop",
		Weight = 2,
		Apply = function(match, seat)
			local item = match:giveRandomItem(seat)
			if not item then
				return ("%s's bag is full, so the item rolls away"):format(seat.Participant.Name)
			end
			return ("%s picked up a %s"):format(seat.Participant.Name, item.Name)
		end,
	},
	{
		Id = "Warp",
		Name = "Warp",
		Weight = 1,
		Apply = function(match, seat, rng)
			local order = match.Board.Order
			seat.SpaceId = order[rng:NextInteger(1, #order)]
			return ("%s warped across the board"):format(seat.Participant.Name)
		end,
	},
}
