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
	  Choice       optional: "DieFace" = the user picks a number 1..DieSides
	  Boards       optional: list of board names this item appears on (board-specific items)
	  Use          function(match, seat, target, choice) -> feed text, or nil + reason to refuse
	               (a refusal keeps the item in the user's inventory)

	Counterplay: a Coin Shield blocks the next coin loss, coin steal, trap or Crown Heist.

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
	{
		Id = "LuckyDie",
		Name = "Lucky Die",
		Description = "Pick your roll",
		Price = 9,
		Weight = 2,
		Choice = "DieFace",
		Use = function(match, seat, _target, face)
			match.Turn.Fixed = face
			return ("%s will move exactly %d"):format(seat.Participant.Name, face)
		end,
	},
	{
		Id = "Pickpocket",
		Name = "Pickpocket",
		Description = "Take up to 6 coins from an opponent",
		Price = 7,
		Weight = 2,
		Target = "Opponent",
		Use = function(match, seat, target)
			if match:coinsOf(target) == 0 then
				return nil, "they have no coins"
			end
			local taken, blocked = match:stealCoins(seat, target, 6)
			if blocked then
				return ("%s's Coin Shield stopped %s's pickpocket"):format(target.Participant.Name, seat.Participant.Name)
			end
			return ("%s pickpocketed %d coins from %s"):format(seat.Participant.Name, taken, target.Participant.Name)
		end,
	},
	{
		Id = "CrownHeist",
		Name = "Crown Heist",
		Description = "Pay 15 coins to take a Crown from an opponent (a Coin Shield stops it)",
		Price = 25,
		Weight = 0.4,
		Target = "Opponent",
		Fee = 15,
		Use = function(match, seat, target)
			local result, reason = match:stealCollectible(seat, target, 15)
			if not result then
				return nil, reason
			elseif result == "blocked" then
				return ("%s's Coin Shield stopped %s's Crown Heist"):format(target.Participant.Name, seat.Participant.Name)
			end
			return ("%s stole a %s from %s!"):format(seat.Participant.Name, match.CollectibleName, target.Participant.Name)
		end,
	},
	{
		Id = "Snare",
		Name = "Snare Trap",
		Description = "Trap your space: the next opponent to land there pays you 5 coins",
		Price = 5,
		Weight = 2,
		Use = function(match, seat)
			if not match:setTrap(seat, 5) then
				return nil, "there's already a trap here"
			end
			return ("%s set a trap"):format(seat.Participant.Name)
		end,
	},
}
