--[[
	Main (server entry point)
	The match loop: waiting room (host picks settings) -> seat 4 participants (real players
	first, bots fill the rest) -> BoardGame.play (board turns + a minigame every round ->
	final standings) -> back to the waiting room.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Arena = require(script.Parent.Arena)
local BoardGame = require(script.Parent.Board.BoardGame)
local BotService = require(script.Parent.BotService)
local MinigameManager = require(script.Parent.MinigameManager)
local Participant = require(script.Parent.Participant)
local WaitingRoom = require(script.Parent.WaitingRoom)

Arena.ensureLobby()
MinigameManager.init()
MinigameManager.setInputHandler(function(player, payload)
	return WaitingRoom.handleInput(player, payload) or BoardGame.handleInput(player, payload)
end)

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

local function getHost(): Player?
	return joinOrder[1]
end

while true do
	while #Players:GetPlayers() == 0 do
		MinigameManager.showLobby("Waiting for players...")
		Players.PlayerAdded:Wait()
	end

	local settings = WaitingRoom.run(getHost)
	if #Players:GetPlayers() == 0 then
		continue -- everyone left during the countdown
	end
	BotService.setSkillRange(Config.Match.BotDifficulties[settings.Difficulty])

	local participants = buildParticipants()
	local ok, err = xpcall(BoardGame.play, debug.traceback, participants, settings)
	if not ok then
		warn("[Party] Match crashed, returning to the waiting room:\n" .. tostring(err))
		MinigameManager.abort("Match crashed, back to the lobby!")
		BoardGame.cleanup()
	end
end
