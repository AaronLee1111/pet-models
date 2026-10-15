--[[
	Profiles
	The game's door to permanent player data (ProfileStore). Loads a profile when a player
	joins, hands their cosmetic tables to Inventory, and saves when they leave or the server
	closes. Bots never have profiles.

	  Profiles.start()                    call once from Main
	  Profiles.get(player) -> profile?    { Coins, Owned, Equipped } (see ProfileStore)
	  Profiles.addBankCoins(player, n)    permanent coins
	  Profiles.bankCoins(player) -> number

	Backend: Config.Profile.Backend ("Auto" = DataStore live, Memory in Studio). Saves happen
	on leave (and release the session lock), every Config.Profile.AutosaveInterval, and at
	shutdown (BindToClose). A profile that failed to load is never saved over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Inventory = require(script.Parent.Inventory)
local DataStoreBackend = require(script.DataStoreBackend)
local MemoryBackend = require(script.MemoryBackend)
local ProfileStore = require(script.ProfileStore)

local Profiles = {}

Profiles.ProfileStore = ProfileStore
Profiles.MemoryBackend = MemoryBackend

function Profiles.chooseBackend(setting: string, isStudio: boolean): string
	if setting == "Auto" then
		return if isStudio then "Memory" else "DataStore"
	end
	return if setting == "DataStore" then "DataStore" else "Memory"
end

-- When DataStores can't be reached at all (e.g. an unpublished place), every profile loads
-- blank and is never saved: better than pretending to save, or crashing the server.
local UnavailableBackend = {
	read = function()
		error("DataStores are unavailable on this server")
	end,
	write = function()
		error("DataStores are unavailable on this server")
	end,
}

Profiles.backendName = Profiles.chooseBackend(Config.Profile.Backend, RunService:IsStudio())
local backend
if Profiles.backendName == "DataStore" then
	local ok, result = pcall(DataStoreBackend.new)
	if ok then
		backend = result
	else
		warn("[Profiles] DataStore unavailable, profiles won't save this session: " .. tostring(result))
		Profiles.backendName = "Unavailable"
		backend = UnavailableBackend
	end
else
	backend = MemoryBackend.new()
end
Profiles.store = ProfileStore.new(backend)

local function keyOf(player: Player): string
	return "player_" .. player.UserId
end

function Profiles.get(player: Player)
	return Profiles.store:get(keyOf(player))
end

function Profiles.bankCoins(player: Player): number
	local profile = Profiles.get(player)
	return if profile then profile.Coins else 0
end

function Profiles.addBankCoins(player: Player, amount: number): number
	return Profiles.store:addCoins(keyOf(player), amount)
end

local function onJoin(player: Player)
	local key = keyOf(player)
	local profile = Profiles.store:load(key)
	if not player.Parent then
		Profiles.store:release(key) -- left while loading
		return
	end
	-- Inventory edits these tables directly, so cosmetics bought in a match are saved too.
	Inventory.attach(key, profile.Owned, profile.Equipped)
end

function Profiles.start()
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		Profiles.store:release(keyOf(player))
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Profile.AutosaveInterval)
			for _, key in Profiles.store:keys() do
				task.spawn(Profiles.store.save, Profiles.store, key)
			end
		end
	end)
	-- Shutdown: save and release everyone in parallel, and wait (Roblox allows ~30 s).
	game:BindToClose(function()
		local pending = 0
		for _, key in Profiles.store:keys() do
			pending += 1
			task.spawn(function()
				Profiles.store:release(key)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return Profiles
