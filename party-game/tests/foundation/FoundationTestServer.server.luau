--[[
	Four-client foundation regression (server half; test only, never in the shipped place).
	One local server, four real Studio clients, zero bots. Runs, back to back:
	  1. Board Party on Sunny Loop (shortest match)
	  2. Board Party on Magical Festival Island (shortest match, Moon Dial to start)
	  3. Individual Minigames: Trail Tangle (FFA), Mash Dash (2v2), Bullseye (1v3)
	  4. Duels: Sunny Loop with Duel spaces in place of coin spaces (Quick Draw / Bumper Bout)
	  5. Disconnect: a board match where one client is kicked; a bot must take the reserved seat
	Every client reports what it saw after each match (FoundationTestClient); this compares
	the reports with each other and with what the server sent, and ends the test with
	"FOUNDATION PASS" or "FOUNDATION FAIL" plus every problem found.

	Run: rojo build tests/foundation/foundation.project.json -o Foundation.rbxlx, open it, then
	  task.spawn(function() print(game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(4, {})) end)
	Keep the server window in front (Studio slows background test windows).
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local StudioTestService = game:GetService("StudioTestService")

local Config = require(RS.PartyShared.Config)
-- Faster, not different: shorter pauses only.
Config.Board.HopTime = 0.15
Config.Board.LandPause = 0.4
Config.Board.ChoiceTimeout = 6
Config.Board.RollTimeout = 12
Config.Match.OrderRollTimeout = 8
Config.Match.WaitingRoomDuration = 120
Config.Match.PreBonusDuration = 2
Config.Match.BonusDuration = 3
Config.Match.StandingsDuration = 6
Config.VoteDuration = 5
Config.InstructionsDuration = 3
Config.ResultsDuration = 4

local Server = game.ServerScriptService.PartyServer
local MinigameManager = require(Server.MinigameManager)
local BoardGame = require(Server.Board.BoardGame)
local Profiles = require(Server.Profiles)

local SCENARIOS = {
	{ Name = "SunnyLoop", Mode = "Board", Board = "Classic", Items = { "DoubleDice", "SwapTicket" } },
	{ Name = "Festival", Mode = "Board", Board = "MagicalFestival", Items = { "MoonDial", "LuckyDie" } },
	{ Name = "Minigames", Mode = "Minigames", Rounds = 3, Force = { "TrailTangle", "MashDash", "Bullseye" } },
	-- Sunny Loop with its coin spaces turned into Duel spaces (in memory, for this match only),
	-- so duels with real duellists and real spectators are certain.
	{ Name = "Duels", Mode = "Board", Board = "Classic", Items = {}, Duels = true },
	{ Name = "Disconnect", Mode = "Board", Board = "Classic", Items = {} },
}

local scenarioValue = Instance.new("StringValue")
scenarioValue.Name = "FoundationScenario"
scenarioValue.Parent = RS
local report = Instance.new("RemoteEvent")
report.Name = "FoundationReport"
report.Parent = RS

local log, problems, serverProblems = {}, {}, {}
local function note(text)
	table.insert(log, text)
	print("[Foundation] " .. text)
end
local function problem(text)
	table.insert(problems, text)
	print("[Foundation] PROBLEM " .. text)
end

game:GetService("LogService").MessageOut:Connect(function(text, kind)
	if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning)
		and not text:find("UIBlox") and not text:find("CorePackages") and not text:find("[Profiles]", 1, true)
		and not text:find("203785492") and not text:find("ChatScript") then
		table.insert(serverProblems, text:sub(1, 240))
	end
end)

-- What the server tells everyone (BoardGame and the board feed use MinigameManager.broadcast).
local server = { State = nil, Toasts = {}, Reserved = nil }
local broadcast = MinigameManager.broadcast
MinigameManager.broadcast = function(message)
	if message.Type == "BoardState" then
		server.State = message
		for _, seat in message.Seats do
			if seat.ReservedFor then
				server.Reserved = { Seat = seat.Id, For = seat.ReservedFor, IsBot = seat.IsBot }
			end
		end
	elseif message.Type == "Toast" then
		table.insert(server.Toasts, message.Text)
	end
	return broadcast(message)
end

-- Individual Minigames: play a chosen sequence instead of a random vote (layout coverage).
local forced = {}
local runRound = MinigameManager.runRound
MinigameManager.runRound = function(participants, options)
	options = options or {}
	if not options.Entry and #forced > 0 and #participants == Config.PlayersPerMatch then
		local id = table.remove(forced, 1)
		for _, entry in MinigameManager.voteMinigames() do
			if entry.Id == id then
				options.Entry = entry
			end
		end
	end
	return runRound(participants, options)
end

local function boardFingerprint(state)
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

-- Every client's report for the running scenario.
local reports = {}
local current = nil -- name of the running scenario
report.OnServerEvent:Connect(function(player, data)
	if type(data) == "table" and data.Scenario == current then
		reports[player.Name] = data
	end
end)

local function waitFor(fn, limit)
	local start = os.clock()
	while os.clock() - start < limit do
		local ok, value = pcall(fn)
		if ok and value then
			return value
		end
		task.wait(0.2)
	end
end

local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- All clients must agree on every field in `fields`.
local function compare(scenario, fields)
	local first, firstName
	for name, data in reports do
		if not first then
			first, firstName = data, name
		else
			for _, field in fields do
				local a, b = tostring(first[field]), tostring(data[field])
				if a ~= b then
					problem(("%s: %s differs (%s: %s | %s: %s)"):format(scenario, field, firstName, a:sub(1, 160), name, b:sub(1, 160)))
				end
			end
		end
	end
end

local function perClientChecks(scenario)
	for name, data in reports do
		for _, issue in data.Issues or {} do
			problem(("%s: %s: %s"):format(scenario, name, issue))
		end
	end
end

local function runBoardScenario(scenario)
	local stateAtEnd = boardFingerprint(server.State)
	compare(scenario.Name, { "Final", "FinalBoard", "Results", "BridgeTrack", "MapFinal", "Seats", "Duels" })
	perClientChecks(scenario.Name)
	local any = next(reports) and reports[next(reports)]
	if any and any.FinalBoard ~= stateAtEnd then
		problem(("%s: clients' final board differs from the server's (%s vs %s)"):format(scenario.Name, tostring(any.FinalBoard):sub(1, 120), stateAtEnd:sub(1, 120)))
	end
	return any
end

task.spawn(function()
	waitFor(function()
		return #Players:GetPlayers() >= 4
	end, 300)
	local players = Players:GetPlayers()
	note(("clients: %d"):format(#players))
	if #players < 4 then
		problem("fewer than four clients joined")
	end
	-- Bank coins so the shop check can afford something (memory profiles start empty).
	local CosmeticService = require(Server.CosmeticService)
	for _, player in players do
		waitFor(function()
			return Profiles.get(player) ~= nil
		end, 20)
		pcall(Profiles.addBankCoins, player, 300)
		pcall(CosmeticService.sendInventory, player)
	end

	for _, scenario in SCENARIOS do
		table.clear(reports)
		table.clear(server.Toasts)
		server.State, server.Reserved = nil, nil
		current = scenario.Name
		-- Duel spaces for the Duels scenario; normal spaces back for everything else.
		local classic = require(Server.Board.Boards.Classic)
		for _, space in classic.Spaces do
			space.OriginalType = space.OriginalType or space.Type
			space.Type = if scenario.Duels and (space.OriginalType == "Gain" or space.OriginalType == "Lose") then "Duel" else space.OriginalType
		end
		forced = table.clone(scenario.Force or {})
		Config.Items.StartingItems = scenario.Items or {}
		scenarioValue.Value = HttpService:JSONEncode({ Name = scenario.Name, Mode = scenario.Mode, Board = scenario.Board, Rounds = scenario.Rounds })
		note("scenario " .. scenario.Name)

		if scenario.Name == "Disconnect" then
			-- Kick the fourth client on another player's turn; its seat must go to a bot,
			-- reserved for its UserId.
			local victim = Players:GetPlayers()[4]
			local victimId = victim and ("player_" .. victim.UserId)
			waitFor(function()
				local s = server.State
				return s and s.Stage == "Roll" and s.TurnId and s.TurnId ~= victimId
			end, 240)
			if victim then
				victim:Kick("Foundation test: simulated disconnect")
				note("kicked " .. victim.Name)
				local held = waitFor(function()
					return server.Reserved and server.Reserved.For == victimId and server.Reserved.IsBot and server.Reserved
				end, 120)
				if held then
					note(("bot %s holds the seat reserved for %s"):format(held.Seat, held.For))
				else
					problem("Disconnect: no bot took the reserved seat")
				end
				local bots, players_ = 0, 0
				for _, seat in server.State.Seats do
					if seat.IsBot then
						bots += 1
					else
						players_ += 1
					end
				end
				note(("seats after the kick: %d players, %d bot(s)"):format(players_, bots))
				if bots ~= 1 or players_ ~= 3 then
					problem("Disconnect: expected 3 players and 1 bot")
				end
			end
			break
		end

		local expected = #Players:GetPlayers()
		local got = waitFor(function()
			return count(reports) >= expected
		end, 900)
		if not got then
			problem(("%s: only %d of %d clients reported"):format(scenario.Name, count(reports), expected))
		end
		local sample
		if scenario.Mode == "Board" then
			sample = runBoardScenario(scenario)
		else
			compare(scenario.Name, { "Final", "Results", "Teams" })
			perClientChecks(scenario.Name)
			sample = reports[next(reports)]
		end
		if sample then
			note(("%s final: %s"):format(scenario.Name, tostring(sample.Final)))
			note(("%s results: %s"):format(scenario.Name, tostring(sample.Results)))
			if sample.BridgeTrack then
				note(("%s bridge: %s"):format(scenario.Name, tostring(sample.BridgeTrack)))
			end
			if sample.Duels and sample.Duels ~= "" then
				note(("%s duels: %s"):format(scenario.Name, tostring(sample.Duels)))
			end
		end
		for name, data in reports do
			note(("%s %s: %s"):format(scenario.Name, name, tostring(data.Summary)))
		end
		-- Space kinds and actions seen on the board feed (coverage, not pass/fail).
		local seen = {}
		for _, text in server.Toasts do
			for _, key in { "Crown", "Shop", "found", "Gift", "rolled", "Duel", "used", "bought", "toll", "Switch", "Chaos", "Moon", "pays", "steal", "Swap" } do
				if text:find(key) then
					seen[key] = (seen[key] or 0) + 1
				end
			end
		end
		local parts = {}
		for key, n in seen do
			table.insert(parts, key .. "x" .. n)
		end
		table.sort(parts)
		note(("%s feed: %s"):format(scenario.Name, table.concat(parts, " ")))
		-- Back in the waiting room before the next scenario.
		waitFor(function()
			return BoardGame.isRunning() == false
		end, 60)
		task.wait(4)
	end

	local verdict = if #problems == 0 and #serverProblems == 0 then "FOUNDATION PASS" else "FOUNDATION FAIL"
	local text = verdict .. "\n" .. table.concat(log, "\n") .. "\nproblems: " .. (if #problems > 0 then table.concat(problems, " || ") else "none")
		.. "\nserver errors/warnings: " .. (if #serverProblems > 0 then table.concat(serverProblems, " || ") else "none")
	print("[Foundation] " .. text)
	pcall(function()
		StudioTestService:EndTest(text)
	end)
end)

task.delay(3600, function()
	pcall(function()
		StudioTestService:EndTest("FOUNDATION TIMEOUT\n" .. table.concat(log, "\n"))
	end)
end)
