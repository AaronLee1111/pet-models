--[[
	Unit tests for the permanent Cosmetics Shop (bank coins). Run with RunAll (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local Net = require(ReplicatedStorage.PartyShared.Net)
local CoinService = require(Server.CoinService)
local CosmeticShop = require(Server.CosmeticShop)
local Inventory = require(Server.Inventory)
local MemoryBackend = require(Server.Profiles.MemoryBackend)
local ProfileStore = require(Server.Profiles.ProfileStore)

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

local counter = 0
-- A fresh shop with one loaded player profile holding `coins` bank coins.
local function setup(coins: number)
	counter += 1
	local key = ("player_shop%d_%d"):format(counter, math.floor(os.clock() * 1000))
	local backend = MemoryBackend.new()
	local store = ProfileStore.new(backend)
	local profile = store:load(key)
	profile.Coins = coins
	Inventory.attach(key, profile.Owned, profile.Equipped)
	local clock = 100
	local shop = CosmeticShop.new(store, Inventory, function()
		return clock
	end)
	local function tick(seconds)
		clock += seconds or 1
	end
	return shop, key, store, backend, tick
end

local function itemOf(rarity: string, slot: string?)
	for _, item in Cosmetics.Items do
		if item.Rarity == rarity and (slot == nil or item.Slot == slot) then
			return item
		end
	end
	error("no " .. rarity .. " item")
end

test("every cosmetic has a bank price", function()
	for _, item in Cosmetics.Items do
		local price = Cosmetics.bankPrice(item)
		ok(type(price) == "number" and price > 0, item.Id .. " has no bank price")
	end
	ok(Cosmetics.bankPrice(itemOf("Epic")) > Cosmetics.bankPrice(itemOf("Common")), "rarer costs more")
end)

test("buying spends bank coins, grants, equips into an empty slot and saves", function()
	local shop, key, store, backend = setup(200)
	local item = itemOf("Common", "Hat")
	local bought, code = shop:buy(key, item.Id)
	eq(bought, true, "bought")
	eq(code, "ok", "code")
	eq(store:get(key).Coins, 200 - Cosmetics.bankPrice(item), "bank coins spent")
	eq(Inventory.owns(key, item.Id), true, "owned")
	eq(Inventory.getEquipped(key).Hat, item.Id, "equipped into the empty slot")
	task.wait() -- the save runs in its own thread
	eq(backend.Data[key].Owned[item.Id], true, "saved to the profile backend")
	eq(backend.Data[key].Coins, 200 - Cosmetics.bankPrice(item), "saved balance")
	Inventory.forget(key)
end)

test("not enough bank coins: refused, nothing changes", function()
	local shop, key, store = setup(10)
	local item = itemOf("Common")
	local bought, code, text = shop:buy(key, item.Id)
	eq(bought, false, "refused")
	eq(code, "insufficient", "code")
	ok(string.find(text, "costs"), "says the price")
	eq(store:get(key).Coins, 10, "coins kept")
	eq(Inventory.owns(key, item.Id), false, "not owned")
	Inventory.forget(key)
end)

test("match coins can't pay for permanent cosmetics, and purchases don't touch them", function()
	local shop, key, store, _, tick = setup(0)
	local participant = { Id = key, Name = "P", IsBot = false }
	CoinService.resetAll()
	CoinService.add(participant, 1000)
	local item = itemOf("Common")
	eq((shop:buy(key, item.Id)), false, "1000 match coins don't count")
	store:get(key).Coins = 500
	tick()
	eq((shop:buy(key, item.Id)), true, "bank coins do")
	eq(CoinService.get(participant), 1000, "match coins untouched")
	CoinService.resetAll()
	Inventory.forget(key)
end)

test("duplicate purchase refused without charging", function()
	local shop, key, store, _, tick = setup(500)
	local item = itemOf("Rare")
	shop:buy(key, item.Id)
	local after = store:get(key).Coins
	tick()
	local bought, code = shop:buy(key, item.Id)
	eq(bought, false, "second buy")
	eq(code, "owned", "code")
	eq(store:get(key).Coins, after, "not charged twice")
	Inventory.forget(key)
end)

test("invalid and malformed item ids are refused safely", function()
	local shop, key, store, _, tick = setup(500)
	for _, bad in { nil, 5, true, {}, "not_an_item", string.rep("x", 500) } do
		tick()
		local bought, code = shop:buy(key, bad)
		eq(bought, false, "refused " .. tostring(bad))
		ok(code == "bad_request" or code == "unknown_item", "code for " .. tostring(bad) .. ": " .. tostring(code))
	end
	eq(store:get(key).Coins, 500, "nothing charged")
	eq(#Inventory.getOwned(key), 0, "nothing granted")
	Inventory.forget(key)
end)

test("rapid repeat requests are throttled", function()
	local shop, key, store = setup(1000)
	local a, b = Cosmetics.Items[1], Cosmetics.Items[2]
	eq((shop:buy(key, a.Id)), true, "first")
	local bought, code = shop:buy(key, b.Id) -- same instant
	eq(bought, false, "second too soon")
	eq(code, "too_fast", "code")
	eq(store:get(key).Coins, 1000 - Cosmetics.bankPrice(a), "only charged once")
	Inventory.forget(key)
end)

test("no loaded profile: refused", function()
	local store = ProfileStore.new(MemoryBackend.new())
	local shop = CosmeticShop.new(store, Inventory)
	local bought, code = shop:buy("player_never_loaded", Cosmetics.Items[1].Id)
	eq(bought, false, "refused")
	eq(code, "no_profile", "code")
end)

test("a spoofed price in the request is ignored: the catalog price is charged", function()
	local store = ProfileStore.new(MemoryBackend.new())
	local sent = {}
	CosmeticShop.start(store, Inventory, function(_, message)
		table.insert(sent, message)
	end, function() end)
	local fakePlayer = { UserId = 987654 }
	local key = "player_987654"
	local profile = store:load(key)
	profile.Coins = 300
	Inventory.attach(key, profile.Owned, profile.Equipped)
	local item = itemOf("Epic")
	local handled = CosmeticShop.handleInput(fakePlayer :: any, { Kind = Net.Input.BuyCosmetic, ItemId = item.Id, Price = 0 })
	eq(handled, true, "handled")
	eq(sent[1].Ok, true, "bought")
	eq(store:get(key).Coins, 300 - Cosmetics.bankPrice(item), "charged the real price")
	eq(CosmeticShop.handleInput(fakePlayer :: any, { Kind = "Roll" }), false, "other inputs pass through")
	Inventory.forget(key)
end)

test("owned items equip and unequip; unowned can't be equipped", function()
	local shop, key, _, _, tick = setup(1000)
	local hat1, hat2 = itemOf("Common", "Hat"), itemOf("Epic", "Hat")
	eq(Inventory.equip(key, hat2.Id), false, "unowned")
	shop:buy(key, hat1.Id)
	tick()
	shop:buy(key, hat2.Id)
	eq(Inventory.getEquipped(key).Hat, hat1.Id, "a second hat doesn't replace the worn one")
	eq(Inventory.equip(key, hat2.Id), true, "swap to the new hat")
	Inventory.unequip(key, "Hat")
	eq(Inventory.getEquipped(key).Hat, nil, "removed")
	Inventory.forget(key)
end)

test("reconnecting (in-memory backend) keeps purchases, balance and what's worn", function()
	local shop, key, store = setup(250)
	local trail = itemOf("Common", "Trail")
	shop:buy(key, trail.Id)
	local balance = store:get(key).Coins
	eq(store:release(key), true, "saved on leave")
	Inventory.forget(key)
	local profile = store:load(key)
	Inventory.attach(key, profile.Owned, profile.Equipped)
	eq(profile.Coins, balance, "balance")
	eq(Inventory.owns(key, trail.Id), true, "still owned")
	eq(Inventory.getEquipped(key).Trail, trail.Id, "still worn")
	Inventory.forget(key)
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[ShopTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[ShopTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
