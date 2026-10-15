--[[
	SpaceTypes
	What every kind of board space looks like and does. Board layouts refer to these by key.

	Each type:
	  Name      shown in the legend / landing toast
	  Short     a few characters drawn on the tile
	  Color     tile colour
	  Resolve   function(match, seat, space) -> string?  runs when a piece LANDS here
	            (passing over a space does nothing). Return a short line for the feed.
	            Use the match helpers: changeCoins, runEvent, giveReward, visitShop.

	To add a type: add an entry here, then use its key in a board's Spaces.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local function coinsText(name: string, delta: number, shielded: boolean?): string
	if shielded then
		return ("%s's Coin Shield blocked the loss and broke"):format(name)
	elseif delta == 0 then
		return ("%s has no coins to lose"):format(name)
	end
	return ("%s %s %d coins"):format(name, if delta > 0 then "gets" else "loses", math.abs(delta))
end

return {
	Neutral = {
		Name = "Plain space",
		Short = "",
		Color = Color3.fromRGB(200, 200, 215),
		Resolve = function()
			return nil
		end,
	},
	Gain = {
		Name = "Coin space",
		Short = "+" .. Config.Economy.GainSpaceCoins,
		Color = Color3.fromRGB(70, 140, 255),
		Resolve = function(match, seat)
			return coinsText(seat.Participant.Name, match:changeCoins(seat, Config.Economy.GainSpaceCoins))
		end,
	},
	Lose = {
		Name = "Ouch space",
		Short = "-" .. Config.Economy.LoseSpaceCoins,
		Color = Color3.fromRGB(240, 70, 70),
		Resolve = function(match, seat)
			local delta, shielded = match:changeCoins(seat, -Config.Economy.LoseSpaceCoins)
			return coinsText(seat.Participant.Name, delta, shielded)
		end,
	},
	Event = {
		Name = "Event space",
		Short = "?",
		Color = Color3.fromRGB(80, 200, 110),
		Resolve = function(match, seat)
			return match:runEvent(seat)
		end,
	},
	Shop = {
		Name = "Shop",
		Short = "SHOP",
		Color = Color3.fromRGB(170, 90, 230),
		Resolve = function(match, seat)
			return match:visitShop(seat)
		end,
	},
	Reward = {
		Name = "Gift space",
		Short = "GIFT",
		Color = Color3.fromRGB(255, 190, 40),
		Resolve = function(match, seat)
			return match:giveReward(seat)
		end,
	},
}
