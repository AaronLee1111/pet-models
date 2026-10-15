--[[
	Profiles
	The game's door to permanent player data (ProfileStore). Loads a profile when a player
	joins, hands their cosmetic tables to Inventory, and saves when they leave or the server
	closes. Bots never have profiles.

	  Profiles.start()                    call once from Main
	  Profiles.get(player) -> profile?    { Coins, Owned, Equipped } (see ProfileStore)
	  Profiles.addBankCoins(player, n)    permanent coins
	  Profiles.bankCoins(player) -> number

	Backend: Config.Profile.Backend ("Memory" now; "DataStore" once DataStoreBackend is done).
	Real saving plugs in ONLY in DataStoreBackend.luau; nothing else needs to change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Inventory = require(script.Parent.Inventory)
local DataStoreBackend = require(script.DataStoreBackend)
local MemoryBackend = require(script.MemoryBackend)
local ProfileStore = require(script.ProfileStore)

local Profiles = {}

Profiles.ProfileStore = ProfileStore
Profiles.MemoryBackend = MemoryBackend

local backend = if Config.Profile.Backend == "DataStore" then DataStoreBackend.new() else MemoryBackend.new()
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
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Profiles.store:save(keyOf(player))
		end
	end)
end

return Profiles
