--[[
	Unit tests for minigame rules that can run without a live round: each minigame is set up
	with a fake round context and driven directly. Run with RunAll (see README).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local MinigameInfo = require(Server.MinigameInfo)

local tests = {}
local function test(name: string, fn)
	table.insert(tests, { Name = name, Fn = fn })
end

local function eq(actual, expected, what: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function ok(condition, what: string)
	if not condition then
		error(what, 2)
	end
end

local function fakeParticipants(count: number)
	local list = {}
	for i = 1, count do
		table.insert(list, {
			Id = "bot_mg" .. i,
			Name = "P" .. i,
			IsBot = true,
			-- No body: minigames that look for one during Setup get nothing, like a fresh spawn.
			GetCharacter = function() end,
			GetHumanoid = function() end,
			GetRoot = function() end,
			IsAlive = function()
				return false
			end,
		})
	end
	return list
end

-- A RoundContext stand-in that records what the minigame did.
local function fakeRound(participants)
	local round = { Participants = participants, Rng = Random.new(3), Ended = false, Toasts = {}, Progress = {}, Eliminated = {} }
	function round:ReportProgress(p, value)
		self.Progress[p] = value
	end
	function round:SetStatus(text)
		self.Status = text
	end
	function round:Toast(text)
		table.insert(self.Toasts, text)
	end
	function round:End(reason)
		self.Ended = true
		self.EndReason = reason
	end
	function round:Eliminate(p)
		self.Eliminated[p] = true
	end
	function round:IsEliminated(p)
		return self.Eliminated[p] == true
	end
	function round:GetAlive()
		local alive = {}
		for _, p in self.Participants do
			if not self.Eliminated[p] then
				table.insert(alive, p)
			end
		end
		return alive
	end
	function round:GetTeam(n)
		local team = {}
		for _, p in self.Participants do
			if p.Team == n then
				table.insert(team, p)
			end
		end
		return team
	end
	return round
end

-- Builds a minigame instance the way MinigameManager does, with a throwaway arena.
local function newGame(moduleName: string, participants)
	local definition = require(Server.Minigames[moduleName])
	local folder = Instance.new("Folder")
	folder.Name = "TestArena"
	local arena = { Folder = folder, Origin = CFrame.new(0, 800, 0), SpectatorCFrame = CFrame.new(0, 850, 0) }
	local round = fakeRound(participants)
	local game_ = setmetatable({ Round = round, Arena = arena, Participants = participants }, { __index = definition })
	game_:Setup(arena, participants, round)
	return game_, round, folder
end

local function placementOf(results, participant)
	for _, result in results do
		if result.Participant == participant then
			return result.Placement
		end
	end
	return nil
end

test("Duel is a valid layout", function()
	local definition = require(Server.Minigames.QuickDraw)
	eq(MinigameInfo.validate(definition), nil, "QuickDraw validates")
	eq(definition.Info.Layout, "Duel", "layout")
end)

test("quick draw: false start gives the point away; first to 2 wins", function()
	local a, b = table.unpack(fakeParticipants(2))
	local game_, round, folder = newGame("QuickDraw", { a, b })
	game_:_setLight("Idle")
	game_:Press(a)
	eq(game_.Points[a] + game_.Points[b], 0, "pressing while idle does nothing")
	game_:_setLight("Waiting")
	game_:Press(a)
	eq(game_.Points[b], 1, "a jumped the gun: b scores")
	game_:_setLight("Draw")
	game_:Press(a)
	eq(game_.Points[a], 1, "a drew first")
	game_:_setLight("Draw")
	game_:Press(b)
	game_:Press(a) -- too late: the point is already taken
	eq(game_.Points[b], 2, "b drew first")
	eq(game_.Points[a], 1, "late press ignored")
	eq(round.Ended, true, "match over at 2")
	local results = game_:GetResults()
	eq(placementOf(results, b), 1, "b wins")
	eq(placementOf(results, a), 2, "a second")
	game_:Cleanup()
	folder:Destroy()
end)

test("bullseye: centre scores 100, edges 0; one stop per shot", function()
	local Bullseye = require(Server.Minigames.Bullseye)
	eq(MinigameInfo.validate(Bullseye), nil, "validates")
	eq(Bullseye.scoreFor(0), 100, "centre")
	eq(Bullseye.scoreFor(1), 0, "edge")
	eq(Bullseye.scoreFor(-0.5), 50, "half way")
	local players = fakeParticipants(4)
	players[1].Team = 1
	for i = 2, 4 do
		players[i].Team = 2
	end
	local clock = 0
	local game_, round, folder = newGame("Bullseye", players)
	game_.Now = function()
		return clock
	end
	game_.Shot, game_.ShotStart = 1, 0
	eq(game_:Stop(players[1]) ~= nil, true, "first stop scores")
	eq(game_:Stop(players[1]), nil, "second stop in the same shot ignored")
	game_.ShotStart = nil
	eq(game_:Stop(players[2]), nil, "no shot running")
	round.Ended = true
	game_:Cleanup()
	folder:Destroy()
end)

test("bullseye: solo total vs the team's average decides 1v3", function()
	local players = fakeParticipants(4)
	players[1].Team = 1
	for i = 2, 4 do
		players[i].Team = 2
	end
	local game_, _, folder = newGame("Bullseye", players)
	game_.Totals = { [players[1]] = 200, [players[2]] = 300, [players[3]] = 150, [players[4]] = 90 }
	local solo, team = game_:TeamScores()
	eq(solo, 200, "solo")
	eq(team, 180, "team average")
	local results = game_:GetResults()
	eq(placementOf(results, players[1]), 1, "solo wins on average")
	eq(placementOf(results, players[2]), 2, "team loses together")
	game_.Totals[players[1]] = 100
	eq(placementOf(game_:GetResults(), players[3]), 1, "team wins")
	game_.Totals[players[1]] = 180
	eq(placementOf(game_:GetResults(), players[1]), placementOf(game_:GetResults(), players[2]), "tie: everyone shares")
	game_:Cleanup()
	folder:Destroy()
end)

test("pattern recall: right colours advance, a wrong one knocks you out", function()
	local PatternRecall = require(Server.Minigames.PatternRecall)
	eq(MinigameInfo.validate(PatternRecall), nil, "validates")
	local players = fakeParticipants(3)
	local game_, round, folder = newGame("PatternRecall", players)
	game_.Sequence = { "Red", "Blue", "Red" }
	game_.RoundNumber = 1
	game_:_beginInput()
	eq(game_:Press(players[1], "Red"), true, "1st colour")
	eq(game_:Press(players[1], "Blue"), true, "2nd colour")
	eq(game_:Press(players[1], "Red"), true, "3rd colour")
	eq(game_.Done[players[1]], true, "finished")
	eq(game_:Press(players[1], "Red"), nil, "presses after finishing ignored")
	eq(game_:Press(players[2], "Green"), false, "wrong colour")
	eq(round.Eliminated[players[2]], true, "knocked out")
	eq(game_:Press(players[2], "Red"), nil, "out players can't press")
	game_.Phase = "Show"
	eq(game_:Press(players[3], "Red"), nil, "no pressing while it's showing")
	round.Ended = true
	game_:Cleanup()
	folder:Destroy()
end)

test("pattern recall: last standing wins, same-round knockouts tie", function()
	local players = fakeParticipants(4)
	local game_, round, folder = newGame("PatternRecall", players)
	game_.RoundNumber = 1
	game_:_knockOut(players[3])
	game_:_knockOut(players[4])
	game_.RoundNumber = 2
	game_:_knockOut(players[2])
	local results = game_:GetResults()
	eq(placementOf(results, players[1]), 1, "survivor")
	eq(placementOf(results, players[2]), 2, "out in round 2")
	eq(placementOf(results, players[3]), 3, "out in round 1")
	eq(placementOf(results, players[4]), 3, "tied in round 1")
	round.Ended = true
	game_:Cleanup()
	folder:Destroy()
end)

test("pattern recall: bots forget more on long sequences and with low skill", function()
	local PatternRecall = require(Server.Minigames.PatternRecall)
	ok(PatternRecall.botStepChance(1, 10) > PatternRecall.botStepChance(0, 10), "skill helps")
	ok(PatternRecall.botStepChance(0, 3) > PatternRecall.botStepChance(0, 10), "longer is harder")
	ok(PatternRecall.botStepChance(1, 12) > 0.9, "skilled bots stay reliable")
end)

-- Every spawn must stand on something, or players fall out during the countdown.
test("every minigame spawn has a floor under it", function()
	for _, module in Server.Minigames:GetChildren() do
		if string.sub(module.Name, 1, 1) == "_" then
			continue
		end
		local definition = require(module)
		local count = if definition.Info.Layout == "Duel" then 2 else 4
		local players = fakeParticipants(count)
		for i, p in players do
			p.Team = if definition.Info.Layout == "1v3" then (if i == 1 then 1 else 2) elseif definition.Info.Layout == "2v2" then (if i <= 2 then 1 else 2) else nil
		end
		local folder = Instance.new("Folder")
		folder.Name = "SpawnCheck"
		folder.Parent = workspace
		local arena = { Folder = folder, Origin = CFrame.new(0, 900, 0), SpectatorCFrame = CFrame.new(0, 950, 0) }
		local round = fakeRound(players)
		local instance = setmetatable({ Round = round, Arena = arena, Participants = players }, { __index = definition })
		local okSetup, spawns = pcall(instance.Setup, instance, arena, players, round)
		if okSetup then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { folder }
			for i, spawn in spawns do
				local hit = workspace:Raycast(spawn.Position, Vector3.new(0, -12, 0), params)
				if not hit then
					folder:Destroy()
					error(("%s: spawn %d has no floor under it"):format(module.Name, i), 0)
				end
			end
		end
		round.Ended = true
		pcall(instance.Cleanup, instance)
		folder:Destroy()
		ok(okSetup, module.Name .. " Setup errored: " .. tostring(spawns))
	end
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[MinigameTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[MinigameTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
