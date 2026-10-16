--[[
	Match
	The rules of one board-game match, with no networking, timing or world in it, so it can
	be tested on its own. BoardGame drives it and draws the results.

	  Match.new(board, participants, settings, deps)
	    settings  { Rounds, Difficulty }
	    deps      {
	      Wallet     CoinService-like: get, add, spend, getCollectibles, addCollectibles, transfer
	      Inventory  Inventory-like: grant, equip, getEquipped, unowned
	      Rng        Random
	      Ask        function(seat, request) -> option index; may yield. request =
	                 { Kind = "Path"|"Collectible"|"Shop"|"Target", Prompt, Options = {labels}, Default, Data }
	    }

	A seat: { Index, Participant, SpaceId, Items = {item ids}, Shield, Stats }. Seats keep
	their place in the turn order, inventory and stats when a bot takes over from a player
	who left (replaceParticipant).

	A turn: beginTurn(seat) -> [useItem(seat, slot, target)] -> rollTurn(seat) -> move(...) -> endTurn().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local BotBrain = require(script.Parent.BotBrain)
local ChaosEvents = require(script.Parent.ChaosEvents)
local Events = require(script.Parent.Events)
local Items = require(script.Parent.Items)
local SpaceTypes = require(script.Parent.SpaceTypes)

local Match = {}
Match.__index = Match

local itemsById = {}
for _, item in Items do
	itemsById[item.Id] = item
end

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

local function isDieValue(value): boolean
	return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= Config.Board.DieSides
end

function Match.getItem(id: string)
	return itemsById[id]
end

function Match.new(board, participants, settings, deps)
	local self = setmetatable({
		Board = board,
		Deps = deps,
		Rng = deps.Rng or Random.new(),
		Rounds = settings.Rounds or Config.Match.BoardRounds,
		Difficulty = settings.Difficulty or Config.Match.BotDifficulty,
		Round = 0,
		Seats = {},
		Order = {}, -- seat order until decideTurnOrder runs
		CollectibleSpace = nil,
		CollectibleName = Config.Collectible.Name,
		CollectiblePrice = Config.Collectible.Price,
		Turn = nil, -- { Seat, Stage = "PreRoll"|"Moving", ItemUsed, Dice, Fixed }
		Traps = {}, -- [spaceId] = { Owner = seat, Coins = n }
		GateOpen = {}, -- [gateId] = true/false (Switch spaces flip them)
	}, Match)

	for index, participant in participants do
		local seat = {
			Index = index,
			Participant = participant,
			SpaceId = board.Start,
			Items = {},
			Shield = false,
			Stats = { MinigamePoints = 0, CoinsEarned = 0, SpacesMoved = 0 },
		}
		table.insert(self.Seats, seat)
		table.insert(self.Order, seat)
	end
	for _, gate in board.Gates or {} do
		self.GateOpen[gate.Id] = gate.Open ~= false
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

function Match:seatById(id: string?)
	for _, seat in self.Seats do
		if seat.Participant.Id == id then
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

--[[
	Adds/removes coins (never below 0) as a board effect. A Coin Shield blocks the next loss.
	Returns the change that actually happened and whether a shield blocked it.
	Gains count towards the Coin Collector bonus. (Purchases use Wallet.spend instead.)
]]
function Match:changeCoins(seat, amount: number): (number, boolean)
	if amount < 0 and seat.Shield and self:coinsOf(seat) > 0 then
		seat.Shield = false
		return 0, true
	end
	local _, delta = self.Deps.Wallet.add(seat.Participant, amount)
	if delta > 0 then
		seat.Stats.CoinsEarned += delta
	end
	return delta, false
end

-- Turn order -----------------------------------------------------------------------------------

--[[
	Everyone rolls once; highest goes first. Tied seats roll again among themselves (and again,
	until nobody is tied). rollFor(seats, attempt) -> { [seat] = roll } lets BoardGame wait for
	players to press ROLL; by default the match's Rng rolls. Invalid rolls are re-rolled here.
	Sets self.Order and returns it with a log: { { Seat, Roll, Attempt } }.
]]
function Match:decideTurnOrder(rollFor)
	local log = {}
	rollFor = rollFor or function(seats)
		local rolls = {}
		for _, seat in seats do
			rolls[seat] = self:roll()
		end
		return rolls
	end

	local function resolve(group, attempt)
		local rolls = rollFor(group, attempt) or {}
		for _, seat in group do
			if not isDieValue(rolls[seat]) then
				rolls[seat] = self:roll()
			end
			table.insert(log, { Seat = seat, Roll = rolls[seat], Attempt = attempt })
		end
		local sorted = table.clone(group)
		table.sort(sorted, function(a, b)
			if rolls[a] ~= rolls[b] then
				return rolls[a] > rolls[b]
			end
			return a.Index < b.Index
		end)
		local result = {}
		local i = 1
		while i <= #sorted do
			local j = i
			while sorted[j + 1] and rolls[sorted[j + 1]] == rolls[sorted[i]] do
				j += 1
			end
			if j > i then
				for _, seat in resolve(table.move(sorted, i, j, 1, {}), attempt + 1) do
					table.insert(result, seat)
				end
			else
				table.insert(result, sorted[i])
			end
			i = j + 1
		end
		return result
	end

	self.Order = resolve(table.clone(self.Seats), 1)
	return self.Order, log
end

-- Dice -----------------------------------------------------------------------------------------

function Match:roll(): number
	return self.Rng:NextInteger(1, Config.Board.DieSides)
end

-- Turns + items --------------------------------------------------------------------------------

function Match:beginTurn(seat)
	self.Turn = { Seat = seat, Stage = "PreRoll", ItemUsed = false, Dice = 1 }
end

function Match:endTurn()
	self.Turn = nil
end

-- Adds an item to a seat's inventory. False if unknown or the inventory is full.
function Match:giveItem(seat, itemId: string): boolean
	if not itemsById[itemId] or #seat.Items >= Config.Items.MaxHeld then
		return false
	end
	table.insert(seat.Items, itemId)
	return true
end

--[[
	Uses the item in `slot` of the seat's inventory. Every rule is checked here, so players
	(via the remote) and bots go through exactly the same validation:
	  it must be this seat's turn, before the roll, no item used yet this turn,
	  the slot must hold a real item, an Opponent item needs another seat as target, and a
	  DieFace item needs a whole number 1..DieSides as `choice`.
	Returns true + feed text, or false + reason. A refused item stays in the inventory.
]]
function Match:useItem(seat, slot, target, choice): (boolean, string)
	local turn = self.Turn
	if not turn or turn.Seat ~= seat then
		return false, "not your turn"
	end
	if turn.Stage ~= "PreRoll" then
		return false, "items are used before rolling"
	end
	if turn.ItemUsed then
		return false, "one item per turn"
	end
	if type(slot) ~= "number" or slot % 1 ~= 0 or not seat.Items[slot] then
		return false, "you don't have that item"
	end
	local item = itemsById[seat.Items[slot]]
	if not item then
		return false, "unknown item"
	end
	if item.Target == "Opponent" then
		if type(target) ~= "table" or target == seat or not table.find(self.Seats, target) then
			return false, "pick an opponent"
		end
	else
		target = nil
	end
	if item.Choice == "DieFace" then
		if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > Config.Board.DieSides then
			return false, "pick a number"
		end
	else
		choice = nil
	end
	local text, reason = item.Use(self, seat, target, choice)
	if not text then
		return false, reason or "can't use that now"
	end
	table.remove(seat.Items, slot)
	turn.ItemUsed = true
	if item.Dice then
		turn.Dice = item.Dice
	end
	return true, text
end

-- Rolls this turn's dice (1, more from a dice item, or a chosen number from a Lucky Die).
-- Returns the total and each die.
function Match:rollTurn(seat): (number, { number })
	local turn = self.Turn
	if turn and turn.Seat == seat and turn.Fixed then
		turn.Stage = "Moving"
		return turn.Fixed, { turn.Fixed }
	end
	local count = if turn and turn.Seat == seat then turn.Dice else 1
	local dice, total = {}, 0
	for i = 1, count do
		dice[i] = self:roll()
		total += dice[i]
	end
	if turn then
		turn.Stage = "Moving"
	end
	return total, dice
end

-- Stealing + traps ---------------------------------------------------------------------------

--[[
	Takes up to `amount` coins from victim to thief. A Coin Shield on the victim blocks it
	(and breaks). Returns coins taken, and whether a shield blocked it.
]]
function Match:stealCoins(thief, victim, amount: number): (number, boolean)
	if victim.Shield and self:coinsOf(victim) > 0 then
		victim.Shield = false
		return 0, true
	end
	local _, delta = self.Deps.Wallet.add(victim.Participant, -amount)
	local taken = -delta
	if taken > 0 then
		self:changeCoins(thief, taken)
	end
	return taken, false
end

--[[
	The Crown steal: the thief pays `fee` coins, then takes one collectible from the victim.
	A Coin Shield on the victim blocks it (the shield breaks; the fee is still paid).
	Returns "stolen" | "blocked", or nil + reason (nothing happened).
]]
function Match:stealCollectible(thief, victim, fee: number): (string?, string?)
	if self:collectiblesOf(victim) < 1 then
		return nil, ("they have no %s"):format(Config.Collectible.Plural)
	end
	if not self.Deps.Wallet.spend(thief.Participant, fee) then
		return nil, ("you need %d coins to pay for it"):format(fee)
	end
	if victim.Shield then
		victim.Shield = false
		return "blocked"
	end
	self.Deps.Wallet.addCollectibles(victim.Participant, -1)
	self.Deps.Wallet.addCollectibles(thief.Participant, 1)
	return "stolen"
end

-- Sets a trap on the seat's current space. False if one is already there.
function Match:setTrap(seat, coins: number): boolean
	if self.Traps[seat.SpaceId] then
		return false
	end
	self.Traps[seat.SpaceId] = { Owner = seat, Coins = coins }
	return true
end

-- An opponent landing on a trap pays its owner (a shield blocks it). Returns feed text.
function Match:springTrap(seat): string?
	local trap = self.Traps[seat.SpaceId]
	if not trap or trap.Owner == seat then
		return nil
	end
	self.Traps[seat.SpaceId] = nil
	local taken, blocked = self:stealCoins(trap.Owner, seat, trap.Coins)
	if blocked then
		return ("%s's Coin Shield broke %s's trap"):format(seat.Participant.Name, trap.Owner.Participant.Name)
	end
	return ("%s stepped in %s's trap and paid %d coins"):format(seat.Participant.Name, trap.Owner.Participant.Name, taken)
end

-- Items that can appear on this board (Items with a Boards list only show up on those boards).
function Match:itemPool()
	local pool = {}
	for _, item in Items do
		if not item.Boards or table.find(item.Boards, self.Board.Name) then
			table.insert(pool, item)
		end
	end
	return pool
end

-- Opponents a Target item could be used on.
function Match:opponentsOf(seat)
	local list = {}
	for _, other in self.Seats do
		if other ~= seat then
			table.insert(list, other)
		end
	end
	return list
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

-- Comeback ------------------------------------------------------------------------------------

local function comebackOn(match): boolean
	return Config.Comeback.Enabled and match.Round >= Config.Comeback.StartRound
end

-- An underdog is far enough behind the Crown leader to get help (discount, better gifts).
function Match:isUnderdog(seat): boolean
	if not comebackOn(self) then
		return false
	end
	local leader = 0
	for _, other in self.Seats do
		leader = math.max(leader, self:collectiblesOf(other))
	end
	return leader - self:collectiblesOf(seat) >= Config.Comeback.UnderdogGap
end

-- What this seat pays for the collectible right now (underdogs get a discount).
function Match:collectiblePriceFor(seat): number
	if self:isUnderdog(seat) then
		return math.max(Config.Comeback.MinCrownPrice, self.CollectiblePrice - Config.Comeback.UnderdogDiscount)
	end
	return self.CollectiblePrice
end

-- True in the last round when Final Frenzy is on.
function Match:isFrenzy(): boolean
	return Config.Comeback.Enabled and Config.Comeback.FinalFrenzy and self.Round >= self.Rounds
end

-- Coins a Gain / Lose space is worth this round.
function Match:spaceCoins(base: number): number
	return if self:isFrenzy() then base * Config.Comeback.FrenzyMultiplier else base
end

--[[
	Start of a round: the last-place seat(s) get a few coins (from Comeback.StartRound on).
	Returns feed text or nil.
]]
function Match:startRound(round: number): string?
	self.Round = round
	if not comebackOn(self) then
		return nil
	end
	local rows = self:standings()
	local last = rows[#rows].Placement
	if last == 1 then
		return nil -- everyone tied
	end
	local names = {}
	for _, row in rows do
		if row.Placement == last then
			local seat = self:seatOf(row.Participant)
			self:changeCoins(seat, Config.Comeback.LastPlaceCoins)
			table.insert(names, row.Participant.Name)
		end
	end
	return ("Catch-up: %s +%d coins"):format(table.concat(names, ", "), Config.Comeback.LastPlaceCoins)
end

-- Gift-space reward table for this seat (underdogs get better odds on items and Crowns).
function Match:rewardsFor(seat)
	if not self:isUnderdog(seat) then
		return Config.Economy.Rewards
	end
	local boosted = {}
	for _, reward in Config.Economy.Rewards do
		local copy = table.clone(reward)
		if copy.Kind == "Collectible" or copy.Kind == "Item" then
			copy.Weight *= Config.Comeback.UnderdogGiftBoost
		end
		table.insert(boosted, copy)
	end
	return boosted
end

-- Collectible purchase ---------------------------------------------------------------------------

-- Pays for the collectible. Returns true if bought (and moves it).
function Match:buyCollectible(seat): boolean
	if not self.Deps.Wallet.spend(seat.Participant, self:collectiblePriceFor(seat)) then
		return false
	end
	self.Deps.Wallet.addCollectibles(seat.Participant, 1)
	self.CollectiblePrice = Config.Collectible.Price -- a Price Surge ends with the purchase
	self:relocateCollectible()
	return true
end

-- Reached the collectible's space (passing or landing): offer it if affordable.
function Match:offerCollectible(seat): string
	local name = seat.Participant.Name
	local price = self:collectiblePriceFor(seat)
	if self:coinsOf(seat) < price then
		return ("%s needs %d coins for a %s"):format(name, price, self.CollectibleName)
	end
	local pick = self:ask(seat, {
		Kind = "Collectible",
		Prompt = ("Buy a %s for %d coins?%s"):format(
			self.CollectibleName,
			price,
			if price < self.CollectiblePrice then " (underdog discount)" else ""
		),
		Options = { "Buy", "Not now" },
		Default = 1,
	})
	if pick == 1 and self:buyCollectible(seat) then
		return ("%s bought a %s!"):format(name, self.CollectibleName)
	end
	return ("%s passed on the %s"):format(name, self.CollectibleName)
end

function Match:ask(seat, request): number
	local pick = self.Deps.Ask(seat, request)
	if type(pick) ~= "number" or pick % 1 ~= 0 or pick < 1 or pick > #request.Options then
		return request.Default or 1
	end
	return pick
end

-- Movement ------------------------------------------------------------------------------------

-- Gates ----------------------------------------------------------------------------------------

-- The gate on the edge from -> to, if any.
function Match:gateOn(from: number, to: number)
	for _, gate in self.Board.Gates or {} do
		if gate.From == from and gate.To == to then
			return gate
		end
	end
	return nil
end

-- Where a piece can go from `id` right now: closed gates are left out (never all of them).
function Match:nextOptions(id: number): { number }
	local all = self.Board:nextOptions(id)
	local open = {}
	for _, nextId in all do
		local gate = self:gateOn(id, nextId)
		if not gate or self.GateOpen[gate.Id] then
			table.insert(open, nextId)
		end
	end
	return if #open > 0 then open else all
end

-- Flips every gate on the board (Switch space). Returns how many are now open.
function Match:toggleGates(): number
	local open = 0
	for _, gate in self.Board.Gates or {} do
		self.GateOpen[gate.Id] = not self.GateOpen[gate.Id]
		open += if self.GateOpen[gate.Id] then 1 else 0
	end
	self.DistanceCache = nil
	return open
end

-- Fewest moves from -> to with the gates as they are now (math.huge if unreachable).
function Match:distance(from: number, to: number): number
	self.DistanceCache = self.DistanceCache or {}
	local row = self.DistanceCache[from]
	if not row then
		row = { [from] = 0 }
		local queue, head = { from }, 1
		while queue[head] do
			local id = queue[head]
			head += 1
			for _, nextId in self:nextOptions(id) do
				if row[nextId] == nil then
					row[nextId] = row[id] + 1
					table.insert(queue, nextId)
				end
			end
		end
		self.DistanceCache[from] = row
	end
	return row[to] or math.huge
end

--[[
	What a fork choice leads to, shown with the choice so players can decide:
	  CrownDistance  moves to the collectible going this way (math.huge if it can't be reached)
	  Preview        tile text of the next 3 spaces down this way, e.g. "+3 ? SHOP"
	  Toll           coins the route costs
]]
function Match:routeInfo(_seat, firstId: number, toll: number)
	local shorts = {}
	local id = firstId
	for _ = 1, 3 do
		local space = self.Board:get(id)
		local short = SpaceTypes[space.Type].Short
		table.insert(shorts, if short == "" then "·" else short)
		id = self:nextOptions(id)[1]
	end
	return {
		CrownDistance = 1 + self:distance(firstId, self.CollectibleSpace),
		Preview = table.concat(shorts, " "),
		Toll = toll,
	}
end

-- One space forward. At a fork the mover chooses; a tolled route is only offered to (and
-- charged to) someone who can pay.
function Match:step(seat): number
	local here = seat.SpaceId
	local options = {}
	for _, id in self:nextOptions(here) do
		local gate = self:gateOn(here, id)
		if not gate or not gate.Toll or self:coinsOf(seat) >= gate.Toll then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		options = self:nextOptions(here)
	end
	local nextId = options[1]
	if #options > 1 then
		local space = self.Board:get(here)
		local all = self.Board:nextOptions(here)
		local labels, info = {}, {}
		for i, id in options do
			local index = table.find(all, id)
			local gate = self:gateOn(here, id)
			info[i] = self:routeInfo(seat, id, if gate then gate.Toll or 0 else 0)
			local name = if space.Paths and index then space.Paths[index] else ("Space %d"):format(id)
			labels[i] = ("%s\n%s %s · %s"):format(
				name,
				self.CollectibleName,
				if info[i].CrownDistance == math.huge then "far" else ("in %d"):format(info[i].CrownDistance),
				info[i].Preview
			)
		end
		nextId = options[self:ask(seat, {
			Kind = "Path",
			Prompt = "Which way?",
			Options = labels,
			Default = 1,
			Data = { Spaces = options, Info = info },
		})]
	end
	local gate = self:gateOn(here, nextId)
	if gate and gate.Toll and gate.Toll > 0 then
		self.Deps.Wallet.spend(seat.Participant, gate.Toll)
	end
	seat.SpaceId = nextId
	seat.Stats.SpacesMoved += 1
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
	local trap = self:springTrap(seat)
	local space = self.Board:get(seat.SpaceId)
	local spaceType = SpaceTypes[space.Type]
	local text = spaceType.Resolve(self, seat, space)
	if trap then
		return if text then trap .. ". " .. text else trap
	end
	return text
end

-- Space helpers (used by SpaceTypes / Events) ---------------------------------------------------

function Match:runChaos(seat): string
	local event = weightedPick(self.Rng, ChaosEvents)
	return ("%s: %s"):format(event.Name, event.Apply(self, seat, self.Rng))
end

-- Item space: a random item, or a few coins if the bag is full.
function Match:itemSpace(seat): string
	local item = self:giveRandomItem(seat)
	if item then
		return ("%s found a %s"):format(seat.Participant.Name, item.Name)
	end
	local delta = self:changeCoins(seat, Config.Economy.ItemSpaceFallbackCoins)
	return ("%s's bag is full: +%d coins instead"):format(seat.Participant.Name, delta)
end

--[[
	Duel space: the lander picks an opponent and a stake both can pay; both roll a die and the
	higher roll takes the stake (a tie is a draw). A duel is a wager, so shields don't apply.
]]
function Match:runDuel(seat): string
	local name = seat.Participant.Name
	local opponents = {}
	for _, other in self:opponentsOf(seat) do
		if self:coinsOf(other) >= Config.Economy.DuelStakes[1] then
			table.insert(opponents, other)
		end
	end
	if self:coinsOf(seat) < Config.Economy.DuelStakes[1] or #opponents == 0 then
		return ("%s wants a duel, but nobody has the coins"):format(name)
	end
	local labels = {}
	for i, other in opponents do
		labels[i] = ("%s (%d coins)"):format(other.Participant.Name, self:coinsOf(other))
	end
	table.insert(labels, "No duel")
	local pick = self:ask(seat, {
		Kind = "DuelTarget",
		Prompt = "Duel! Challenge who?",
		Options = labels,
		Default = #labels,
		Data = { Seats = opponents },
	})
	local rival = opponents[pick]
	if not rival then
		return ("%s declined the duel"):format(name)
	end
	local stakes, stakeLabels = {}, {}
	for _, stake in Config.Economy.DuelStakes do
		if self:coinsOf(seat) >= stake and self:coinsOf(rival) >= stake then
			table.insert(stakes, stake)
			table.insert(stakeLabels, ("%d coins"):format(stake))
		end
	end
	local stake = stakes[self:ask(seat, {
		Kind = "DuelStake",
		Prompt = ("Duel %s: how many coins?"):format(rival.Participant.Name),
		Options = stakeLabels,
		Default = 1,
		Data = { Stakes = stakes, Rival = rival },
	})]
	local mine, theirs = self:roll(), self:roll()
	local result = ("%s %d vs %s %d"):format(name, mine, rival.Participant.Name, theirs)
	if mine == theirs then
		return result .. ": a draw!"
	end
	local winner, loser = if mine > theirs then seat else rival, if mine > theirs then rival else seat
	local _, taken = self.Deps.Wallet.add(loser.Participant, -stake)
	self:changeCoins(winner, -taken)
	return ("%s: %s wins %d coins"):format(result, winner.Participant.Name, -taken)
end

--[[
	Switch space: flip the board's gates (free), pay to move the Crown, or leave it.
]]
function Match:runSwitch(seat): string
	local name = seat.Participant.Name
	local options, actions = {}, {}
	if #(self.Board.Gates or {}) > 0 then
		table.insert(options, "Flip the gates")
		table.insert(actions, "Gates")
	end
	if self:coinsOf(seat) >= Config.Economy.CrownMovePrice then
		table.insert(options, ("Move the %s (%d coins)"):format(self.CollectibleName, Config.Economy.CrownMovePrice))
		table.insert(actions, "Crown")
	end
	table.insert(options, "Leave it")
	table.insert(actions, "None")
	local action = actions[self:ask(seat, {
		Kind = "Switch",
		Prompt = "Switch: change the board?",
		Options = options,
		Default = #options,
		Data = { Actions = actions },
	})]
	if action == "Gates" then
		local open = self:toggleGates()
		return ("%s flipped the gates: %s"):format(name, if open > 0 then "the shortcut is open" else "the shortcut is closed")
	elseif action == "Crown" and self.Deps.Wallet.spend(seat.Participant, Config.Economy.CrownMovePrice) then
		self:relocateCollectible()
		return ("%s paid %d coins to move the %s"):format(name, Config.Economy.CrownMovePrice, self.CollectibleName)
	end
	return ("%s left the board as it is"):format(name)
end

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

-- A random board item into the seat's inventory. Returns the item, or nil if it's full.
function Match:giveRandomItem(seat)
	if #seat.Items >= Config.Items.MaxHeld then
		return nil
	end
	local item = weightedPick(self.Rng, self:itemPool())
	self:giveItem(seat, item.Id)
	return item
end

function Match:giveReward(seat): string
	local name = seat.Participant.Name
	local reward = weightedPick(self.Rng, self:rewardsFor(seat))
	if reward.Kind == "Item" then
		local item = self:giveRandomItem(seat)
		if item then
			return ("%s unwrapped a %s!"):format(name, item.Name)
		end
		reward = { Kind = "Coins", Amount = 5 } -- bag is full
	end
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

--[[
	Shop: up to Config.Economy.ShopItemOffers board items (if there's room in the bag) and
	Config.Economy.ShopOffers cosmetics the visitor doesn't own. Data.Items lists each offer
	as { Kind = "Item"|"Cosmetic", Id, Name, Price }.
]]
function Match:visitShop(seat): string
	local name = seat.Participant.Name
	local offers = {}
	if #seat.Items < Config.Items.MaxHeld then
		local pool = self:itemPool()
		for _ = 1, math.min(Config.Economy.ShopItemOffers, #pool) do
			local item = table.remove(pool, self.Rng:NextInteger(1, #pool))
			table.insert(offers, { Kind = "Item", Id = item.Id, Name = item.Name, Price = item.Price })
		end
	end
	local unowned = self.Deps.Inventory.unowned(seat.Participant.Id)
	for _ = 1, math.min(Config.Economy.ShopOffers, #unowned) do
		local item = table.remove(unowned, self.Rng:NextInteger(1, #unowned))
		table.insert(offers, { Kind = "Cosmetic", Id = item.Id, Name = item.Name, Price = item.Price })
	end
	if #offers == 0 then
		return ("%s already owns everything in the shop"):format(name)
	end
	local labels = {}
	for i, offer in offers do
		labels[i] = ("%s (%d coins)"):format(offer.Name, offer.Price)
	end
	table.insert(labels, "Leave")
	local pick = self:ask(seat, {
		Kind = "Shop",
		Prompt = "Shop: buy something?",
		Options = labels,
		Default = #labels,
		Data = { Items = offers },
	})
	local offer = offers[pick]
	if not offer then
		return ("%s left the shop"):format(name)
	end
	if offer.Kind == "Item" and #seat.Items >= Config.Items.MaxHeld then
		return ("%s has no room for the %s"):format(name, offer.Name)
	end
	if not self.Deps.Wallet.spend(seat.Participant, offer.Price) then
		return ("%s can't afford the %s"):format(name, offer.Name)
	end
	if offer.Kind == "Item" then
		self:giveItem(seat, offer.Id)
	else
		self:grantCosmetic(seat, offer.Id)
	end
	return ("%s bought a %s"):format(name, offer.Name)
end

-- Minigames + bonuses ---------------------------------------------------------------------------

--[[
	Records a minigame for the bonus stats. results: MinigameManager's normalized results
	({ Participant, Placement }); rows: the coin rows ({ Id, Coins }).
]]
function Match:recordMinigame(results, rows)
	local coinsById = {}
	for _, row in rows or {} do
		coinsById[row.Id] = row.Coins
	end
	for _, result in results or {} do
		local seat = self:seatOf(result.Participant)
		if seat then
			seat.Stats.MinigamePoints += Config.MinigamePointsByPlacement[result.Placement] or 0
			seat.Stats.CoinsEarned += coinsById[result.Participant.Id] or 0
		end
	end
end

--[[
	Hands out Config.Bonuses. Returns { { Bonus, Winners = {seats}, Value } } in config order.
	A bonus nobody scored on (best value 0) goes to nobody.
]]
function Match:awardBonuses(bonuses)
	local awarded = {}
	for _, bonus in bonuses or Config.Bonuses do
		local best = 0
		for _, seat in self.Seats do
			best = math.max(best, seat.Stats[bonus.Stat] or 0)
		end
		local winners = {}
		if best > 0 then
			for _, seat in self.Seats do
				if (seat.Stats[bonus.Stat] or 0) == best then
					table.insert(winners, seat)
				end
			end
			if #winners > 1 and not bonus.AwardTies then
				winners = {}
			end
		end
		for _, seat in winners do
			self.Deps.Wallet.addCollectibles(seat.Participant, bonus.Crowns or 1)
		end
		table.insert(awarded, { Bonus = bonus, Winners = winners, Value = best })
	end
	return awarded
end

-- Seats -----------------------------------------------------------------------------------------

-- A bot takes over a seat (its player left). Coins, collectibles, items and stats carry over.
function Match:replaceParticipant(seat, newParticipant)
	self.Deps.Wallet.transfer(seat.Participant, newParticipant)
	seat.Participant = newParticipant
end

-- Bots ------------------------------------------------------------------------------------------

-- What a bot picks for an Ask request. `skill` is 0..1.
function Match:botDecision(seat, request, skill: number?): number
	return BotBrain.decide(self, seat, request, BotBrain.profile(self.Difficulty), skill or 0.5)
end

-- Which item (slot, target seat) a bot uses before rolling, or nil.
function Match:botItemChoice(seat)
	return BotBrain.chooseItem(self, seat, BotBrain.profile(self.Difficulty))
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
