--[[
	MinigameMode
	The "Minigames" match mode: no board, just back-to-back minigames (vote -> play ->
	results) for the chosen number of rounds. Most coins wins; ties share a place. Real
	players get bank coins by placement, same as the board party.

	  MinigameMode.play(participants, settings)   yields for the whole match; returns ranked rows
	  MinigameMode.reclaim(participants, claims, index, player)   hand a kept seat back (tested)

	A player who leaves keeps their seat (a bot plays it); if they rejoin they get it back
	after the current minigame (see SeatClaims). New late joiners watch until the next match.
	  MinigameMode.rank(participants, wallet)     pure ranking (tested)
]]

local Players = game:GetService("Players")
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
local SeatClaims = require(script.Parent.SeatClaims)

local MinigameMode = {}

local running = nil -- { Participants, Claims } while a Minigames match is on

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
		if running and participant.UserId and Config.SeatReclaim.Enabled then
			running.Claims:reserve(index, participant.UserId)
		end
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

--[[
	Hands seat `index` back to `player`, whose UserId it is reserved for. Same slot, so the
	turn order stays; the wallet moves from the bot back to them. Returns the new participant
	and the one it replaced, or nil.
]]
function MinigameMode.reclaim(participants, claims, index, player)
	if claims:pendingFor(index) ~= player then
		return nil
	end
	claims:consume(index)
	local previous = participants[index]
	if not previous or not (previous.IsBot or isAway(previous)) then
		return nil
	end
	local returning = Participant.fromPlayer(player)
	for other, participant in participants do
		if other ~= index and participant.Id == returning.Id then
			return nil
		end
	end
	CoinService.transfer(previous, returning)
	participants[index] = returning
	return returning, previous
end

-- Between minigames: everyone waiting gets their seat back.
local function settleReclaims(participants)
	for index in participants do
		local player = running.Claims:pendingFor(index)
		local returning, previous = if player then MinigameMode.reclaim(participants, running.Claims, index, player) else nil
		if returning then
			if previous.IsBot and previous.Bot then
				BotService.release(previous.Bot)
			end
			MinigameManager.broadcast({
				Type = Net.Message.Toast,
				Text = ("%s is back and takes their seat again"):format(returning.Name),
			})
			MinigameManager.sendTo(player, { Type = Net.Message.Toast, Text = SeatClaims.Messages.now })
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	if running and Config.SeatReclaim.Enabled and running.Claims:request(player) then
		MinigameManager.sendTo(player, { Type = Net.Message.Toast, Text = SeatClaims.Messages.after_minigame })
	end
end)
Players.PlayerRemoving:Connect(function(player)
	if not running then
		return
	end
	running.Claims:cancel(player)
	for index, participant in running.Participants do
		if participant.Player == player and Config.SeatReclaim.Enabled then
			running.Claims:reserve(index, player.UserId)
		end
	end
end)

-- Forget seat reservations (match crashed); safe any time.
function MinigameMode.cleanup()
	running = nil
end

function MinigameMode.play(participants, settings)
	CoinService.resetAll()
	Inventory.resetBots()
	participants = table.clone(participants)
	local rounds = settings.Rounds or Config.Match.BoardRounds
	running = { Participants = participants, Claims = SeatClaims.new() }

	for round = 1, rounds do
		settleReclaims(participants)
		replaceLeavers(participants)
		MinigameManager.showLobby(("Minigame %d of %d"):format(round, rounds), Config.IntermissionDuration)
		local ok, err = xpcall(MinigameManager.runRound, debug.traceback, participants)
		if not ok then
			warn("[MinigameMode] Minigame crashed, carrying on:\n" .. tostring(err))
			MinigameManager.abort("Minigame crashed, on to the next one!")
		end
	end

	settleReclaims(participants)
	replaceLeavers(participants)
	-- Seats are final now: reservations end with the match.
	for _, player in running.Claims:clear() do
		MinigameManager.sendTo(player, { Type = Net.Message.Toast, Text = SeatClaims.Messages.ended })
	end
	running = nil
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
