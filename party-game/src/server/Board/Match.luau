--[[
	Match
	The rules of one board-game match, with no networking, timing or world in it, so it can
	be tested on its own. BoardGame drives it and draws the results.

	  Match.new(board, participants, settings, deps)
	    settings  { Rounds }
	    deps      {
	      Wallet     CoinService-like: get, add, spend, getCollectibles, addCollectibles, transfer
	      Inventory  Inventory-like: grant, equip, getEquipped, unowned
	      Rng        Random
	      Ask        function(seat, request) -> option index; may yield. request =
	                 { Kind = "Path"|"Collectible"|"Shop", Prompt, Options = {labels}, Default, Data }
	    }

	A seat: { Index, Participant, SpaceId }. Seats keep their place in the turn order even
	when a bot takes over from a player who left (replaceParticipant).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local Events = require(script.Parent.Events)
local SpaceTypes = require(script.Parent.SpaceTypes)

local Match = {}
Match.__index = Match

local function weightedPick(rng: Random, list)
	local total = 0
	for _, entry in list do
		total += entry.Weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in list do
		roll -= entry.Weight
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

function Match.new(board, participants, settings, deps)
	local self = setmetatable({
		Board = board,
		Deps = deps,
		Rng = deps.Rng or Random.new(),
		Rounds = settings.Rounds or Config.Match.BoardRounds,
		Round = 0,
		Seats = {},
		Order = {},
		CollectibleSpace = nil,
		CollectibleName = Config.Collectible.Name,
		CollectiblePrice = Config.Collectible.Price,
	}, Match)

	for index, participant in participants do
		local seat = { Index = index, Participant = participant, SpaceId = board.Start }
		table.insert(self.Seats, seat)
		table.insert(self.Order, seat)
	end
	-- Random turn order, fixed for the whole match.
	for i = #self.Order, 2, -1 do
		local j = self.Rng:NextInteger(1, i)
		self.Order[i], self.Order[j] = self.Order[j], self.Order[i]
	end
	self:relocateCollectible()
	return self
end

function Match:participants()
	local list = {}
	for _, seat in self.Seats do
		table.insert(list, seat.Participant)
	end
	return list
end

function Match:seatOf(participant)
	for _, seat in self.Seats do
		if seat.Participant == participant then
			return seat
		end
	end
	return nil
end

function Match:coinsOf(seat): number
	return self.Deps.Wallet.get(seat.Participant)
end

function Match:collectiblesOf(seat): number
	return self.Deps.Wallet.getCollectibles(seat.Participant)
end

-- Adds/removes coins (never below 0). Returns the change that actually happened.
function Match:changeCoins(seat, amount: number): number
	local _, delta = self.Deps.Wallet.add(seat.Participant, amount)
	return delta
end

function Match:roll(): number
	return self.Rng:NextInteger(1, Config.Board.DieSides)
end

function Match:ask(seat, request): number
	local pick = self.Deps.Ask(seat, request)
	if type(pick) ~= "number" or pick % 1 ~= 0 or pick < 1 or pick > #request.Options then
		return request.Default or 1
	end
	return pick
end

-- Collectible --------------------------------------------------------------------------------

-- Moves the collectible to a different allowed space, avoiding occupied ones when possible.
function Match:relocateCollectible()
	local candidates, free = {}, {}
	local occupied = {}
	for _, seat in self.Seats do
		occupied[seat.SpaceId] = true
	end
	for _, id in self.Board.CrownSpaces do
		if id ~= self.CollectibleSpace then
			table.insert(candidates, id)
			if not occupied[id] then
				table.insert(free, id)
			end
		end
	end
	local pool = if #free > 0 then free else candidates
	self.CollectibleSpace = pool[self.Rng:NextInteger(1, #pool)]
	return self.CollectibleSpace
end

-- Pays for the collectible. Returns true if bought (and moves it).
function Match:buyCollectible(seat): boolean
	if not self.Deps.Wallet.spend(seat.Participant, self.CollectiblePrice) then
		return false
	end
	self.Deps.Wallet.addCollectibles(seat.Participant, 1)
	self:relocateCollectible()
	return true
end

-- Reached the collectible's space (passing or landing): offer it if affordable.
function Match:offerCollectible(seat): string
	local name = seat.Participant.Name
	if self:coinsOf(seat) < self.CollectiblePrice then
		return ("%s needs %d coins for a %s"):format(name, self.CollectiblePrice, self.CollectibleName)
	end
	local pick = self:ask(seat, {
		Kind = "Collectible",
		Prompt = ("Buy a %s for %d coins?"):format(self.CollectibleName, self.CollectiblePrice),
		Options = { "Buy", "Not now" },
		Default = 1,
	})
	if pick == 1 and self:buyCollectible(seat) then
		return ("%s bought a %s!"):format(name, self.CollectibleName)
	end
	return ("%s passed on the %s"):format(name, self.CollectibleName)
end

-- Movement ------------------------------------------------------------------------------------

-- One space forward. At a fork the mover chooses.
function Match:step(seat): number
	local options = self.Board:nextOptions(seat.SpaceId)
	local nextId = options[1]
	if #options > 1 then
		local space = self.Board:get(seat.SpaceId)
		local labels = {}
		for i, id in options do
			labels[i] = if space.Paths then space.Paths[i] else ("Space %d"):format(id)
		end
		nextId = options[self:ask(seat, { Kind = "Path", Prompt = "Which way?", Options = labels, Default = 1 })]
	end
	seat.SpaceId = nextId
	return nextId
end

--[[
	Moves `steps` spaces, then resolves the landing space.
	onHop(seat, spaceId, remaining) runs after every hop (BoardGame animates there).
	onNotice(text) receives anything worth telling everyone on the way (collectible offers).
	Returns the feed line for the landing (may be nil).
]]
function Match:move(seat, steps: number, onHop, onNotice)
	for remaining = steps - 1, 0, -1 do
		local id = self:step(seat)
		if onHop then
			onHop(seat, id, remaining)
		end
		if id == self.CollectibleSpace then
			local text = self:offerCollectible(seat)
			if onNotice then
				onNotice(text)
			end
		end
	end
	return self:land(seat)
end

function Match:land(seat): string?
	local space = self.Board:get(seat.SpaceId)
	local spaceType = SpaceTypes[space.Type]
	return spaceType.Resolve(self, seat, space)
end

-- Space helpers (used by SpaceTypes / Events) ---------------------------------------------------

function Match:runEvent(seat): string
	local event = weightedPick(self.Rng, Events)
	return ("%s: %s"):format(event.Name, event.Apply(self, seat, self.Rng))
end

function Match:grantCosmetic(seat, itemId: string): boolean
	local ownerId = seat.Participant.Id
	if not self.Deps.Inventory.grant(ownerId, itemId) then
		return false
	end
	local item = Cosmetics.get(itemId)
	if not self.Deps.Inventory.getEquipped(ownerId)[item.Slot] then
		self.Deps.Inventory.equip(ownerId, itemId) -- first item in a slot goes straight on
	end
	return true
end

function Match:giveReward(seat): string
	local name = seat.Participant.Name
	local reward = weightedPick(self.Rng, Config.Economy.Rewards)
	if reward.Kind == "Cosmetic" then
		local unowned = self.Deps.Inventory.unowned(seat.Participant.Id)
		if #unowned > 0 then
			local item = unowned[self.Rng:NextInteger(1, #unowned)]
			self:grantCosmetic(seat, item.Id)
			return ("%s unwrapped a %s!"):format(name, item.Name)
		end
		reward = { Kind = "Coins", Amount = 5 } -- owns everything already
	end
	if reward.Kind == "Collectible" then
		self.Deps.Wallet.addCollectibles(seat.Participant, reward.Amount)
		return ("%s unwrapped a %s!"):format(name, self.CollectibleName)
	end
	local delta = self:changeCoins(seat, reward.Amount)
	return ("%s unwrapped %d coins"):format(name, delta)
end

function Match:visitShop(seat): string
	local name = seat.Participant.Name
	local unowned = self.Deps.Inventory.unowned(seat.Participant.Id)
	if #unowned == 0 then
		return ("%s already owns everything in the shop"):format(name)
	end
	local offers = {}
	for _ = 1, math.min(Config.Economy.ShopOffers, #unowned) do
		local item = table.remove(unowned, self.Rng:NextInteger(1, #unowned))
		table.insert(offers, item)
	end
	local labels = {}
	for i, item in offers do
		labels[i] = ("%s (%d coins)"):format(item.Name, item.Price)
	end
	table.insert(labels, "Leave")
	local pick = self:ask(seat, {
		Kind = "Shop",
		Prompt = "Shop: buy a cosmetic?",
		Options = labels,
		Default = #labels,
		Data = { Items = offers },
	})
	local item = offers[pick]
	if not item then
		return ("%s left the shop"):format(name)
	end
	if not self.Deps.Wallet.spend(seat.Participant, item.Price) then
		return ("%s can't afford the %s"):format(name, item.Name)
	end
	self:grantCosmetic(seat, item.Id)
	return ("%s bought a %s"):format(name, item.Name)
end

-- Seats -----------------------------------------------------------------------------------------

-- A bot takes over a seat (its player left). Coins and collectibles carry over.
function Match:replaceParticipant(seat, newParticipant)
	self.Deps.Wallet.transfer(seat.Participant, newParticipant)
	seat.Participant = newParticipant
end

-- Bots ------------------------------------------------------------------------------------------

-- What a bot picks for an Ask request. `skill` is 0..1.
function Match:botDecision(seat, request, skill: number): number
	if request.Kind == "Collectible" then
		return 1 -- always buy: it's what wins
	elseif request.Kind == "Shop" then
		local coins = self:coinsOf(seat)
		-- Better bots keep enough coins for the collectible.
		local reserve = Config.Economy.BotShopReserve * skill
		for i, item in request.Data.Items do
			if coins - item.Price >= reserve then
				return i
			end
		end
		return request.Default
	elseif request.Kind == "Path" then
		return self.Rng:NextInteger(1, #request.Options)
	end
	return request.Default or 1
end

-- Standings -------------------------------------------------------------------------------------

--[[
	Ranks rows { Participant, Collectibles, Coins, ... }: most collectibles first, coins break
	ties, and rows equal on both share a placement. Returns a new sorted list with Placement set.
]]
function Match.rank(rows)
	local sorted = table.clone(rows)
	table.sort(sorted, function(a, b)
		if a.Collectibles ~= b.Collectibles then
			return a.Collectibles > b.Collectibles
		end
		if a.Coins ~= b.Coins then
			return a.Coins > b.Coins
		end
		return (a.SeatIndex or 0) < (b.SeatIndex or 0)
	end)
	for i, row in sorted do
		local previous = sorted[i - 1]
		if previous and previous.Collectibles == row.Collectibles and previous.Coins == row.Coins then
			row.Placement = previous.Placement
		else
			row.Placement = i
		end
	end
	return sorted
end

function Match:standings()
	local rows = {}
	for _, seat in self.Seats do
		table.insert(rows, {
			Participant = seat.Participant,
			SeatIndex = seat.Index,
			Collectibles = self:collectiblesOf(seat),
			Coins = self:coinsOf(seat),
		})
	end
	return Match.rank(rows)
end

return Match
