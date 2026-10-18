--[[
	WaitingRoom
	The pre-match lobby: counts down, shows who's in, and lets the host (first player in
	the server) pick the match settings or start early. Empty seats are filled with bots
	when the match starts, so one player is enough.

	  WaitingRoom.run(getHost) -> settings { Mode, Rounds, Difficulty, Board } (yields)
	  WaitingRoom.handleInput(player, payload) -> true if it was a waiting-room input
	  WaitingRoom.applySetting(key, value) -> true if it was a legal choice (and applied it)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local MinigameManager = require(script.Parent.MinigameManager)
local Tutorial = require(script.Parent.Tutorial)

local WaitingRoom = {}

-- What each board in the picker is called on screen (its DisplayName, e.g. "Sunny Loop").
function WaitingRoom.boardNames()
	local names = {}
	local folder = script.Parent:FindFirstChild("Board") and script.Parent.Board:FindFirstChild("Boards")
	for _, id in Config.Match.Boards do
		local module = folder and folder:FindFirstChild(id)
		local ok, data = pcall(function()
			return module and require(module)
		end)
		names[id] = if ok and type(data) == "table" and type(data.DisplayName) == "string" then data.DisplayName else id
	end
	return names
end

-- Kept between matches, so the host doesn't have to pick again.
local settings = {
	Mode = Config.Match.Mode,
	Rounds = Config.Match.BoardRounds,
	Difficulty = Config.Match.BotDifficulty,
	Board = Config.Match.Board,
}

-- Every setting the host can change, and its legal values.
local function choices()
	return {
		Mode = Config.Match.Modes,
		Rounds = Config.Match.BoardRoundChoices,
		Difficulty = Config.Match.BotDifficultyOrder,
		Board = Config.Match.Boards,
	}
end

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
		Choices = choices(),
		BoardNames = WaitingRoom.boardNames(),
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
		Tutorial.complete(player, "StartedMatch")
	elseif WaitingRoom.applySetting(payload.Key, payload.Value) then
		changed = true
	end
	return true
end

function WaitingRoom.applySetting(key, value): boolean
	local legal = type(key) == "string" and choices()[key]
	if not legal or not table.find(legal, value) then
		return false
	end
	settings[key] = value
	return true
end

return WaitingRoom
