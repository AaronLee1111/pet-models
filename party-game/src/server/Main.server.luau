--[[
	Main (server entry point)
	The party loop: lobby -> seat 4 participants (real players first, bots fill the rest)
	-> MinigameManager.runRound -> repeat.

	When the board game exists, it replaces this loop and calls
	MinigameManager.runRound(participants) at the end of each turn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Arena = require(script.Parent.Arena)
local BotService = require(script.Parent.BotService)
local MinigameManager = require(script.Parent.MinigameManager)
local Participant = require(script.Parent.Participant)

Arena.ensureLobby()
MinigameManager.init()

-- First come, first seated: track join order so seats are fair when >4 players are on.
local joinOrder: { Player } = {}
for _, player in Players:GetPlayers() do
	table.insert(joinOrder, player)
end
Players.PlayerAdded:Connect(function(player)
	table.insert(joinOrder, player)
end)
Players.PlayerRemoving:Connect(function(player)
	local index = table.find(joinOrder, player)
	if index then
		table.remove(joinOrder, index)
	end
end)

local function buildParticipants()
	local participants = {}
	for _, player in joinOrder do
		if #participants >= Config.PlayersPerMatch then
			break -- extra players watch this round from the lobby
		end
		table.insert(participants, Participant.fromPlayer(player))
	end

	local realCount = #participants
	local bots = BotService.getBots(Config.PlayersPerMatch - realCount, function(index)
		return Arena.lobbySpot(realCount + index)
	end)
	for _, bot in bots do
		table.insert(participants, Participant.fromBot(bot))
	end
	return participants
end

while true do
	while #Players:GetPlayers() == 0 do
		MinigameManager.showLobby("Waiting for players...")
		Players.PlayerAdded:Wait()
	end

	MinigameManager.showLobby("Next minigame starting soon!", Config.IntermissionDuration)

	local participants = buildParticipants()
	local ok, err = xpcall(MinigameManager.runRound, debug.traceback, participants)
	if not ok then
		warn("[Party] Round crashed, returning to lobby:\n" .. tostring(err))
		MinigameManager.abort("⚠️ Minigame crashed — back to the lobby!")
	end
end
