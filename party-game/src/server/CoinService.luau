--[[
	CoinService
	Server-authoritative wallets: coins and the match collectible (Config.Collectible) for
	every seat, players and bots alike, keyed by participant Id. Real players also get
	leaderstats so the values show in the Roblox player list.

	Wallets are per match: BoardGame calls resetAll() when a match starts.
	(No persistence yet; add DataStore saving once the session systems are stable.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local CoinService = {}

local wallets: { [string]: { Coins: number, Collectibles: number } } = {}
local playersById: { [string]: Player } = {}

local function setupPlayer(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	-- Collectible first: it's what the player list sorts by.
	local collectibles = Instance.new("IntValue")
	collectibles.Name = Config.Collectible.Plural
	collectibles.Parent = leaderstats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

local function wallet(participant)
	local entry = wallets[participant.Id]
	if not entry then
		entry = { Coins = 0, Collectibles = 0 }
		wallets[participant.Id] = entry
	end
	if participant.Player then
		playersById[participant.Id] = participant.Player
	end
	return entry
end

-- Copies a wallet into the owner's leaderstats (real players only).
local function mirror(id: string)
	local player = playersById[id]
	local entry = wallets[id]
	local leaderstats = player and player.Parent and player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local coins = leaderstats:FindFirstChild("Coins")
	local collectibles = leaderstats:FindFirstChild(Config.Collectible.Plural)
	if coins then
		coins.Value = if entry then entry.Coins else 0
	end
	if collectibles then
		collectibles.Value = if entry then entry.Collectibles else 0
	end
end

function CoinService.get(participant): number
	return wallet(participant).Coins
end

function CoinService.getCollectibles(participant): number
	return wallet(participant).Collectibles
end

-- Adds (or with a negative amount, removes) coins. Never goes below 0.
-- Returns the new total and how many coins actually changed hands.
function CoinService.add(participant, amount: number): (number, number)
	local entry = wallet(participant)
	local before = entry.Coins
	entry.Coins = math.max(0, before + math.floor(amount))
	mirror(participant.Id)
	return entry.Coins, entry.Coins - before
end

function CoinService.addCollectibles(participant, amount: number): number
	local entry = wallet(participant)
	entry.Collectibles = math.max(0, entry.Collectibles + math.floor(amount))
	mirror(participant.Id)
	return entry.Collectibles
end

-- Takes `amount` coins only if the participant has them all. Returns true if paid.
function CoinService.spend(participant, amount: number): boolean
	local entry = wallet(participant)
	if amount < 0 or entry.Coins < amount then
		return false
	end
	entry.Coins -= amount
	mirror(participant.Id)
	return true
end

-- A bot taking over a seat inherits everything the leaver had.
-- Also used when a returning player takes their seat back from that bot. A returning player
-- whose seat never changed hands has the same Id, so the wallet already is theirs.
function CoinService.transfer(from, to)
	if from.Id == to.Id then
		wallet(to)
		mirror(to.Id)
		return
	end
	local entry = wallet(from)
	local target = wallet(to)
	target.Coins += entry.Coins
	target.Collectibles += entry.Collectibles
	wallets[from.Id] = nil
	mirror(from.Id)
	mirror(to.Id)
end

-- Fresh match: everyone back to zero.
function CoinService.resetAll()
	table.clear(wallets)
	for id in playersById do
		mirror(id)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	for id, owner in playersById do
		if owner == player then
			playersById[id] = nil
		end
	end
end)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

return CoinService
