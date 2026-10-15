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
local function newMatch(answers, seed: number?)
	CoinService.resetAll()
	local asked = {}
	local board = BoardLayout.load(Classic, SpaceTypes)
	local match = Match.new(board, fakeParticipants(4), { Rounds = 3 }, {
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

test("shop sells a cosmetic and equips it", function()
	local match, asked = newMatch({ Shop = 1 })
	local seat = match.Seats[1]
	setCoins(match, seat, 50)
	match:visitShop(seat)
	local request = asked[1]
	local item = request.Data.Items[1]
	ok(Inventory.owns(seat.Participant.Id, item.Id), "not owned")
	eq(Inventory.getEquipped(seat.Participant.Id)[item.Slot], item.Id, "not equipped")
	eq(match:coinsOf(seat), 50 - item.Price, "coins")
	eq(request.Options[#request.Options], "Leave", "last option")
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
	eq(match:botDecision(seat, { Kind = "Collectible", Options = { "Buy", "Not now" }, Default = 1 }, 0.5), 1, "buy")
	local shop = {
		Kind = "Shop",
		Options = { "A", "Leave" },
		Default = 2,
		Data = { Items = { { Price = 10 } } },
	}
	setCoins(match, seat, 12)
	eq(match:botDecision(seat, shop, 1), 2, "skilled bot saves")
	eq(match:botDecision(seat, shop, 0), 1, "sloppy bot spends")
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
