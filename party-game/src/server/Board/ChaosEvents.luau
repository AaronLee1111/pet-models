--[[
	ChaosEvents
	What can happen on a Chaos space: mostly harmful or disruptive, occasionally lucky.
	Same shape as Events: { Id, Name, Weight, Apply(match, seat, rng) -> feed text }.

	Losses are capped (Config.Economy.ChaosLossCap) and a Coin Shield blocks a coin loss, so
	one bad landing can hurt but can't wipe anyone out.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

return {
	{
		Id = "Thunderclap",
		Name = "Thunderclap",
		Weight = 3,
		Apply = function(match, seat)
			local loss = math.min(math.ceil(match:coinsOf(seat) / 2), Config.Economy.ChaosLossCap)
			local delta, shielded = match:changeCoins(seat, -loss)
			if shielded then
				return ("%s's Coin Shield took the hit and broke"):format(seat.Participant.Name)
			end
			return ("%s lost %d coins"):format(seat.Participant.Name, -delta)
		end,
	},
	{
		Id = "TaxDay",
		Name = "Tax Day",
		Weight = 2,
		Apply = function(match)
			for _, each in match.Seats do
				match:changeCoins(each, -3)
			end
			return "Everyone pays 3 coins (shields block it)"
		end,
	},
	{
		Id = "Shuffle",
		Name = "Shuffle",
		Weight = 2,
		Apply = function(match, _seat, rng)
			local spaces = {}
			for _, each in match.Seats do
				table.insert(spaces, each.SpaceId)
			end
			for i = #spaces, 2, -1 do
				local j = rng:NextInteger(1, i)
				spaces[i], spaces[j] = spaces[j], spaces[i]
			end
			for i, each in match.Seats do
				each.SpaceId = spaces[i]
			end
			return "Everyone's pieces were shuffled around the board"
		end,
	},
	{
		Id = "BagSwap",
		Name = "Bag Swap",
		Weight = 1,
		Apply = function(match, seat, rng)
			local others = match:opponentsOf(seat)
			local other = others[rng:NextInteger(1, #others)]
			seat.Items, other.Items = other.Items, seat.Items
			return ("%s and %s swapped item bags"):format(seat.Participant.Name, other.Participant.Name)
		end,
	},
	{
		Id = "PriceSurge",
		Name = "Price Surge",
		Weight = 1,
		Apply = function(match)
			local cap = Config.Collectible.Price + Config.Economy.PriceSurgeCap
			match.CollectiblePrice = math.min(match.CollectiblePrice + 5, cap)
			return ("The %s now costs %d coins (until someone buys it)"):format(match.CollectibleName, match.CollectiblePrice)
		end,
	},
	{
		Id = "LuckyBreak",
		Name = "Lucky Break",
		Weight = 1,
		Apply = function(match, seat)
			local delta = match:changeCoins(seat, 8)
			return ("Chaos smiles on %s: +%d coins"):format(seat.Participant.Name, delta)
		end,
	},
}
