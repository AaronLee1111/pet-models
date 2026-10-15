--[[
	Items
	Board items. A seat holds up to Config.Items.MaxHeld and may use one per turn, before
	rolling. Match:useItem checks ownership, timing and the target, then calls Use.

	Each item:
	  Id           unique, never rename
	  Name         shown to players
	  Description  one line for the item buttons / shop
	  Price        coins at a shop
	  Weight       relative chance in gifts, events and shop offers
	  Dice         optional: roll this many dice this turn instead of one
	  Target       optional: "Opponent" = the user picks another seat
	  Use          function(match, seat, target) -> feed text, or nil + reason to refuse
	               (a refusal keeps the item in the user's inventory)

	To add an item: append an entry here. Teach bots when to use it in BotBrain.itemScore.
]]

return {
	{
		Id = "DoubleDice",
		Name = "Double Dice",
		Description = "Roll two dice and move the total",
		Price = 6,
		Weight = 3,
		Dice = 2,
		Use = function(_match, seat)
			return ("%s will roll two dice!"):format(seat.Participant.Name)
		end,
	},
	{
		Id = "TripleDice",
		Name = "Triple Dice",
		Description = "Roll three dice and move the total",
		Price = 10,
		Weight = 1,
		Dice = 3,
		Use = function(_match, seat)
			return ("%s will roll three dice!"):format(seat.Participant.Name)
		end,
	},
	{
		Id = "CoinShield",
		Name = "Coin Shield",
		Description = "Blocks the next coin loss, then breaks",
		Price = 5,
		Weight = 2,
		Use = function(_match, seat)
			if seat.Shield then
				return nil, "already shielded"
			end
			seat.Shield = true
			return ("%s raised a Coin Shield"):format(seat.Participant.Name)
		end,
	},
	{
		Id = "SwapTicket",
		Name = "Swap Ticket",
		Description = "Swap places with an opponent you pick",
		Price = 8,
		Weight = 2,
		Target = "Opponent",
		Use = function(_match, seat, target)
			seat.SpaceId, target.SpaceId = target.SpaceId, seat.SpaceId
			return ("%s swapped places with %s"):format(seat.Participant.Name, target.Participant.Name)
		end,
	},
	{
		Id = "WarpToken",
		Name = "Warp Token",
		Description = "Jump to a random space",
		Price = 6,
		Weight = 2,
		Use = function(match, seat)
			local options = {}
			for _, id in match.Board.Order do
				if id ~= seat.SpaceId then
					table.insert(options, id)
				end
			end
			seat.SpaceId = options[match.Rng:NextInteger(1, #options)]
			return ("%s warped to a random space"):format(seat.Participant.Name)
		end,
	},
}
