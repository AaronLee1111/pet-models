--[[
	MinigameMode
	The "Minigames" match mode: no board, just back-to-back minigames (vote -> play ->
	results) for the chosen number of rounds. Most coins wins; ties share a place. Real
	players get bank coins by placement, same as the board party.

	  MinigameMode.play(participants, settings)   yields for the whole match; returns ranked rows
	  MinigameMode.rank(participants, wallet)     pure ranking (tested)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local Arena = require(script.Parent.Arena)
local BotService = require(script.Parent.BotService)
local CoinService = require(script.Parent.CoinService)
local CosmeticService = require(script.Parent.CosmeticService)
local Inventory = require(script.Parent.Inventory)
local MinigameManager = require(script.Parent.MinigameManager)
local Participant = require(script.Parent.Participant)
local Profiles = require(script.Parent.Profiles)

local MinigameMode = {}

local function isAway(participant): boolean
	return participant.Left or (not participant.IsBot and (not participant.Player or participant.Player.Parent == nil))
end

-- Ranks by coins (most first); equal coins share a placement. Stable by seat order.
function MinigameMode.rank(participants, wallet)
	local rows = {}
	for index, participant in participants do
		table.insert(rows, { Participant = participant, SeatIndex = index, Coins = wallet.get(participant) })
	end
	table.sort(rows, function(a, b)
		if a.Coins ~= b.Coins then
			return a.Coins > b.Coins
		end
		return a.SeatIndex < b.SeatIndex
	end)
	for i, row in rows do
		local previous = rows[i - 1]
		row.Placement = if previous and previous.Coins == row.Coins then previous.Placement else i
	end
	return rows
end

-- A bot takes over the seat of anyone who left (keeping their coins).
local function replaceLeavers(participants)
	for index, participant in participants do
		if not isAway(participant) then
			continue
		end
		participant.Left = true
		local seated = {}
		local count = 0
		for _, other in participants do
			if other.IsBot then
				seated[other.Bot] = other
				count += 1
			end
		end
		local newcomer
		for _, bot in BotService.getBots(count + 1, Arena.lobbySpot) do
			if seated[bot] then
				bot.Participant = seated[bot] -- getBots clears these
			else
				newcomer = bot
			end
		end
		if newcomer then
			local replacement = Participant.fromBot(newcomer)
			CoinService.transfer(participant, replacement)
			participants[index] = replacement
			MinigameManager.broadcast({
				Type = Net.Message.Toast,
				Text = ("%s left, %s takes over their seat"):format(participant.Name, replacement.Name),
			})
		end
	end
end

function MinigameMode.play(participants, settings)
	CoinService.resetAll()
	Inventory.resetBots()
	participants = table.clone(participants)
	local rounds = settings.Rounds or Config.Match.BoardRounds

	for round = 1, rounds do
		replaceLeavers(participants)
		MinigameManager.showLobby(("Minigame %d of %d"):format(round, rounds), Config.IntermissionDuration)
		local ok, err = xpcall(MinigameManager.runRound, debug.traceback, participants)
		if not ok then
			warn("[MinigameMode] Minigame crashed, carrying on:\n" .. tostring(err))
			MinigameManager.abort("Minigame crashed, on to the next one!")
		end
	end

	replaceLeavers(participants)
	local rows = MinigameMode.rank(participants, CoinService)
	local described = {}
	for _, row in rows do
		local entry = row.Participant:Describe()
		entry.Placement = row.Placement
		entry.Coins = row.Coins
		entry.Collectibles = 0
		local player = row.Participant.Player
		local bank = Config.Profile.BankCoinsByPlacement[row.Placement] or 0
		if player and player.Parent and not row.Participant.Left and bank > 0 then
			Profiles.addBankCoins(player, bank)
			entry.BankCoins = bank
			CosmeticService.sendInventory(player)
		end
		table.insert(described, entry)
	end
	MinigameManager.setPhase(Net.Phase.Standings, {
		Stage = "Final",
		Mode = "Minigames",
		Rows = described,
		EndsAt = Workspace:GetServerTimeNow() + Config.Match.StandingsDuration,
	})
	task.wait(Config.Match.StandingsDuration)
	CoinService.resetAll()
	return rows
end

return MinigameMode
