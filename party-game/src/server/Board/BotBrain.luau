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
local Bridge = require(script.Parent.RotatingBridge)

local BotBrain = {}

-- How much a bot likes landing on / passing each space type (scaled down with distance).
BotBrain.SpaceValue = {
	Gain = 3,
	Lose = -3,
	Event = 0.5,
	Reward = 3,
	Shop = 1,
	Neutral = 0,
	Item = 2,
	Duel = 0.5,
	Chaos = -2,
	Switch = 0.5,
}
-- How much a bot wants each item in a shop.
BotBrain.ItemValue = {
	DoubleDice = 3,
	TripleDice = 4,
	CoinShield = 2,
	SwapTicket = 3,
	WarpToken = 2,
	LuckyDie = 3,
	Pickpocket = 2,
	CrownHeist = 4,
	Snare = 1,
	GateKey = 2,
	MoonDial = 4,
}
-- Items an opponent could hurt you with; a bot that sees one in an opponent's (public)
-- inventory values its own Coin Shield more.
BotBrain.Threats = { Pickpocket = true, CrownHeist = true }
local AVERAGE_ROLL = (Config.Board.DieSides + 1) / 2

function BotBrain.profile(difficulty: string?)
	return Config.Match.BotBehavior[difficulty or ""] or Config.Match.BotBehavior.Normal
end

local function isLastRound(match): boolean
	return match.Round >= match.Rounds
end

local function crownDistance(match, spaceId: number): number
	return match:distance(spaceId, match.CollectibleSpace)
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
		id = match:nextOptions(id)[1]
	end
	-- The Crown matters most when you can (nearly) pay for it.
	local coins, price = match:coinsOf(seat), match:collectiblePriceFor(seat)
	local weight = if coins >= price then 4 elseif coins >= price - 6 then 1.5 else 0.3
	local distance = math.min(crownDistance(match, startId), 20)
	return score + weight * (20 - distance) * 0.5
end

function BotBrain.choosePath(match, seat, spaces, profile, info): number
	if profile.LookAhead <= 0 then
		return match.Rng:NextInteger(1, #spaces)
	end
	local best, bestScore = 1, -math.huge
	for i, id in spaces do
		local toll = info and info[i] and info[i].Toll or 0
		local score = BotBrain.branchScore(match, seat, id, profile) - toll * 0.5
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	return best
end

-- Shop ------------------------------------------------------------------------------------------

-- Coins a bot keeps back for the Crown before buying anything.
function BotBrain.reserve(match, seat, profile): number
	local reserve = match:collectiblePriceFor(seat) * profile.SaveFactor
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

-- Is any opponent holding an item that could steal from this seat?
function BotBrain.threatened(match, seat): boolean
	for _, other in match:opponentsOf(seat) do
		for _, id in other.Items do
			if BotBrain.Threats[id] then
				return true
			end
		end
	end
	return false
end

-- The opponent worth robbing: most of `stat` ("Coins" or "Collectibles"), not shielded.
function BotBrain.bestVictim(match, seat, stat: string)
	local best, bestValue = nil, 0
	for _, other in match:opponentsOf(seat) do
		local value = if stat == "Coins" then match:coinsOf(other) else match:collectiblesOf(other)
		if not other.Shield and value > bestValue then
			best, bestValue = other, value
		end
	end
	return best, bestValue
end

-- The die face that lands on the most useful space straight ahead (ignores forks).
function BotBrain.bestFace(match, seat): (number, number)
	local bestFace, bestValue = 1, -math.huge
	local id = seat.SpaceId
	for face = 1, Config.Board.DieSides do
		id = match:nextOptions(id)[1]
		local value = BotBrain.SpaceValue[match.Board:get(id).Type] or 0
		if value > bestValue then
			bestFace, bestValue = face, value
		end
	end
	return bestFace, bestValue
end

--[[
	How much a bot wants to use item `id` right now (> 0 = worth using), plus the target seat
	and die-face choice where the item needs them. To teach bots a new item, add a branch here.
]]
function BotBrain.itemScore(match, seat, id: string)
	local coins, price = match:coinsOf(seat), match:collectiblePriceFor(seat)
	local canBuy = coins >= price
	local distance = crownDistance(match, seat.SpaceId)
	local late = isLastRound(match)
	local urgency = if isBehind(match, seat) then 1.3 else 1

	if id == "MoonDial" then
  if not match:canUseMoonDial() then return 0 end
  local nextOrientation=1-match.Orientation
  local crown=match.CollectibleSpace
  local zone=match.Board:get(crown).Zone
  local after
  if zone~=0 and not Bridge.connected(zone,nextOrientation) then
   -- The Crown would move to one of the newly reachable zone spaces; a bot can't know which,
   -- so it plans on the average distance to them (or the bridge fallback).
   local candidates=match:crownCandidates(nextOrientation)
   if #candidates==0 then candidates={34} end
   local total=0
   for _,id in candidates do total+=math.min(match:distanceAt(seat.SpaceId,id,nextOrientation),40) end
   after=total/#candidates
  else
   after=match:distanceAt(seat.SpaceId,crown,nextOrientation)
  end
  local before=math.min(distance,40)
  local score=if canBuy and after+3<before then (before-after)*0.3 else 0
  for _,other in match:opponentsOf(seat) do
   if match:collectiblesOf(other)>match:collectiblesOf(seat) and match:coinsOf(other)>=price
    and crownDistance(match,other.SpaceId)<=6 and match:distanceAt(other.SpaceId,crown,nextOrientation)>12 then score+=2 end
  end
  -- Saving the item is preferable when the next automatic rotation already opens
  -- our zone and we cannot reach its dock on this roll.
  local dock=(math.max(1,match.Board:get(seat.SpaceId).Zone)-1)*8+1
  if distance==math.huge and match:distance(seat.SpaceId,dock)>Config.Board.DieSides then score=0 end
  return score
 elseif id == "DoubleDice" or id == "TripleDice" then
		local dice = if id == "TripleDice" then 3 else 2
		if canBuy and distance > Config.Board.DieSides and distance <= Config.Board.DieSides * dice then
			return (3 + dice) * urgency
		end
		return if late then 1 else 0 -- use it up before the match ends
	elseif id == "CoinShield" then
		if seat.Shield then
			return 0
		end
		if BotBrain.threatened(match, seat) and (coins >= 6 or match:collectiblesOf(seat) > 0) then
			return 5 -- someone is holding a steal: block it first
		end
		return if coins >= 6 then 2 elseif late and coins > 0 then 1 else 0
	elseif id == "LuckyDie" then
		if canBuy and distance >= 1 and distance <= Config.Board.DieSides then
			return 7, nil, distance -- land exactly on the Crown
		end
		local face, value = BotBrain.bestFace(match, seat)
		return (if value >= 3 then 1 elseif late then 0.5 else 0), nil, face
	elseif id == "Pickpocket" then
		local victim, theirCoins = BotBrain.bestVictim(match, seat, "Coins")
		if victim and theirCoins >= 3 then
			return math.min(theirCoins, 6) / 2 * urgency, victim
		end
		return 0
	elseif id == "CrownHeist" then
		local victim, crowns = BotBrain.bestVictim(match, seat, "Collectibles")
		if victim and crowns >= 1 and coins >= 15 then
			return 8 * urgency, victim
		end
		return 0
	elseif id == "Snare" then
		return if match.Traps[seat.SpaceId] then 0 else 1
	elseif id == "GateKey" then
		-- Same reasoning as a Switch space: flip only if it brings the Crown closer.
		local now = distance
		match:toggleGates()
		local flipped = crownDistance(match, seat.SpaceId)
		match:toggleGates()
		return if flipped + 3 <= now then 3 * urgency else 0
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

-- Returns slot, target (seat or nil) and choice (die face or nil) of the item to use, or nil.
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
		return slot, opponents[rng:NextInteger(1, #opponents)], rng:NextInteger(1, Config.Board.DieSides)
	end
	local bestSlot, bestScore, bestTarget, bestChoice = nil, 0, nil, nil
	for slot, id in seat.Items do
		local score, target, choice = BotBrain.itemScore(match, seat, id)
		if score > bestScore then
			bestSlot, bestScore, bestTarget, bestChoice = slot, score, target, choice
		end
	end
	if bestSlot and rng:NextNumber() < profile.ItemUseChance then
		return bestSlot, bestTarget, bestChoice
	end
	return nil
end

-- Switch space ------------------------------------------------------------------------------------

-- Flip the gates if that brings the Crown closer; pay to move the Crown if an opponent is about
-- to reach it and this bot can't; otherwise leave the board alone.
function BotBrain.chooseSwitch(match, seat, actions, _profile): number
	local leave = table.find(actions, "None") or #actions
	local gatesIndex = table.find(actions, "Gates")
	if gatesIndex then
		local now = crownDistance(match, seat.SpaceId)
		match:toggleGates()
		local flipped = crownDistance(match, seat.SpaceId)
		match:toggleGates() -- put them back: this was only a look
		if flipped + 3 <= now then
			return gatesIndex
		end
	end
	local crownIndex = table.find(actions, "Crown")
	if crownIndex then
		local mine = crownDistance(match, seat.SpaceId)
		for _, other in match:opponentsOf(seat) do
			if crownDistance(match, other.SpaceId) <= 4 and match:coinsOf(other) >= match.CollectiblePrice and mine > 6 then
				return crownIndex
			end
		end
	end
	return leave
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
		return BotBrain.choosePath(match, seat, request.Data.Spaces, profile, request.Data.Info)
	elseif request.Kind == "Shop" and request.Data and request.Data.Items then
		return BotBrain.chooseShop(match, seat, request.Data.Items, request.Default, profile)
	elseif request.Kind == "Target" and request.Data and request.Data.Seats then
		local target = BotBrain.bestSwap(match, seat)
		return table.find(request.Data.Seats, target) or 1
	elseif request.Kind == "DieFace" then
		return (BotBrain.bestFace(match, seat))
	elseif request.Kind == "DuelTarget" and request.Data and request.Data.Seats then
		-- Challenge whoever is ahead (or richest): a win there helps the most.
		local best, bestScore = 1, -math.huge
		for i, other in request.Data.Seats do
			local score = match:collectiblesOf(other) * 100 + match:coinsOf(other)
			if score > bestScore then
				best, bestScore = i, score
			end
		end
		return best
	elseif request.Kind == "DuelStake" and request.Data and request.Data.Stakes then
		-- A die duel is a coin flip: bots that are behind gamble big, leaders play it safe.
		return if isBehind(match, seat) then #request.Data.Stakes else 1
	elseif request.Kind == "Switch" and request.Data and request.Data.Actions then
		return BotBrain.chooseSwitch(match, seat, request.Data.Actions, profile)
	end
	return request.Default or 1
end

return BotBrain
