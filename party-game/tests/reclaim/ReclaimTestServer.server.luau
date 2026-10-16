--[[
	Two-client seat-reclaim harness (test only; never mapped into the shipped place).
	Local server with two Studio clients + two bots on Magical Festival Island, 3 rounds.
	The second client "leaves" and "rejoins" twice through BoardGame's real entry points
	(onPlayerLeft / requestReclaim, which PlayerRemoving / PlayerAdded call):
	  1. leaves on the board -> a bot takes the seat -> rejoins while another seat waits to roll
	     -> must get the seat back immediately
	  2. leaves before a minigame -> the bot plays it -> rejoins during the minigame
	     -> must spectate and get the seat back after results, before the next board turn
	Both clients report their final board state and standings; the server compares them with
	its own and ends the test with a RECLAIM PASS / FAIL verdict.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(RS.PartyShared.Config)
Config.Board.BotRollDelay = { 0.1, 0.2 }
Config.Board.BotChoiceDelay = { 0.1, 0.2 }
Config.Board.HopTime = 0.12
Config.Board.LandPause = 0.2
Config.Match.OrderRollTimeout = 2
Config.Board.ChoiceTimeout = 2
Config.Match.WaitingRoomDuration = 60
Config.VoteDuration = 2
Config.InstructionsDuration = 2
Config.ResultsDuration = 2

local Server = game.ServerScriptService.PartyServer
local BoardGame = require(Server.Board.BoardGame)
local MinigameManager = require(Server.MinigameManager)

-- Watch the board state the server sends everyone (BoardGame calls MinigameManager.broadcast;
-- phase changes go through MinigameManager's own sender, so the board Stage is used instead).
local last = { State = nil }
local broadcast = MinigameManager.broadcast
MinigameManager.broadcast = function(message)
	if message.Type == "BoardState" then
		last.State = message
	end
	return broadcast(message)
end

local function fingerprint(state)
	if not state then
		return "none"
	end
	local seats = {}
	for _, seat in state.Seats do
		table.insert(seats, ("%s@%d/%d/%d"):format(seat.Id, seat.SpaceId, seat.Coins, seat.Collectibles))
	end
	table.sort(seats)
	local bridge = state.Bridge
	return ("%s|crown=%s|bridge=%s"):format(table.concat(seats, ","), tostring(state.CollectibleSpace),
		bridge and (tostring(bridge.Revision) .. ":" .. tostring(bridge.Alignment)) or "-")
end

local function waitFor(fn, limit)
	local start = os.clock()
	while os.clock() - start < (limit or 300) do
		local ok, value = pcall(fn)
		if ok and value then
			return value
		end
		task.wait(0.05)
	end
	return nil
end

local function seatOf(id)
	for _, seat in (last.State and last.State.Seats) or {} do
		if seat.Id == id then
			return seat
		end
	end
end

local function reservedSeat(id)
	for _, seat in (last.State and last.State.Seats) or {} do
		if seat.ReservedFor == id then
			return seat
		end
	end
end

local log = {}
local function note(text)
	table.insert(log, text)
	print("[ReclaimSmoke] " .. text)
end

local result = { Immediate = false, MinigameQueued = false, AfterResults = false, Seats = 0 }
local remote = Instance.new("RemoteEvent")
remote.Name = "ReclaimTestReport"
remote.Parent = RS

task.spawn(function()
	local target = waitFor(function()
		return Players:GetPlayers()[2]
	end, 120)
	if not target then
		note("only one client joined")
		return
	end
	local id = "player_" .. target.UserId
	note(("target %s (UserId %d)"):format(target.Name, target.UserId))

	-- 1. Board: leave, bot takes over, rejoin while another seat waits to roll.
	waitFor(function()
		local s = last.State
		return s and s.Stage == "Roll" and s.TurnId ~= nil and s.TurnId ~= id and seatOf(id)
	end)
	local before = seatOf(id)
	BoardGame.onPlayerLeft(target)
	local held = waitFor(function()
		return reservedSeat(id)
	end)
	note(("left: %s holds the seat (reserved for %s)"):format(held and held.Name or "nobody", id))
	waitFor(function()
		local s = last.State
		return s.Stage == "Roll" and s.TurnId ~= held.Id
	end)
	BoardGame.requestReclaim(target)
	local back = seatOf(id)
	result.Immediate = back ~= nil and reservedSeat(id) == nil
	note(("rejoin at Roll: immediate=%s, order %s -> %s"):format(tostring(result.Immediate), tostring(before.Order),
		tostring(back and back.Order)))

	-- 2. Minigame: leave before it, rejoin while it's playing, seat back after results.
	waitFor(function()
		local s = last.State
		return s.Round >= 2 and s.Stage == "Roll" and s.TurnId ~= id
	end)
	BoardGame.onPlayerLeft(target)
	waitFor(function()
		return last.State.Stage == "Minigame"
	end)
	task.wait(6) -- vote and instructions are over; the minigame is on
	note("bot playing the minigame for the seat: " .. tostring(reservedSeat(id) ~= nil))
	BoardGame.requestReclaim(target)
	result.MinigameQueued = seatOf(id) == nil
	note("rejoin during minigame queued: " .. tostring(result.MinigameQueued))
	waitFor(function()
		return seatOf(id)
	end)
	local s = last.State
	result.AfterResults = s.TurnId == nil and (s.Stage == "Start" or s.Stage == "Standings")
	note(("seat back at stage=%s turn=%s round=%d"):format(tostring(s.Stage), tostring(s.TurnId), s.Round))
	result.Seats = #s.Seats
end)

local reports = {}
remote.OnServerEvent:Connect(function(player, data)
	if type(data) ~= "table" then
		return
	end
	reports[player.Name] = data
	print("[ReclaimSmoke] " .. player.Name .. " " .. HttpService:JSONEncode(data))
	local list = {}
	for _, report in reports do
		table.insert(list, report)
	end
	if #list < 2 then
		return
	end
	local a, b = list[1], list[2]
	local returning = if a.Returned then a else b
	local server = fingerprint(last.State)
	local sameState = a.Fingerprint == b.Fingerprint and a.Fingerprint == server
	local sameStandings = a.Final == b.Final
	local pass = sameState and sameStandings and result.Immediate and result.MinigameQueued and result.AfterResults
		and result.Seats == 4 and returning.Welcome >= 2 and returning.AfterMinigameNotice
		and returning.FinalRowsForMe == 1 and a.Rows == 4 and b.Rows == 4
	local verdict = ("RECLAIM %s: immediate=%s minigameQueued=%s afterResults=%s seats=%d sameState=%s sameStandings=%s welcome=%d myRows=%d"):format(
		if pass then "PASS" else "FAIL", tostring(result.Immediate), tostring(result.MinigameQueued),
		tostring(result.AfterResults), result.Seats, tostring(sameState), tostring(sameStandings),
		returning.Welcome or 0, returning.FinalRowsForMe or 0)
	print("[ReclaimSmoke] " .. verdict)
	print("[ReclaimSmoke] server " .. server)
	pcall(function()
		game:GetService("StudioTestService"):EndTest(verdict .. "\n" .. table.concat(log, "\n") .. "\n" .. HttpService:JSONEncode(reports))
	end)
end)

-- A failed client launch must not leave a local multi-client test running indefinitely.
task.delay(600, function()
	local count = 0
	for _ in reports do
		count += 1
	end
	if count < 2 then
		pcall(function()
			game:GetService("StudioTestService"):EndTest("INCOMPLETE: fewer than two reports after 600 seconds\n" .. table.concat(log, "\n"))
		end)
	end
end)
