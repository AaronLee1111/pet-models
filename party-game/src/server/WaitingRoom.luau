--[[
	WaitingRoom
	The pre-match lobby: counts down, shows who's in, and lets the host (first player in
	the server) pick the match settings or start early. Empty seats are filled with bots
	when the match starts, so one player is enough.

	  WaitingRoom.run(getHost) -> settings { Rounds, Difficulty, Board } (yields)
	  WaitingRoom.handleInput(player, payload) -> true if it was a waiting-room input
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local MinigameManager = require(script.Parent.MinigameManager)

local WaitingRoom = {}

-- Kept between matches, so the host doesn't have to pick again.
local settings = {
	Rounds = Config.Match.BoardRounds,
	Difficulty = Config.Match.BotDifficulty,
	Board = Config.Match.Board,
}

local open = false
local changed = false
local startNow = false
local hostGetter: (() -> Player?)? = nil

local function publish(endsAt: number)
	local host = hostGetter and hostGetter()
	MinigameManager.setPhase(Net.Phase.Lobby, {
		Text = "Next match starting soon",
		EndsAt = endsAt,
		WaitingRoom = true,
		Settings = table.clone(settings),
		Choices = {
			Rounds = Config.Match.BoardRoundChoices,
			Difficulty = Config.Match.BotDifficultyOrder,
		},
		HostId = host and host.UserId,
		HostName = host and host.DisplayName,
		PlayerCount = math.min(#Players:GetPlayers(), Config.PlayersPerMatch),
		Seats = Config.PlayersPerMatch,
	})
end

function WaitingRoom.run(getHost: () -> Player?)
	hostGetter = getHost
	open = true
	startNow = false
	local endsAt = Workspace:GetServerTimeNow() + Config.Match.WaitingRoomDuration
	local playerCount = #Players:GetPlayers()
	local host = getHost()
	publish(endsAt)
	while Workspace:GetServerTimeNow() < endsAt and not startNow do
		task.wait(0.1)
		if changed or #Players:GetPlayers() ~= playerCount or getHost() ~= host then
			changed = false
			playerCount = #Players:GetPlayers()
			host = getHost()
			publish(endsAt)
		end
	end
	open = false
	return table.clone(settings)
end

function WaitingRoom.getSettings()
	return table.clone(settings)
end

function WaitingRoom.handleInput(player: Player, payload): boolean
	local kind = payload.Kind
	if kind ~= Net.Input.Setting and kind ~= Net.Input.StartMatch then
		return false
	end
	if not open or not hostGetter or hostGetter() ~= player then
		return true -- only the host, only while the waiting room is open
	end
	if kind == Net.Input.StartMatch then
		startNow = true
	elseif payload.Key == "Rounds" and table.find(Config.Match.BoardRoundChoices, payload.Value) then
		settings.Rounds = payload.Value
		changed = true
	elseif payload.Key == "Difficulty" and table.find(Config.Match.BotDifficultyOrder, payload.Value) then
		settings.Difficulty = payload.Value
		changed = true
	end
	return true
end

return WaitingRoom
