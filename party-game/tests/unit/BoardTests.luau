--[[
	Unit tests for the board game rules: board data, movement, turns, spaces, events,
	purchases, wallets, inventory and final standings. No networking, timing or world.

	Run (Studio, edit mode is fine):
	  1. rojo build tests/unit.project.json -o UnitTests.rbxlx, open it in Studio
	  2. Command bar: require(game.ServerStorage.PartyTests.BoardTests)()
	Prints every failure and returns passed, failed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local Config = require(ReplicatedStorage.PartyShared.Config)
local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local CoinService = require(Server.CoinService)
local Inventory = require(Server.Inventory)
local BoardLayout = require(Server.Board.BoardLayout)
local Events = require(Server.Board.Events)
local BotBrain = require(Server.Board.BotBrain)
local Items = require(Server.Board.Items)
local Match = require(Server.Board.Match)
local SpaceTypes = require(Server.Board.SpaceTypes)
local Classic = require(Server.Board.Boards.Classic)

local tests = {}
local function test(name: string, fn)
	table.insert(tests, { Name = name, Fn = fn })
end

local function eq(actual, expected, what: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function ok(condition, what: string)
	if not condition then
		error(what, 2)
	end
end

local nextId = 0
local function fakeParticipants(count: number)
	local list = {}
	for i = 1, count do
		nextId += 1
		table.insert(list, { Id = "bot_test" .. nextId, Name = "T" .. i, IsBot = true })
	end
	return list
end

-- answers[Kind] = option index (or a function(request) -> index); records every request.
local function newMatch(answers, seed: number?, difficulty: string?)
	CoinService.resetAll()
	local asked = {}
	local board = BoardLayout.load(Classic, SpaceTypes)
	local match = Match.new(board, fakeParticipants(4), { Rounds = 3, Difficulty = difficulty or "Hard" }, {
		Wallet = CoinService,
		Inventory = Inventory,
		Rng = Random.new(seed or 7),
		Ask = function(_seat, request)
			table.insert(asked, request)
			local answer = answers and answers[request.Kind]
			if type(answer) == "function" then
				return answer(request)
			end
			return answer or request.Default
		end,
	})
	return match, asked
end

local function setCoins(match, seat, amount)
	CoinService.add(seat.Participant, amount - match:coinsOf(seat))
end

-- Swaps a Config table for the duration of fn.
local function withConfig(tbl, key, value, fn)
	local old = tbl[key]
	tbl[key] = value
	local success, err = pcall(fn)
	tbl[key] = old
	if not success then
		error(err, 0)
	end
end

-- Board data ----------------------------------------------------------------------------------

test("Classic board is valid", function()
	eq(BoardLayout.validate(Classic, SpaceTypes), nil, "problem")
end)

test("every space type resolves", function()
	for key, spaceType in SpaceTypes do
		ok(type(spaceType.Resolve) == "function", key .. " has no Resolve")
		ok(typeof(spaceType.Color) == "Color3", key .. " has no Color")
	end
end)

test("validation catches broken boards", function()
	local function broken(edit)
		local data = { Name = "X", Start = 1, CrownSpaces = { 1, 2 }, Spaces = {
			{ Id = 1, Type = "Neutral", At = { 0, 0 }, Next = { 2 } },
			{ Id = 2, Type = "Gain", At = { 1, 0 }, Next = { 3 } },
			{ Id = 3, Type = "Lose", At = { 2, 0 }, Next = { 1 } },
		} }
		edit(data)
		return BoardLayout.validate(data, SpaceTypes)
	end
	eq(broken(function() end), nil, "good board")
	ok(broken(function(d) d.Spaces[2].Next = {} end), "dead end not caught")
	ok(broken(function(d) d.Spaces[2].Next = { 9 } end), "missing next not caught")
	ok(broken(function(d) d.Spaces[2].Type = "Nope" end), "bad type not caught")
	ok(broken(function(d) d.Spaces[3].Id = 2 end), "duplicate id not caught")
	ok(broken(function(d) d.Start = 7 end), "bad start not caught")
	ok(broken(function(d) d.CrownSpaces = { 1 } end), "single crown space not caught")
	ok(broken(function(d)
		table.insert(d.Spaces, { Id = 4, Type = "Neutral", At = { 3, 0 }, Next = { 1 } })
	end), "unreachable space not caught")
	ok(broken(function(d)
		d.Spaces[3].Next = { 1, 4 }
		table.insert(d.Spaces, { Id = 4, Type = "Neutral", At = { 3, 0 }, Next = { 4 } })
	end), "trap loop not caught")
end)

-- Movement ------------------------------------------------------------------------------------

test("moves along the loop and wraps past the start", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.CollectibleSpace = 30 -- out of the way
	match:move(seat, 2)
	eq(seat.SpaceId, 3, "after 2")
	seat.SpaceId = 25
	match:move(seat, 3)
	eq(seat.SpaceId, 2, "after wrapping")
end)

test("forks ask the mover and follow the choice", function()
	local match, asked = newMatch({ Path = 2 })
	local seat = match.Seats[1]
	match.CollectibleSpace = 7
	setCoins(match, seat, 10) -- the shortcut has a toll
	seat.SpaceId = 4
	match:move(seat, 2)
	eq(seat.SpaceId, 27, "took the shortcut")
	eq(asked[1].Kind, "Path", "asked")
	eq(#asked[1].Options, 2, "options")
	match:move(seat, 4)
	eq(seat.SpaceId, 18, "shortcut rejoins the loop")

	local main = newMatch({ Path = 1 })
	main.CollectibleSpace = 30
	main.Seats[1].SpaceId = 4
	main:move(main.Seats[1], 2)
	eq(main.Seats[1].SpaceId, 6, "took the main road")
end)

test("a bad answer to a fork falls back to the default", function()
	local match = newMatch({ Path = 99 })
	match.CollectibleSpace = 30
	match.Seats[1].SpaceId = 5
	match:move(match.Seats[1], 1)
	eq(match.Seats[1].SpaceId, 6, "default path")
end)

test("onHop sees every space with the moves left", function()
	local match = newMatch()
	match.CollectibleSpace = 30
	local hops = {}
	match:move(match.Seats[1], 4, function(_, id, remaining)
		table.insert(hops, id .. ":" .. remaining)
	end)
	eq(table.concat(hops, ","), "2:3,3:2,4:1,5:0", "hops")
end)

-- Turns ---------------------------------------------------------------------------------------

test("turn order holds every seat once", function()
	local match = newMatch()
	eq(#match.Order, 4, "order size")
	local seen = {}
	for _, seat in match.Order do
		ok(not seen[seat], "seat twice in order")
		seen[seat] = true
	end
	for _, seat in match.Seats do
		ok(seen[seat], "seat missing from order")
		eq(seat.SpaceId, match.Board.Start, "starts on Start")
	end
end)

test("die rolls cover 1..DieSides and nothing else", function()
	local match = newMatch()
	local seen = {}
	for _ = 1, 500 do
		local roll = match:roll()
		ok(roll >= 1 and roll <= Config.Board.DieSides and roll % 1 == 0, "bad roll " .. roll)
		seen[roll] = true
	end
	for side = 1, Config.Board.DieSides do
		ok(seen[side], "never rolled " .. side)
	end
end)

-- Spaces --------------------------------------------------------------------------------------

test("gain and lose spaces change coins, never below zero", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.CollectibleSpace = 30
	seat.SpaceId = 2 -- Gain
	match:land(seat)
	eq(match:coinsOf(seat), Config.Economy.GainSpaceCoins, "after gain")
	setCoins(match, seat, 1)
	seat.SpaceId = 6 -- Lose
	match:land(seat)
	eq(match:coinsOf(seat), 0, "clamped at zero")
end)

test("neutral space does nothing", function()
	local match = newMatch()
	local seat = match.Seats[1]
	setCoins(match, seat, 4)
	seat.SpaceId = 1
	eq(match:land(seat), nil, "text")
	eq(match:coinsOf(seat), 4, "coins")
end)

test("every event runs and leaves a sane board", function()
	for _, event in Events do
		local match = newMatch(nil, 11)
		for i, seat in match.Seats do
			setCoins(match, seat, i * 3)
			seat.SpaceId = match.Board.Order[i * 5]
		end
		local text = event.Apply(match, match.Seats[1], match.Rng)
		ok(type(text) == "string" and #text > 0, event.Id .. " gave no text")
		for _, seat in match.Seats do
			ok(match.Board:get(seat.SpaceId) ~= nil, event.Id .. " put a seat off the board")
			ok(match:coinsOf(seat) >= 0, event.Id .. " made coins negative")
		end
	end
end)

test("swap event swaps two seats", function()
	local match = newMatch()
	local swap
	for _, event in Events do
		if event.Id == "SwapSpots" then
			swap = event
		end
	end
	for i, seat in match.Seats do
		seat.SpaceId = i + 10
	end
	swap.Apply(match, match.Seats[1], match.Rng)
	eq(match.Seats[1].SpaceId ~= 11, true, "mover moved")
	local spots = {}
	for _, seat in match.Seats do
		spots[seat.SpaceId] = true
	end
	for id = 11, 14 do
		ok(spots[id], "space " .. id .. " lost a seat")
	end
end)

test("reward space gives coins, a cosmetic or a collectible", function()
	local match = newMatch()
	local seat = match.Seats[1]
	withConfig(Config.Economy, "Rewards", { { Kind = "Coins", Amount = 7, Weight = 1 } }, function()
		match:giveReward(seat)
	end)
	eq(match:coinsOf(seat), 7, "coin reward")
	withConfig(Config.Economy, "Rewards", { { Kind = "Cosmetic", Weight = 1 } }, function()
		match:giveReward(seat)
	end)
	eq(#Inventory.getOwned(seat.Participant.Id), 1, "cosmetic reward")
	withConfig(Config.Economy, "Rewards", { { Kind = "Collectible", Amount = 1, Weight = 1 } }, function()
		match:giveReward(seat)
	end)
	eq(match:collectiblesOf(seat), 1, "collectible reward")
end)

-- Collectible ---------------------------------------------------------------------------------

test("collectible can't be bought without enough coins", function()
	local match, asked = newMatch({ Collectible = 1 })
	local seat = match.Seats[1]
	setCoins(match, seat, Config.Collectible.Price - 1)
	local before = match.CollectibleSpace
	match:offerCollectible(seat)
	eq(#asked, 0, "should not even ask")
	eq(match:collectiblesOf(seat), 0, "collectibles")
	eq(match.CollectibleSpace, before, "collectible stayed")
end)

test("buying the collectible costs coins and moves it", function()
	local match = newMatch({ Collectible = 1 })
	local seat = match.Seats[1]
	setCoins(match, seat, Config.Collectible.Price + 5)
	local before = match.CollectibleSpace
	match:offerCollectible(seat)
	eq(match:collectiblesOf(seat), 1, "collectibles")
	eq(match:coinsOf(seat), 5, "coins left")
	ok(match.CollectibleSpace ~= before, "collectible did not move")
	ok(table.find(match.Board.CrownSpaces, match.CollectibleSpace), "moved to a non-crown space")
end)

test("declining the collectible keeps the coins", function()
	local match = newMatch({ Collectible = 2 })
	local seat = match.Seats[1]
	setCoins(match, seat, 30)
	match:offerCollectible(seat)
	eq(match:collectiblesOf(seat), 0, "collectibles")
	eq(match:coinsOf(seat), 30, "coins")
end)

test("passing the collectible's space offers it mid-move", function()
	local match, asked = newMatch({ Collectible = 1 })
	local seat = match.Seats[1]
	setCoins(match, seat, 40)
	match.CollectibleSpace = 7
	seat.SpaceId = 3
	match:move(seat, 6) -- 4,5(fork->6),6,7,8,9
	eq(match:collectiblesOf(seat), 1, "bought while passing")
	eq(seat.SpaceId, 9, "kept moving")
	local kinds = {}
	for _, request in asked do
		table.insert(kinds, request.Kind)
	end
	ok(table.find(kinds, "Collectible"), "never offered")
end)

test("collectible never reappears where it was", function()
	local match = newMatch()
	for _ = 1, 200 do
		local before = match.CollectibleSpace
		match:relocateCollectible()
		ok(match.CollectibleSpace ~= before, "stayed put")
	end
end)

-- Shop ----------------------------------------------------------------------------------------

local function pickOffer(kind)
	return function(request)
		for i, offer in request.Data.Items do
			if offer.Kind == kind then
				return i
			end
		end
		return request.Default
	end
end

test("shop sells a cosmetic and equips it", function()
	local match, asked = newMatch({ Shop = pickOffer("Cosmetic") })
	local seat = match.Seats[1]
	setCoins(match, seat, 50)
	match:visitShop(seat)
	local request = asked[1]
	local offer = request.Data.Items[pickOffer("Cosmetic")(request)]
	local item = Cosmetics.get(offer.Id)
	ok(Inventory.owns(seat.Participant.Id, item.Id), "not owned")
	eq(Inventory.getEquipped(seat.Participant.Id)[item.Slot], item.Id, "not equipped")
	eq(match:coinsOf(seat), 50 - item.Price, "coins")
	eq(request.Options[#request.Options], "Leave", "last option")
end)

test("shop sells board items, but not into a full bag", function()
	local match, asked = newMatch({ Shop = pickOffer("Item") })
	local seat = match.Seats[1]
	setCoins(match, seat, 50)
	match:visitShop(seat)
	local offer = asked[1].Data.Items[1]
	eq(offer.Kind, "Item", "first offer is an item")
	eq(seat.Items[1], offer.Id, "item in bag")
	eq(match:coinsOf(seat), 50 - offer.Price, "paid")
	for _ = 1, Config.Items.MaxHeld do
		match:giveItem(seat, "CoinShield")
	end
	local before = #asked
	match:visitShop(seat)
	for _, each in asked[before + 1].Data.Items do
		ok(each.Kind ~= "Item", "offered an item to a full bag")
	end
end)

test("shop refuses what you can't afford, and leaving costs nothing", function()
	local match = newMatch({ Shop = 1 })
	local seat = match.Seats[1]
	setCoins(match, seat, 0)
	match:visitShop(seat)
	eq(#Inventory.getOwned(seat.Participant.Id), 0, "got it for free")
	local leaver = newMatch({ Shop = function(request)
		return #request.Options
	end })
	setCoins(leaver, leaver.Seats[1], 50)
	leaver:visitShop(leaver.Seats[1])
	eq(leaver:coinsOf(leaver.Seats[1]), 50, "leaving cost coins")
end)

-- Wallet, inventory, seats ----------------------------------------------------------------------

test("wallet spend is all-or-nothing", function()
	CoinService.resetAll()
	local p = fakeParticipants(1)[1]
	CoinService.add(p, 10)
	eq(CoinService.spend(p, 11), false, "overspend")
	eq(CoinService.get(p), 10, "unchanged")
	eq(CoinService.spend(p, 10), true, "exact spend")
	eq(CoinService.get(p), 0, "empty")
	eq(CoinService.spend(p, -5), false, "negative spend")
end)

test("inventory: grant once, equip only owned, bots reset", function()
	local bot = "bot_inv" .. os.clock()
	local player = "player_inv" .. os.clock()
	local item = Cosmetics.Items[1]
	eq(Inventory.equip(bot, item.Id), false, "equip unowned")
	eq(Inventory.grant(bot, item.Id), true, "first grant")
	eq(Inventory.grant(bot, item.Id), false, "second grant")
	eq(Inventory.grant(bot, "nope"), false, "unknown item")
	eq(Inventory.equip(bot, item.Id), true, "equip owned")
	Inventory.grant(player, item.Id)
	Inventory.resetBots()
	eq(Inventory.owns(bot, item.Id), false, "bot kept item")
	eq(Inventory.owns(player, item.Id), true, "player lost item")
	Inventory.forget(player)
end)

test("a replacement bot inherits the seat's coins and collectibles", function()
	local match = newMatch()
	local seat = match.Seats[2]
	setCoins(match, seat, 17)
	CoinService.addCollectibles(seat.Participant, 2)
	local replacement = fakeParticipants(1)[1]
	match:replaceParticipant(seat, replacement)
	eq(seat.Participant, replacement, "seat holder")
	eq(match:coinsOf(seat), 17, "coins")
	eq(match:collectiblesOf(seat), 2, "collectibles")
	eq(match:seatOf(replacement), seat, "seatOf")
end)

test("bot decisions: always buy the collectible, save coins at the shop", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.Round = 1
	eq(match:botDecision(seat, { Kind = "Collectible", Options = { "Buy", "Not now" }, Default = 1 }), 1, "buy")
	local shop = {
		Kind = "Shop",
		Options = { "Dice", "Hat", "Leave" },
		Default = 3,
		Data = { Items = {
			{ Kind = "Item", Id = "DoubleDice", Price = 6 },
			{ Kind = "Cosmetic", Id = "hat_party", Price = 6 },
		} },
	}
	setCoins(match, seat, 12)
	eq(match:botDecision(seat, shop), 3, "hard bot saves for the Crown")
	setCoins(match, seat, 30)
	eq(match:botDecision(seat, shop), 1, "hard bot buys a useful item with coins to spare")
	setCoins(match, seat, 60)
	eq(match:botDecision(seat, shop), 1, "items beat cosmetics")
	local profile = table.clone(BotBrain.profile("Hard"))
	profile.SaveFactor = 0
	setCoins(match, seat, 12)
	eq(BotBrain.chooseShop(match, seat, shop.Data.Items, 3, profile), 1, "no saving -> spends")
end)

test("bot decisions: hard bots head for the Crown at a fork when they can pay", function()
	local match = newMatch()
	local seat = match.Seats[1]
	seat.SpaceId = 5 -- fork: main road (6) or shortcut (27)
	local request = { Kind = "Path", Options = { "Main road", "Shortcut" }, Default = 1, Data = { Spaces = { 6, 27 } } }
	setCoins(match, seat, 40)
	match.CollectibleSpace = 20 -- far up the shortcut side
	eq(match:botDecision(seat, request), 2, "shortcut towards the Crown")
	match.CollectibleSpace = 7 -- right down the main road
	eq(match:botDecision(seat, request), 1, "main road towards the Crown")
end)

test("bot decisions: easy bots sometimes choose at random", function()
	local match = newMatch(nil, 3, "Easy")
	local seat = match.Seats[1]
	setCoins(match, seat, 40)
	match.CollectibleSpace = 7
	local request = { Kind = "Path", Options = { "Main road", "Shortcut" }, Default = 1, Data = { Spaces = { 6, 27 } } }
	local picks = {}
	for _ = 1, 60 do
		picks[match:botDecision(seat, request)] = true
	end
	ok(picks[1] and picks[2], "easy bot never varied")
end)

test("bot items: dice towards an affordable Crown, swap into the leader's spot", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.Round = 1
	match.CollectibleSpace = 13
	seat.SpaceId = 3 -- 10 moves from the Crown
	setCoins(match, seat, 30)
	match:giveItem(seat, "CoinShield")
	match:giveItem(seat, "TripleDice")
	match:beginTurn(seat)
	local slot = match:botItemChoice(seat)
	eq(seat.Items[slot], "TripleDice", "dice to reach the Crown")

	local swapper = newMatch()
	local me = swapper.Seats[1]
	swapper.Round = 1
	swapper.CollectibleSpace = 13
	me.SpaceId = 14 -- just past the Crown: a full lap away
	swapper.Seats[3].SpaceId = 12 -- one step before it
	setCoins(swapper, me, 25)
	swapper:giveItem(me, "SwapTicket")
	swapper:beginTurn(me)
	local swapSlot, target = swapper:botItemChoice(me)
	eq(swapSlot, 1, "used the ticket")
	eq(target, swapper.Seats[3], "picked the seat nearest the Crown")
	local used = swapper:useItem(me, swapSlot, target)
	eq(used, true, "validated like a player")
end)

test("bot items: no reason, no item", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.Round = 1
	setCoins(match, seat, 0)
	match:giveItem(seat, "CoinShield")
	match:beginTurn(seat)
	eq(match:botItemChoice(seat), nil, "shield with nothing to protect")
	match.Round = match.Rounds
	setCoins(match, seat, 3)
	eq(match:botItemChoice(seat), 1, "last round: use it up")
end)

-- Turn order --------------------------------------------------------------------------------------

-- rollFor that hands out scripted rolls: script[attempt][seatIndex] = roll.
local function scripted(script)
	return function(seats, attempt)
		local rolls = {}
		for _, seat in seats do
			rolls[seat] = script[attempt][seat.Index]
		end
		return rolls
	end
end

local function orderIndexes(order)
	local list = {}
	for _, seat in order do
		table.insert(list, seat.Index)
	end
	return table.concat(list, ",")
end

test("turn order: highest roll goes first", function()
	local match = newMatch()
	local order = match:decideTurnOrder(scripted({ { 2, 6, 4, 1 } }))
	eq(orderIndexes(order), "2,3,1,4", "order")
	eq(match.Order, order, "match uses it")
end)

test("turn order: tied seats reroll among themselves only", function()
	local match = newMatch()
	local order, log = match:decideTurnOrder(scripted({
		{ 5, 5, 2, 5 }, -- seats 1, 2, 4 tie for first
		{ 3, 6, nil, 3 }, -- seat 2 wins; 1 and 4 tie again
		{ 1, nil, nil, 4 }, -- seat 4 beats seat 1
	}))
	eq(orderIndexes(order), "2,4,1,3", "order")
	local attempts = {}
	for _, entry in log do
		attempts[entry.Attempt] = (attempts[entry.Attempt] or 0) + 1
	end
	eq(attempts[1], 4, "everyone rolled once")
	eq(attempts[2], 3, "three tied rerolled")
	eq(attempts[3], 2, "two tied rerolled again")
end)

test("turn order: same seed, same order; junk rolls are rerolled", function()
	local a = orderIndexes((newMatch(nil, 99):decideTurnOrder()))
	local b = orderIndexes((newMatch(nil, 99):decideTurnOrder()))
	eq(a, b, "deterministic")
	local match = newMatch()
	local _, log = match:decideTurnOrder(function(seats)
		local rolls = {}
		for _, seat in seats do
			rolls[seat] = 99 -- cheating client value
		end
		return rolls
	end)
	for _, entry in log do
		ok(entry.Roll >= 1 and entry.Roll <= Config.Board.DieSides, "kept an illegal roll")
	end
end)

-- Items -------------------------------------------------------------------------------------------

test("every item has the fields the game needs", function()
	for _, item in Items do
		ok(type(item.Id) == "string" and type(item.Name) == "string", "item needs Id and Name")
		ok(type(item.Price) == "number" and type(item.Weight) == "number", item.Id .. " needs Price and Weight")
		ok(type(item.Use) == "function", item.Id .. " needs Use")
		ok(BotBrain.ItemValue[item.Id], item.Id .. " has no bot shop value")
	end
end)

test("double and triple dice roll two and three dice", function()
	for id, count in { DoubleDice = 2, TripleDice = 3 } do
		local match = newMatch()
		local seat = match.Seats[1]
		match:giveItem(seat, id)
		match:beginTurn(seat)
		eq(match:useItem(seat, 1), true, id .. " used")
		eq(#seat.Items, 0, id .. " consumed")
		for _ = 1, 50 do
			match.Turn.Stage = "PreRoll"
			local total, dice = match:rollTurn(seat)
			eq(#dice, count, id .. " dice count")
			ok(total >= count and total <= count * Config.Board.DieSides, id .. " total out of range")
		end
	end
	local plain = newMatch()
	plain:beginTurn(plain.Seats[1])
	local _, dice = plain:rollTurn(plain.Seats[1])
	eq(#dice, 1, "no item: one die")
end)

test("coin shield blocks exactly one loss, then breaks", function()
	local match = newMatch()
	local seat = match.Seats[1]
	setCoins(match, seat, 10)
	match:giveItem(seat, "CoinShield")
	match:beginTurn(seat)
	eq(match:useItem(seat, 1), true, "used")
	eq(seat.Shield, true, "shield up")
	local delta, shielded = match:changeCoins(seat, 5)
	eq(delta, 5, "gains still count")
	eq(seat.Shield, true, "gain didn't break it")
	delta, shielded = match:changeCoins(seat, -3)
	eq(shielded, true, "blocked")
	eq(match:coinsOf(seat), 15, "coins kept")
	eq(seat.Shield, false, "broke")
	match:changeCoins(seat, -3)
	eq(match:coinsOf(seat), 12, "second loss lands")
	seat.SpaceId = 6 -- Lose space
	seat.Shield = true
	ok(string.find(match:land(seat), "Shield"), "lose space mentions the shield")
	eq(match:coinsOf(seat), 12, "lose space blocked")
end)

test("coin shield: can't stack, and purchases aren't 'losses'", function()
	local match = newMatch({ Collectible = 1 })
	local seat = match.Seats[1]
	setCoins(match, seat, 30)
	match:giveItem(seat, "CoinShield")
	match:giveItem(seat, "CoinShield")
	match:beginTurn(seat)
	match:useItem(seat, 1)
	match:beginTurn(seat)
	local used, reason = match:useItem(seat, 1)
	eq(used, false, "second shield")
	ok(reason ~= nil, "reason given")
	eq(#seat.Items, 1, "refused item kept")
	match:offerCollectible(seat)
	eq(match:collectiblesOf(seat), 1, "bought")
	eq(seat.Shield, true, "spending didn't break the shield")
end)

test("swap ticket swaps with the chosen opponent", function()
	local match = newMatch()
	local seat, other = match.Seats[1], match.Seats[3]
	seat.SpaceId, other.SpaceId = 4, 19
	match:giveItem(seat, "SwapTicket")
	match:beginTurn(seat)
	eq(match:useItem(seat, 1, other), true, "used")
	eq(seat.SpaceId, 19, "mover")
	eq(other.SpaceId, 4, "target")
	eq(seat.Stats.SpacesMoved, 0, "a swap isn't travelling")
end)

test("warp token always lands on a different real space", function()
	for seed = 1, 30 do
		local match = newMatch(nil, seed)
		local seat = match.Seats[1]
		seat.SpaceId = 9
		match:giveItem(seat, "WarpToken")
		match:beginTurn(seat)
		eq(match:useItem(seat, 1), true, "used")
		ok(seat.SpaceId ~= 9, "warped in place")
		ok(match.Board:get(seat.SpaceId), "warped off the board")
	end
end)

test("invalid item requests are refused and keep the item", function()
	local match = newMatch()
	local seat, other = match.Seats[1], match.Seats[2]
	match:giveItem(seat, "SwapTicket")
	match:giveItem(other, "DoubleDice")
	local function refused(what, ...)
		local used = match:useItem(...)
		eq(used, false, what)
	end
	refused("no turn yet", seat, 1, other)
	match:beginTurn(seat)
	refused("someone else's turn", other, 1)
	refused("empty slot", seat, 2, other)
	refused("junk slot", seat, "1", other)
	refused("fractional slot", seat, 1.5, other)
	refused("swap with nobody", seat, 1, nil)
	refused("swap with yourself", seat, 1, seat)
	refused("swap with a stranger", seat, 1, { Participant = { Name = "x" } })
	eq(#seat.Items, 1, "item kept through refusals")
	eq(match:useItem(seat, 1, other), true, "valid use")
	match:giveItem(seat, "DoubleDice")
	refused("second item in a turn", seat, 1)
	match:beginTurn(seat)
	match:rollTurn(seat)
	refused("after rolling", seat, 1)
	eq(#seat.Items, 1, "dice kept")
end)

test("inventory limit: gifts, events and giveItem stop at MaxHeld", function()
	local match = newMatch()
	local seat = match.Seats[1]
	for _ = 1, Config.Items.MaxHeld do
		eq(match:giveItem(seat, "WarpToken"), true, "room")
	end
	eq(match:giveItem(seat, "WarpToken"), false, "full")
	eq(match:giveItem(seat, "NotAnItem"), false, "unknown")
	eq(#seat.Items, Config.Items.MaxHeld, "held")
	eq(match:giveRandomItem(seat), nil, "random item into a full bag")
	withConfig(Config.Economy, "Rewards", { { Kind = "Item", Weight = 1 } }, function()
		match:giveReward(seat)
	end)
	eq(#seat.Items, Config.Items.MaxHeld, "gift didn't overfill")
	eq(match:coinsOf(seat), 5, "full bag gift becomes coins")
end)

test("item gifts and the item event fill the bag", function()
	local match = newMatch()
	local seat = match.Seats[1]
	withConfig(Config.Economy, "Rewards", { { Kind = "Item", Weight = 1 } }, function()
		match:giveReward(seat)
	end)
	eq(#seat.Items, 1, "gift item")
	for _, event in Events do
		if event.Id == "ItemDrop" then
			event.Apply(match, seat, match.Rng)
		end
	end
	eq(#seat.Items, 2, "event item")
end)

test("items stay with the seat when a bot takes over", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match:giveItem(seat, "TripleDice")
	seat.Shield = true
	seat.Stats.SpacesMoved = 7
	match:replaceParticipant(seat, fakeParticipants(1)[1])
	eq(seat.Items[1], "TripleDice", "items")
	eq(seat.Shield, true, "shield")
	eq(seat.Stats.SpacesMoved, 7, "stats")
end)

-- Item set 2 --------------------------------------------------------------------------------------

local function useOn(match, seat, id, target, choice)
	match:giveItem(seat, id)
	match:beginTurn(seat)
	return match:useItem(seat, #seat.Items, target, choice)
end

test("lucky die: only a whole 1..DieSides is accepted, then you move exactly that", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match:giveItem(seat, "LuckyDie")
	match:beginTurn(seat)
	for _, bad in { 0, Config.Board.DieSides + 1, 2.5, "3", {} } do
		eq((match:useItem(seat, 1, nil, bad)), false, "bad face " .. tostring(bad))
	end
	eq((match:useItem(seat, 1, nil, nil)), false, "no face")
	eq(#seat.Items, 1, "kept through refusals")
	eq((match:useItem(seat, 1, nil, 4)), true, "valid face")
	local total, dice = match:rollTurn(seat)
	eq(total, 4, "exact roll")
	eq(#dice, 1, "one die shown")
end)

test("pickpocket takes up to 6, refuses an empty target, and a shield stops it", function()
	local match = newMatch()
	local thief, victim = match.Seats[1], match.Seats[2]
	setCoins(match, victim, 0)
	eq((useOn(match, thief, "Pickpocket", victim)), false, "empty victim")
	eq(#thief.Items, 1, "item kept")
	setCoins(match, victim, 4)
	eq((match:useItem(thief, 1, victim)), true, "used")
	eq(match:coinsOf(victim), 0, "took all 4")
	eq(match:coinsOf(thief), 4, "thief got them")
	eq(thief.Stats.CoinsEarned, 4, "counts as earned")
	setCoins(match, victim, 20)
	victim.Shield = true
	eq((useOn(match, thief, "Pickpocket", victim)), true, "used into a shield")
	eq(match:coinsOf(victim), 20, "shield kept the coins")
	eq(victim.Shield, false, "shield broke")
	eq(#thief.Items, 0, "pickpocket spent")
end)

test("crown heist: costs a fee, needs a target with a Crown, a shield stops it", function()
	local match = newMatch()
	local thief, victim = match.Seats[1], match.Seats[2]
	setCoins(match, thief, 30)
	eq((useOn(match, thief, "CrownHeist", victim)), false, "victim has no Crowns")
	eq(match:coinsOf(thief), 30, "no fee taken")
	CoinService.addCollectibles(victim.Participant, 2)
	setCoins(match, thief, 14)
	eq((match:useItem(thief, 1, victim)), false, "can't pay the fee")
	eq(#thief.Items, 1, "item kept")
	setCoins(match, thief, 20)
	eq((match:useItem(thief, 1, victim)), true, "stolen")
	eq(match:collectiblesOf(thief), 1, "thief +1")
	eq(match:collectiblesOf(victim), 1, "victim -1")
	eq(match:coinsOf(thief), 5, "fee paid")
	setCoins(match, thief, 20)
	victim.Shield = true
	eq((useOn(match, thief, "CrownHeist", victim)), true, "used into a shield")
	eq(match:collectiblesOf(victim), 1, "shield kept the Crown")
	eq(match:coinsOf(thief), 5, "fee still paid")
	eq(victim.Shield, false, "shield broke")
end)

test("snare trap: catches the next opponent, not its owner; one per space", function()
	local match = newMatch()
	local owner, other, third = match.Seats[1], match.Seats[2], match.Seats[3]
	match.CollectibleSpace = 30
	owner.SpaceId = 2
	eq((useOn(match, owner, "Snare")), true, "set")
	eq((useOn(match, owner, "Snare")), false, "second trap on the same space")
	match:land(owner)
	ok(match.Traps[2], "owner doesn't spring their own trap")
	setCoins(match, other, 10)
	other.SpaceId = 2
	local text = match:land(other)
	ok(string.find(text, "trap"), "feed mentions the trap")
	eq(match:coinsOf(other), 10 - 5 + Config.Economy.GainSpaceCoins, "paid 5, then the Gain space")
	eq(match.Traps[2], nil, "trap used up")
	match.Traps[2] = { Owner = owner, Coins = 5 }
	third.Shield = true
	setCoins(match, third, 10)
	third.SpaceId = 2
	match:land(third)
	eq(third.Shield, false, "shield broke on the trap")
end)

test("board-specific items only show up on their board", function()
	local match = newMatch()
	table.insert(Items, { Id = "TestOnlyElsewhere", Name = "X", Price = 1, Weight = 1000, Boards = { "Elsewhere" }, Use = function() return "x" end })
	table.insert(Items, { Id = "TestOnlyClassic", Name = "Y", Price = 1, Weight = 0.001, Boards = { "Classic" }, Use = function() return "y" end })
	local ids = {}
	for _, item in match:itemPool() do
		ids[item.Id] = true
	end
	table.remove(Items)
	table.remove(Items)
	eq(ids.TestOnlyElsewhere, nil, "other board's item")
	eq(ids.TestOnlyClassic, true, "this board's item")
	eq(ids.DoubleDice, true, "general items")
end)

test("bots: lucky die onto the Crown, shield up against a visible thief", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.Round = 1
	match.CollectibleSpace = 7
	seat.SpaceId = 3 -- 4 moves away
	setCoins(match, seat, 25)
	match:giveItem(seat, "LuckyDie")
	match:beginTurn(seat)
	local slot, _, face = match:botItemChoice(seat)
	eq(seat.Items[slot], "LuckyDie", "uses the lucky die")
	eq(face, 4, "exact distance")

	local guard = newMatch()
	local me = guard.Seats[1]
	guard.Round = 1
	setCoins(guard, me, 10)
	CoinService.addCollectibles(me.Participant, 1)
	guard:giveItem(me, "DoubleDice")
	guard:giveItem(me, "CoinShield")
	guard:giveItem(guard.Seats[2], "CrownHeist")
	guard:beginTurn(me)
	eq(me.Items[(guard:botItemChoice(me))], "CoinShield", "shield first when someone holds a heist")
end)

test("bots: heist the Crown leader, pickpocket the richest, skip shielded targets", function()
	local match = newMatch()
	local me = match.Seats[1]
	match.Round = 1
	setCoins(match, me, 20)
	CoinService.addCollectibles(match.Seats[2].Participant, 2)
	CoinService.addCollectibles(match.Seats[3].Participant, 3)
	match.Seats[3].Shield = true
	local score, target = BotBrain.itemScore(match, me, "CrownHeist")
	ok(score > 0, "worth a heist")
	eq(target, match.Seats[2], "unshielded Crown holder")
	setCoins(match, me, 10)
	eq((BotBrain.itemScore(match, me, "CrownHeist")), 0, "can't pay the fee")
	setCoins(match, match.Seats[4], 30)
	local _, victim = BotBrain.itemScore(match, me, "Pickpocket")
	eq(victim, match.Seats[4], "richest")
end)

-- Space set 2: gates, tolls, switches, duels, chaos, item spaces -----------------------------------

test("validation: gates must sit on a fork edge", function()
	local data = table.clone(Classic)
	data.Gates = { { Id = "Bad", From = 1, To = 2, Open = true } }
	ok(BoardLayout.validate(data, SpaceTypes), "gate on a non-fork edge not caught")
	data.Gates = { { Id = "Bad", From = 5, To = 9, Open = true } }
	ok(BoardLayout.validate(data, SpaceTypes), "gate on a missing edge not caught")
end)

test("toll shortcut: offered only to those who can pay, and charged", function()
	local match, asked = newMatch({ Path = 2 })
	local seat = match.Seats[1]
	match.CollectibleSpace = 7
	seat.SpaceId = 5
	setCoins(match, seat, 2)
	match:move(seat, 1)
	eq(seat.SpaceId, 6, "can't pay: main road, no question")
	eq(#asked, 0, "not asked")
	seat.SpaceId = 5
	setCoins(match, seat, 10)
	match:move(seat, 1)
	eq(seat.SpaceId, 27, "paid the toll")
	eq(asked[1].Data.Info[2].Toll, 3, "toll shown with the choice")
	ok(string.find(asked[1].Options[2], "toll"), "label says toll")
	eq(match:coinsOf(seat), 10 - 3 - Config.Economy.LoseSpaceCoins, "toll + the Lose space")
end)

test("switch: flipping gates closes the shortcut and changes distances", function()
	local match = newMatch({ Switch = 1, Path = 2 })
	local seat = match.Seats[1]
	eq(match:distance(5, 18), 5, "shortcut open")
	seat.SpaceId = 17
	ok(string.find(match:runSwitch(seat), "closed"), "feed says closed")
	eq(match:distance(5, 18), 13, "shortcut closed")
	seat.SpaceId = 5
	setCoins(match, seat, 50)
	match:move(seat, 1)
	eq(seat.SpaceId, 6, "closed gate isn't offered")
	match:toggleGates()
	eq(match:distance(5, 18), 5, "open again")
end)

test("switch: paying moves the Crown; can't pay, no option", function()
	local match, asked = newMatch({ Switch = function(request)
		return table.find(request.Data.Actions, "Crown") or #request.Options
	end })
	local seat = match.Seats[1]
	seat.SpaceId = 17
	setCoins(match, seat, Config.Economy.CrownMovePrice - 1)
	match:runSwitch(seat)
	eq(table.find(asked[1].Data.Actions, "Crown"), nil, "not offered when broke")
	setCoins(match, seat, 20)
	local before = match.CollectibleSpace
	match:runSwitch(seat)
	ok(match.CollectibleSpace ~= before, "Crown moved")
	eq(match:coinsOf(seat), 20 - Config.Economy.CrownMovePrice, "paid")
end)

test("duel: winner takes the stake, ties draw, only affordable stakes offered", function()
	local match, asked = newMatch({ DuelTarget = 1, DuelStake = function(request)
		return #request.Options -- biggest offered
	end })
	local me, rival = match.Seats[1], match.Seats[2]
	for _, other in match.Seats do
		setCoins(match, other, 0)
	end
	setCoins(match, me, 30)
	setCoins(match, rival, 12)
	local rolls = { 6, 2 }
	match.roll = function()
		return table.remove(rolls, 1)
	end
	local text = match:runDuel(me)
	local stakeRequest = asked[2]
	eq(stakeRequest.Options[#stakeRequest.Options], "10 coins", "20 not offered (rival has 12)")
	ok(string.find(text, "wins 10"), "feed")
	eq(match:coinsOf(me), 40, "winner")
	eq(match:coinsOf(rival), 2, "loser")
	rolls = { 3, 3 }
	setCoins(match, rival, 12)
	ok(string.find(match:runDuel(me), "draw"), "tie")
	eq(match:coinsOf(me), 40, "draw keeps coins")
end)

test("duel: declining or nobody able to pay costs nothing", function()
	local match = newMatch({ DuelTarget = function(request)
		return #request.Options
	end })
	local me = match.Seats[1]
	for _, other in match.Seats do
		setCoins(match, other, 0)
	end
	ok(string.find(match:runDuel(me), "nobody"), "nobody can pay")
	setCoins(match, me, 10)
	setCoins(match, match.Seats[3], 10)
	ok(string.find(match:runDuel(me), "declined"), "declined")
	eq(match:coinsOf(me), 10, "unchanged")
end)

test("every chaos event runs; losses are capped; price surge ends on purchase", function()
	local ChaosEvents = require(Server.Board.ChaosEvents)
	for _, event in ChaosEvents do
		local match = newMatch(nil, 5)
		for i, seat in match.Seats do
			setCoins(match, seat, i * 20)
			seat.SpaceId = match.Board.Order[i * 6]
		end
		local before = match:coinsOf(match.Seats[4])
		local text = event.Apply(match, match.Seats[4], match.Rng)
		ok(type(text) == "string" and #text > 0, event.Id .. " text")
		ok(before - match:coinsOf(match.Seats[4]) <= Config.Economy.ChaosLossCap, event.Id .. " took more than the cap")
		for _, seat in match.Seats do
			ok(match.Board:get(seat.SpaceId), event.Id .. " put a seat off the board")
		end
	end
	local match = newMatch({ Collectible = 1 })
	for _, event in ChaosEvents do
		if event.Id == "PriceSurge" then
			for _ = 1, 5 do
				event.Apply(match, match.Seats[1], match.Rng)
			end
		end
	end
	eq(match.CollectiblePrice, Config.Collectible.Price + Config.Economy.PriceSurgeCap, "surge capped")
	setCoins(match, match.Seats[1], 100)
	match:offerCollectible(match.Seats[1])
	eq(match.CollectiblePrice, Config.Collectible.Price, "price back after a purchase")
	eq(match:coinsOf(match.Seats[1]), 100 - Config.Collectible.Price - Config.Economy.PriceSurgeCap, "paid the surged price")
end)

test("item space: an item, or coins when the bag is full", function()
	local match = newMatch()
	local seat = match.Seats[1]
	seat.SpaceId = 4
	match:land(seat)
	eq(#seat.Items, 1, "got an item")
	for _ = 2, Config.Items.MaxHeld do
		match:giveItem(seat, "Snare")
	end
	match:land(seat)
	eq(match:coinsOf(seat), Config.Economy.ItemSpaceFallbackCoins, "full bag -> coins")
end)

test("bots: flip a gate that helps, duel the leader, gamble only when behind", function()
	local match = newMatch()
	local me = match.Seats[1]
	match:toggleGates() -- shortcut closed
	me.SpaceId = 3
	match.CollectibleSpace = 20 -- far up the shortcut side
	local actions = { "Gates", "None" }
	eq(BotBrain.chooseSwitch(match, me, actions), 1, "opens the shortcut it needs")
	match:toggleGates() -- open
	eq(BotBrain.chooseSwitch(match, me, actions), 2, "leaves an open shortcut alone")

	CoinService.addCollectibles(match.Seats[3].Participant, 1)
	local target = match:botDecision(me, { Kind = "DuelTarget", Options = { "a", "b", "c", "No" }, Default = 4, Data = { Seats = { match.Seats[2], match.Seats[3], match.Seats[4] } } })
	eq(target, 2, "duels the Crown leader")
	local stake = { Kind = "DuelStake", Options = { "5", "10", "20" }, Default = 1, Data = { Stakes = { 5, 10, 20 } } }
	eq(match:botDecision(me, stake), 3, "behind: big stake")
	CoinService.addCollectibles(me.Participant, 2)
	eq(match:botDecision(me, stake), 1, "ahead: small stake")
end)

-- Comeback ----------------------------------------------------------------------------------------

test("comeback: underdog needs the round and the Crown gap", function()
	local match = newMatch()
	local me = match.Seats[1]
	CoinService.addCollectibles(match.Seats[2].Participant, Config.Comeback.UnderdogGap)
	match.Round = Config.Comeback.StartRound - 1
	eq(match:isUnderdog(me), false, "too early")
	match.Round = Config.Comeback.StartRound
	eq(match:isUnderdog(me), true, "behind by the gap")
	eq(match:isUnderdog(match.Seats[2]), false, "the leader")
	CoinService.addCollectibles(me.Participant, 1)
	eq(match:isUnderdog(me), false, "gap closed")
end)

test("comeback: underdog Crown discount, never below the floor", function()
	local match, asked = newMatch({ Collectible = 1 })
	local me = match.Seats[1]
	match.Round = Config.Comeback.StartRound
	CoinService.addCollectibles(match.Seats[2].Participant, 3)
	eq(match:collectiblePriceFor(me), Config.Collectible.Price - Config.Comeback.UnderdogDiscount, "discount")
	eq(match:collectiblePriceFor(match.Seats[2]), Config.Collectible.Price, "leader pays full")
	setCoins(match, me, 30)
	match:offerCollectible(me)
	eq(match:coinsOf(me), 30 - (Config.Collectible.Price - Config.Comeback.UnderdogDiscount), "paid the discounted price")
	ok(string.find(asked[1].Prompt, "discount"), "prompt says discount")
	match.CollectiblePrice = Config.Comeback.MinCrownPrice + 1
	CoinService.addCollectibles(match.Seats[2].Participant, 3)
	eq(match:collectiblePriceFor(me), Config.Comeback.MinCrownPrice, "floor")
end)

test("comeback: last place gets catch-up coins from StartRound on", function()
	local match = newMatch()
	eq(match:startRound(1), nil, "round 1: nothing")
	for i, seat in match.Seats do
		setCoins(match, seat, 10 + i)
	end
	setCoins(match, match.Seats[1], 2)
	setCoins(match, match.Seats[2], 2)
	local text = match:startRound(Config.Comeback.StartRound)
	ok(text and string.find(text, "Catch%-up"), "feed")
	eq(match:coinsOf(match.Seats[1]), 2 + Config.Comeback.LastPlaceCoins, "tied last 1")
	eq(match:coinsOf(match.Seats[2]), 2 + Config.Comeback.LastPlaceCoins, "tied last 2")
	eq(match:coinsOf(match.Seats[4]), 14, "leader untouched")
	local even = newMatch()
	eq(even:startRound(Config.Comeback.StartRound), nil, "everyone tied: nothing")
end)

test("comeback: final frenzy doubles Gain and Lose spaces in the last round only", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.Round = match.Rounds - 1
	seat.SpaceId = 2
	match:land(seat)
	eq(match:coinsOf(seat), Config.Economy.GainSpaceCoins, "normal round")
	match.Round = match.Rounds
	eq(match:isFrenzy(), true, "frenzy")
	match:land(seat)
	eq(match:coinsOf(seat), Config.Economy.GainSpaceCoins * (1 + Config.Comeback.FrenzyMultiplier), "doubled gain")
end)

test("comeback: underdogs get better gift odds for items and Crowns only", function()
	local match = newMatch()
	local me = match.Seats[1]
	match.Round = Config.Comeback.StartRound
	eq(match:rewardsFor(me), Config.Economy.Rewards, "not an underdog: normal table")
	CoinService.addCollectibles(match.Seats[2].Participant, 3)
	local boosted = match:rewardsFor(me)
	for i, reward in Config.Economy.Rewards do
		local factor = if reward.Kind == "Collectible" or reward.Kind == "Item" then Config.Comeback.UnderdogGiftBoost else 1
		eq(boosted[i].Weight, reward.Weight * factor, reward.Kind .. " weight")
	end
end)

-- Bonuses -----------------------------------------------------------------------------------------

test("stats: spaces travelled, coins earned (not balance), minigame points", function()
	local match = newMatch()
	local seat = match.Seats[1]
	match.CollectibleSpace = 30
	match:move(seat, 2) -- lands on 3 (Gain)
	eq(seat.Stats.SpacesMoved, 2, "spaces")
	eq(seat.Stats.CoinsEarned, Config.Economy.GainSpaceCoins, "space coins")
	match:changeCoins(seat, -2)
	eq(seat.Stats.CoinsEarned, Config.Economy.GainSpaceCoins, "losses don't reduce earned")
	match:recordMinigame(
		{ { Participant = seat.Participant, Placement = 1 }, { Participant = match.Seats[2].Participant, Placement = 2 } },
		{ { Id = seat.Participant.Id, Coins = 10 }, { Id = match.Seats[2].Participant.Id, Coins = 6 } }
	)
	eq(seat.Stats.MinigamePoints, Config.MinigamePointsByPlacement[1], "1st place points")
	eq(match.Seats[2].Stats.MinigamePoints, Config.MinigamePointsByPlacement[2], "2nd place points")
	eq(seat.Stats.CoinsEarned, Config.Economy.GainSpaceCoins + 10, "minigame coins")
end)

test("bonuses: one Crown each, every tied leader wins", function()
	local match = newMatch()
	local a, b, c, d = table.unpack(match.Seats)
	a.Stats = { MinigamePoints = 6, CoinsEarned = 20, SpacesMoved = 10 }
	b.Stats = { MinigamePoints = 6, CoinsEarned = 15, SpacesMoved = 12 }
	c.Stats = { MinigamePoints = 2, CoinsEarned = 30, SpacesMoved = 12 }
	d.Stats = { MinigamePoints = 0, CoinsEarned = 5, SpacesMoved = 3 }
	local awarded = match:awardBonuses()
	eq(#awarded, #Config.Bonuses, "every bonus reported")
	eq(#awarded[1].Winners, 2, "minigame tie: both win")
	eq(#awarded[2].Winners, 1, "coin collector")
	eq(awarded[2].Winners[1], c, "most earned")
	eq(#awarded[3].Winners, 2, "explorer tie")
	eq(match:collectiblesOf(a), 1, "a")
	eq(match:collectiblesOf(b), 2, "b")
	eq(match:collectiblesOf(c), 2, "c")
	eq(match:collectiblesOf(d), 0, "d")
end)

test("bonuses: ties can be configured to award nobody; zero scores win nothing", function()
	local match = newMatch()
	for _, seat in match.Seats do
		seat.Stats = { MinigamePoints = 4, CoinsEarned = 0, SpacesMoved = 0 }
	end
	local strict = { { Id = "X", Stat = "MinigamePoints", Crowns = 1, AwardTies = false }, { Id = "Y", Stat = "CoinsEarned", Crowns = 1, AwardTies = true } }
	local awarded = match:awardBonuses(strict)
	eq(#awarded[1].Winners, 0, "tie, AwardTies=false")
	eq(#awarded[2].Winners, 0, "nobody earned anything")
	for _, seat in match.Seats do
		eq(match:collectiblesOf(seat), 0, "no crowns handed out")
	end
end)

test("bonus Crowns change the final standings", function()
	local match = newMatch()
	setCoins(match, match.Seats[1], 50)
	match.Seats[4].Stats.SpacesMoved = 9
	eq(match:standings()[1].Participant, match.Seats[1].Participant, "before: coins lead")
	match:awardBonuses()
	eq(match:standings()[1].Participant, match.Seats[4].Participant, "after: bonus Crown leads")
end)

-- Standings ---------------------------------------------------------------------------------------

test("standings: collectibles first, coins break ties, full ties share", function()
	local rows = Match.rank({
		{ Participant = "a", SeatIndex = 1, Collectibles = 1, Coins = 50 },
		{ Participant = "b", SeatIndex = 2, Collectibles = 2, Coins = 0 },
		{ Participant = "c", SeatIndex = 3, Collectibles = 1, Coins = 50 },
		{ Participant = "d", SeatIndex = 4, Collectibles = 1, Coins = 60 },
	})
	eq(rows[1].Participant, "b", "1st")
	eq(rows[1].Placement, 1, "1st placement")
	eq(rows[2].Participant, "d", "2nd")
	eq(rows[2].Placement, 2, "2nd placement")
	eq(rows[3].Placement, 3, "tie placement a")
	eq(rows[4].Placement, 3, "tie placement c")
end)

test("match standings read the live wallets", function()
	local match = newMatch()
	setCoins(match, match.Seats[3], 9)
	CoinService.addCollectibles(match.Seats[4].Participant, 1)
	local rows = match:standings()
	eq(rows[1].Participant, match.Seats[4].Participant, "collectible holder wins")
	eq(rows[2].Participant, match.Seats[3].Participant, "coins second")
end)

-- Runner ------------------------------------------------------------------------------------------

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[BoardTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	CoinService.resetAll()
	print(("[BoardTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
