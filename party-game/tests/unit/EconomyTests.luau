--[[
	Unit tests for cosmetics (ownership, equip requests, drawing) and the persistence
	boundary (profiles vs match coins). Run with RunAll (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local Config = require(ReplicatedStorage.PartyShared.Config)
local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local CoinService = require(Server.CoinService)
local CosmeticService = require(Server.CosmeticService)
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
local function uniqueId(prefix: string): string
	counter += 1
	return ("%s_t%d_%d"):format(prefix, counter, math.floor(os.clock() * 1000))
end

-- A bare character: just enough parts for the cosmetic drawers.
local function dummyCharacter()
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Position = Vector3.new(0, 2, 0)
	head.Anchored = true
	head.Parent = model
	return model
end

local function countTagged(model: Model): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if string.sub(descendant.Name, 1, 13) == "PartyCosmetic" then
			count += 1
		end
	end
	return count
end

-- Cosmetics -----------------------------------------------------------------------------------

test("every cosmetic has a slot and a placeholder visual", function()
	for _, item in Cosmetics.Items do
		ok(table.find(Cosmetics.Slots, item.Slot), item.Id .. " slot")
		ok(type(item.Visual) == "table" and type(item.Visual.Kind) == "string", item.Id .. " visual")
	end
end)

test("clients can't equip what they don't own (or junk)", function()
	local owner = uniqueId("player")
	local item = Cosmetics.Items[1]
	eq(CosmeticService.requestEquip(owner, item.Id), false, "unowned")
	eq(CosmeticService.requestEquip(owner, "made_up"), false, "unknown id")
	eq(CosmeticService.requestEquip(owner, 42), false, "number")
	eq(CosmeticService.requestEquip(owner, { item.Id }), false, "table")
	eq(next(Inventory.getEquipped(owner)), nil, "nothing equipped")
	Inventory.grant(owner, item.Id)
	eq(CosmeticService.requestEquip(owner, item.Id), true, "owned")
	eq(Inventory.getEquipped(owner)[item.Slot], item.Id, "equipped")
	eq(CosmeticService.requestUnequip(owner, "NotASlot"), false, "bad slot")
	eq(CosmeticService.requestUnequip(owner, item.Slot), true, "unequip")
	eq(Inventory.getEquipped(owner)[item.Slot], nil, "taken off")
	Inventory.forget(owner)
end)

test("equipping replaces the item in the same slot only", function()
	local owner = uniqueId("player")
	Inventory.grant(owner, "hat_party")
	Inventory.grant(owner, "hat_propeller")
	Inventory.grant(owner, "trail_rainbow")
	CosmeticService.requestEquip(owner, "hat_party")
	CosmeticService.requestEquip(owner, "trail_rainbow")
	CosmeticService.requestEquip(owner, "hat_propeller")
	local equipped = Inventory.getEquipped(owner)
	eq(equipped.Hat, "hat_propeller", "hat swapped")
	eq(equipped.Trail, "trail_rainbow", "trail kept")
	Inventory.forget(owner)
end)

test("cosmetics are drawn, redrawn without duplicates, and cleared", function()
	local character = dummyCharacter()
	CosmeticService.apply(character, { Hat = "hat_party", Trail = "trail_confetti", Emote = "emote_wave" })
	local drawn = countTagged(character)
	ok(drawn >= 4, "expected hat + trail parts + sparkles, got " .. drawn)
	ok(character:FindFirstChild("PartyCosmetic_Hat"), "hat on the character")
	eq(character:GetAttribute("PartyCosmeticKey"), "Hat=hat_party;Trail=trail_confetti;Emote=emote_wave", "key")
	CosmeticService.apply(character, { Hat = "hat_party", Trail = "trail_confetti", Emote = "emote_wave" })
	eq(countTagged(character), drawn, "redraw duplicated parts")
	CosmeticService.apply(character, {})
	eq(countTagged(character), 0, "cleared")
	character:Destroy()
end)

test("inventory changes notify listeners", function()
	local owner = uniqueId("bot")
	local heard = 0
	Inventory.onChanged(function(id)
		if id == owner then
			heard += 1
		end
	end)
	Inventory.grant(owner, "hat_party")
	Inventory.equip(owner, "hat_party")
	task.wait() -- listeners run in their own threads
	eq(heard, 2, "grant + equip")
	Inventory.forget(owner)
end)

-- Profiles ------------------------------------------------------------------------------------

test("profiles: new players get a clean template", function()
	local store = ProfileStore.new(MemoryBackend.new())
	local profile = store:load("player_1")
	eq(profile.Coins, 0, "coins")
	eq(next(profile.Owned), nil, "owned")
	eq(profile.Version, ProfileStore.Version, "version")
end)

test("profiles: owned + equipped cosmetics and bank coins survive leaving and rejoining", function()
	local backend = MemoryBackend.new()
	local store = ProfileStore.new(backend)
	local key = uniqueId("player")
	local profile = store:load(key)
	Inventory.attach(key, profile.Owned, profile.Equipped)
	Inventory.grant(key, "trail_rainbow")
	Inventory.equip(key, "trail_rainbow")
	store:addCoins(key, 30)
	eq(store:release(key), true, "saved on leave")
	Inventory.forget(key)
	eq(store:get(key), nil, "released")

	local again = store:load(key)
	eq(again.Coins, 30, "bank coins")
	eq(again.Owned.trail_rainbow, true, "owned")
	eq(again.Equipped.Trail, "trail_rainbow", "equipped")
	Inventory.attach(key, again.Owned, again.Equipped)
	eq(Inventory.owns(key, "trail_rainbow"), true, "inventory sees the saved item")
	Inventory.forget(key)
end)

test("profiles: match coins and Crowns never touch the profile", function()
	local backend = MemoryBackend.new()
	local store = ProfileStore.new(backend)
	local key = uniqueId("player")
	local profile = store:load(key)
	local participant = { Id = key, Name = "P", IsBot = false }
	CoinService.add(participant, 50)
	CoinService.addCollectibles(participant, 2)
	eq(profile.Coins, 0, "match coins leaked into the bank")
	eq(profile.Crowns, nil, "Crowns leaked into the profile")
	store:save(key)
	local saved = backend.Data[key]
	eq(saved.Coins, 0, "saved bank coins")
	eq(saved.Crowns, nil, "no Crowns field saved")
	CoinService.resetAll()
	store:addCoins(key, 12)
	eq(CoinService.get(participant), 0, "bank coins leaked into the match wallet")
	eq(store:get(key).Coins, 12, "bank kept after the match reset")
end)

test("profiles: damaged saves are repaired, unowned equips dropped", function()
	local backend = MemoryBackend.new()
	backend.Data.player_9 = {
		Coins = -5,
		Owned = { hat_party = true, [7] = true, trail_rainbow = "yes" },
		Equipped = { Hat = "hat_party", Trail = "trail_rainbow", Emote = 3 },
		Junk = "x",
	}
	local profile = ProfileStore.new(backend):load("player_9")
	eq(profile.Coins, 0, "negative coins")
	eq(profile.Owned.hat_party, true, "valid owned kept")
	eq(profile.Owned.trail_rainbow, nil, "bad owned dropped")
	eq(profile.Equipped.Hat, "hat_party", "valid equip kept")
	eq(profile.Equipped.Trail, nil, "equip of unowned dropped")
	eq(profile.Equipped.Emote, nil, "junk equip dropped")
	eq(profile.Junk, nil, "unknown fields dropped")
end)

test("profiles: a failed load never saves over the real data", function()
	local broken = {
		Writes = 0,
		read = function()
			error("service down")
		end,
		write = function(self)
			self.Writes += 1
		end,
	}
	local store = ProfileStore.new(broken)
	local profile = store:load("player_5")
	ok(profile ~= nil, "still playable")
	eq(store:save("player_5"), false, "save refused")
	eq(broken.Writes, 0, "nothing written")
end)

-- DataStore layer (fake store) ---------------------------------------------------------------

-- Behaves like a DataStore's UpdateAsync; `failures` makes the next N calls throw.
local function fakeStore()
	local store = { Data = {}, Failures = 0, Calls = 0 }
	function store:UpdateAsync(key, transform)
		self.Calls += 1
		if self.Failures > 0 then
			self.Failures -= 1
			error("DataStore request was throttled")
		end
		local result = transform(ProfileStore.deepCopy(self.Data[key]))
		if result ~= nil then
			self.Data[key] = ProfileStore.deepCopy(result)
		end
		return result
	end
	return store
end

local DataStoreBackend = require(Server.Profiles.DataStoreBackend)
local clock = 1000
local function server(store, jobId)
	return DataStoreBackend.new({
		Store = store,
		JobId = jobId,
		Now = function()
			return clock
		end,
		Wait = function() end,
	})
end

test("datastore: load claims the session, save keeps it, release frees it", function()
	local store = fakeStore()
	local a = server(store, "A")
	eq(a:read("player_1"), nil, "new player")
	eq(store.Data.player_1.Session.JobId, "A", "locked by A")
	a:write("player_1", { Coins = 5 })
	eq(store.Data.player_1.Data.Coins, 5, "saved")
	eq(store.Data.player_1.Session.JobId, "A", "still locked")
	a:write("player_1", { Coins = 6 }, true)
	eq(store.Data.player_1.Session, nil, "released")
	local b = server(store, "B")
	eq(b:read("player_1").Coins, 6, "another server loads the released profile")
end)

test("datastore: a live lock on another server blocks loading and saving", function()
	local store = fakeStore()
	server(store, "A"):read("player_2")
	local b = server(store, "B")
	local loaded = pcall(function()
		b:read("player_2")
	end)
	eq(loaded, false, "B must not load while A holds the lock")
	local saved = pcall(function()
		b:write("player_2", { Coins = 999 })
	end)
	eq(saved, false, "B must not save over A")
	eq(store.Data.player_2.Data, nil, "data untouched")
end)

test("datastore: an abandoned lock (crashed server) is taken over after expiry", function()
	local store = fakeStore()
	server(store, "A"):read("player_3")
	clock += DataStoreBackend.LOCK_EXPIRY + 1
	local b = server(store, "B")
	b:read("player_3")
	eq(store.Data.player_3.Session.JobId, "B", "taken over")
	local stale = pcall(function()
		server(store, "A"):write("player_3", { Coins = 1 })
	end)
	eq(stale, false, "the old server can't save over the new one")
end)

test("datastore: retries through temporary failures, gives up after RETRIES", function()
	local store = fakeStore()
	local a = server(store, "A")
	store.Failures = DataStoreBackend.RETRIES - 1
	a:read("player_4")
	eq(store.Data.player_4.Session.JobId, "A", "loaded after retries")
	store.Failures = DataStoreBackend.RETRIES
	local ok = pcall(function()
		a:write("player_4", { Coins = 3 })
	end)
	eq(ok, false, "gave up")
end)

test("profiles over the datastore: round trip, and a blocked load plays unsaved", function()
	local store = fakeStore()
	local profiles = ProfileStore.new(server(store, "A"))
	local profile = profiles:load("player_6")
	profile.Coins = 40
	profile.Owned.hat_party = true
	eq(profiles:release("player_6"), true, "saved on leave")
	local again = ProfileStore.new(server(store, "B")):load("player_6")
	eq(again.Coins, 40, "coins")
	eq(again.Owned.hat_party, true, "cosmetic")

	local blocked = ProfileStore.new(server(store, "C"))
	local fresh = blocked:load("player_6") -- B still holds it
	eq(fresh.Coins, 0, "blocked load gets a blank profile")
	fresh.Coins = 1
	eq(blocked:save("player_6"), false, "and never saves it")
	eq(store.Data.player_6.Data.Coins, 40, "real data intact")
end)

test("profiles: backend choice keeps Studio off real saves", function()
	local Profiles = require(Server.Profiles)
	eq(Profiles.chooseBackend("Auto", true), "Memory", "Studio")
	eq(Profiles.chooseBackend("Auto", false), "DataStore", "live")
	eq(Profiles.chooseBackend("Memory", false), "Memory", "forced memory")
	eq(Profiles.chooseBackend("DataStore", true), "DataStore", "forced datastore")
	if Config.Profile.Backend == "Auto" then
		eq(Profiles.backendName, "Memory", "this Studio session")
	else
		ok(table.find({ "Memory", "DataStore", "Unavailable" }, Profiles.backendName), "known backend")
	end
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[EconomyTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	CoinService.resetAll()
	print(("[EconomyTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
