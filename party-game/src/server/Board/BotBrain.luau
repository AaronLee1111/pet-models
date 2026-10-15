--[[
	BotBrain
	How bots play the board. Pure functions of what any player could see on screen (board,
	coins, Crown position, standings, round): bots never peek at upcoming dice or rewards.

	Difficulty profiles live in Config.Match.BotBehavior:
	  RandomChoice   chance a decision is made at random (Easy bots blunder a lot)
	  ItemUseChance  chance a bot actually uses an item it has a good reason to use
	  SaveFactor     share of the Crown price kept back before shopping
	  LookAhead      spaces scored down each fork branch (0 = pick at random)
	  CosmeticSpend  coins to spare before buying a cosmetic (they don't help win)

	Space and item values below are the tuning knobs for the "thinking" part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local BotBrain = {}

-- How much a bot likes landing on / passing each space type (scaled down with distance).
BotBrain.SpaceValue = { Gain = 3, Lose = -3, Event = 0.5, Reward = 3, Shop = 1, Neutral = 0 }
-- How much a bot wants each item in a shop.
BotBrain.ItemValue = { DoubleDice = 3, TripleDice = 4, CoinShield = 2, SwapTicket = 3, WarpToken = 2 }
local AVERAGE_ROLL = (Config.Board.DieSides + 1) / 2

function BotBrain.profile(difficulty: string?)
	return Config.Match.BotBehavior[difficulty or ""] or Config.Match.BotBehavior.Normal
end

local function isLastRound(match): boolean
	return match.Round >= match.Rounds
end

local function crownDistance(match, spaceId: number): number
	return match.Board:distance(spaceId, match.CollectibleSpace)
end

-- True if this seat has fewer collectibles than the leader.
local function isBehind(match, seat): boolean
	local mine = match:collectiblesOf(seat)
	for _, other in match.Seats do
		if match:collectiblesOf(other) > mine then
			return true
		end
	end
	return false
end

-- Paths -----------------------------------------------------------------------------------------

-- Score of heading down the branch that starts at `startId`.
function BotBrain.branchScore(match, seat, startId: number, profile): number
	local score = 0
	local id = startId
	for step = 0, profile.LookAhead - 1 do
		local space = match.Board:get(id)
		score += (BotBrain.SpaceValue[space.Type] or 0) * 0.85 ^ step
		id = space.Next[1]
	end
	-- The Crown matters most when you can (nearly) pay for it.
	local coins, price = match:coinsOf(seat), match.CollectiblePrice
	local weight = if coins >= price then 4 elseif coins >= price - 6 then 1.5 else 0.3
	local distance = math.min(crownDistance(match, startId), 20)
	return score + weight * (20 - distance) * 0.5
end

function BotBrain.choosePath(match, seat, spaces, profile): number
	if profile.LookAhead <= 0 then
		return match.Rng:NextInteger(1, #spaces)
	end
	local best, bestScore = 1, -math.huge
	for i, id in spaces do
		local score = BotBrain.branchScore(match, seat, id, profile)
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	return best
end

-- Shop ------------------------------------------------------------------------------------------

-- Coins a bot keeps back for the Crown before buying anything.
function BotBrain.reserve(match, seat, profile): number
	local reserve = match.CollectiblePrice * profile.SaveFactor
	if isLastRound(match) and crownDistance(match, seat.SpaceId) > 2 * AVERAGE_ROLL + 2 then
		reserve = 0 -- can't reach the Crown again anyway: spend
	end
	return reserve
end

function BotBrain.chooseShop(match, seat, offers, default: number, profile): number
	local coins = match:coinsOf(seat)
	local reserve = BotBrain.reserve(match, seat, profile)
	local best, bestValue = default, 0
	for i, offer in offers do
		local left = coins - offer.Price
		local value
		if offer.Kind == "Item" then
			value = if left >= reserve and #seat.Items < Config.Items.MaxHeld then BotBrain.ItemValue[offer.Id] or 1 else 0
		else
			value = if left >= reserve + profile.CosmeticSpend then 0.5 else 0
		end
		if value > bestValue then
			best, bestValue = i, value
		end
	end
	return best
end

-- Items -----------------------------------------------------------------------------------------

-- The opponent nearest the Crown (the best seat to swap into), and how many moves closer it is.
function BotBrain.bestSwap(match, seat)
	local own = crownDistance(match, seat.SpaceId)
	local target, targetDistance = nil, math.huge
	for _, other in match:opponentsOf(seat) do
		local distance = crownDistance(match, other.SpaceId)
		if distance < targetDistance then
			target, targetDistance = other, distance
		end
	end
	return target, own - targetDistance
end

--[[
	How much a bot wants to use item `id` right now (> 0 = worth using), and the target.
	To teach bots a new item, add a branch here.
]]
function BotBrain.itemScore(match, seat, id: string)
	local coins, price = match:coinsOf(seat), match.CollectiblePrice
	local canBuy = coins >= price
	local distance = crownDistance(match, seat.SpaceId)
	local late = isLastRound(match)
	local urgency = if isBehind(match, seat) then 1.3 else 1

	if id == "DoubleDice" or id == "TripleDice" then
		local dice = if id == "TripleDice" then 3 else 2
		if canBuy and distance > Config.Board.DieSides and distance <= Config.Board.DieSides * dice then
			return (3 + dice) * urgency
		end
		return if late then 1 else 0 -- use it up before the match ends
	elseif id == "CoinShield" then
		if seat.Shield then
			return 0
		end
		return if coins >= 6 then 2 elseif late and coins > 0 then 1 else 0
	elseif id == "SwapTicket" then
		local target, gain = BotBrain.bestSwap(match, seat)
		if target and gain >= 6 and coins >= price - 5 then
			return 4 * urgency, target
		end
		return (if late and target and gain > 0 then 0.5 else 0), target
	elseif id == "WarpToken" then
		if distance >= 14 then
			return 2 * urgency
		end
		return if late then 0.5 else 0
	end
	return 0
end

-- Returns slot, target (seat or nil) of the item to use this turn, or nil.
function BotBrain.chooseItem(match, seat, profile)
	if #seat.Items == 0 then
		return nil
	end
	local rng = match.Rng
	if rng:NextNumber() < profile.RandomChoice then
		if rng:NextNumber() < 0.5 then
			return nil
		end
		local slot = rng:NextInteger(1, #seat.Items)
		local opponents = match:opponentsOf(seat)
		return slot, opponents[rng:NextInteger(1, #opponents)]
	end
	local bestSlot, bestScore, bestTarget = nil, 0, nil
	for slot, id in seat.Items do
		local score, target = BotBrain.itemScore(match, seat, id)
		if score > bestScore then
			bestSlot, bestScore, bestTarget = slot, score, target
		end
	end
	if bestSlot and rng:NextNumber() < profile.ItemUseChance then
		return bestSlot, bestTarget
	end
	return nil
end

-- Ask requests ----------------------------------------------------------------------------------

function BotBrain.decide(match, seat, request, profile, _skill: number): number
	local count = #request.Options
	if count > 1 and match.Rng:NextNumber() < profile.RandomChoice then
		return match.Rng:NextInteger(1, count)
	end
	if request.Kind == "Collectible" then
		return 1 -- always buy: it's what wins
	elseif request.Kind == "Path" and request.Data and request.Data.Spaces then
		return BotBrain.choosePath(match, seat, request.Data.Spaces, profile)
	elseif request.Kind == "Shop" and request.Data and request.Data.Items then
		return BotBrain.chooseShop(match, seat, request.Data.Items, request.Default, profile)
	elseif request.Kind == "Target" and request.Data and request.Data.Seats then
		local target = BotBrain.bestSwap(match, seat)
		return table.find(request.Data.Seats, target) or 1
	end
	return request.Default or 1
end

return BotBrain
