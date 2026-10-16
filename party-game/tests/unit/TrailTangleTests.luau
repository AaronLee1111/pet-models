--[[
	Unit tests for Trail Tangle: the deterministic grid simulation (movement, steering, input
	buffering and rate limits, every collision case), ranking, the speed ramp, bot planning,
	and the round's setup / cleanup. Run with RunAll (see README).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local MinigameInfo = require(Server.MinigameInfo)
local TT = require(Server.Minigames.TrailTangle)

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

-- A sim with riders placed exactly where a test wants them.
local function customSim(width, height, placements)
	local sim = TT.newSim(#placements, width, height)
	table.clear(sim.Cells)
	for index, place in placements do
		local rider = sim.Riders[index]
		rider.X, rider.Y, rider.Dir = place[1], place[2], place[3]
		sim.Cells[TT.cellIndex(sim, rider.X, rider.Y)] = index
	end
	return sim
end

local function fakeParticipants(count: number, withBodies: boolean?)
	local list = {}
	for i = 1, count do
		local character, root, humanoid
		if withBodies then
			character = Instance.new("Model")
			root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Size = Vector3.new(2, 2, 1)
			root.Parent = character
			humanoid = Instance.new("Humanoid")
			humanoid.Parent = character
			character.PrimaryPart = root
			character.Parent = workspace
		end
		table.insert(list, {
			Id = "bot_tt" .. i,
			Name = "P" .. i,
			IsBot = false,
			GetCharacter = function()
				return character
			end,
			GetHumanoid = function()
				return humanoid
			end,
			GetRoot = function()
				return root
			end,
			IsAlive = function()
				return character ~= nil
			end,
		})
	end
	return list
end

local function fakeRound(participants)
	local round = { Participants = participants, Ended = false, Toasts = {}, Progress = {}, Eliminated = {} }
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
	return round
end

local function newGame(count, withBodies)
	local participants = fakeParticipants(count or 4, withBodies)
	local folder = Instance.new("Folder")
	folder.Name = "TrailTangleTestArena"
	folder.Parent = workspace
	local arena = { Folder = folder, Origin = CFrame.new(0, 900, 0), SpectatorCFrame = CFrame.new(0, 950, 0) }
	local round = fakeRound(participants)
	local game_ = setmetatable({ Round = round, Arena = arena, Participants = participants }, { __index = TT })
	game_:Setup(arena, participants, round)
	return game_, round, folder, participants
end

local function placementOf(results, participant)
	for _, result in results do
		if result.Participant == participant then
			return result.Placement
		end
	end
end

local function snapshot(sim)
	local parts = { sim.Tick }
	for _, r in sim.Riders do
		table.insert(parts, ("%d,%d,%d,%s,%d,%s"):format(r.X, r.Y, r.Dir, tostring(r.Alive), r.Claimed, tostring(r.EliminatedTick)))
	end
	return table.concat(parts, "|")
end

-- Framework ----------------------------------------------------------------------------------

test("info: valid FFA minigame, ~35 s, overhead camera, LEFT/RIGHT on keys, pad and screen", function()
	eq(MinigameInfo.validate(TT), nil, "validates")
	local info = MinigameInfo.normalize("TrailTangle", TT.Info)
	eq(info.Layout, "FFA")
	eq(info.Duration, 35)
	eq(info.Camera.Mode, "AngledOverhead")
	eq(info.Camera.Follow, 0, "whole grid, no drift")
	eq(info.Controls.Move, false, "movement is automatic")
	eq(#info.Controls.Actions, 2)
	local left, right = info.Controls.Actions[1], info.Controls.Actions[2]
	eq(left.Action, "Left")
	eq(left.Side, "Left", "LEFT button bottom-left")
	eq(table.concat(left.Keys, ","), "A,Left")
	eq(table.concat(left.Gamepads, ","), "DPadLeft,ButtonL1")
	eq(table.concat(right.Keys, ","), "D,Right")
	eq(table.concat(right.Gamepads, ","), "DPadRight,ButtonR1")
end)

-- Movement and steering ------------------------------------------------------------------------

test("movement: one cell per step, trail claimed, fully deterministic", function()
	local sim = TT.newSim(4)
	local rider = sim.Riders[1]
	local x, y = rider.X, rider.Y
	TT.step(sim)
	eq(rider.X, x + TT.DX[rider.Dir], "moved one cell")
	eq(rider.Y, y + TT.DY[rider.Dir])
	eq(rider.Claimed, 2, "start + one cell")
	eq(sim.Cells[TT.cellIndex(sim, x, y)], 1, "start cell stays as trail")
	local a, b = TT.newSim(4), TT.newSim(4)
	local script_ = { [3] = { 1, "Left" }, [5] = { 2, "Right" }, [8] = { 3, "Left" }, [9] = { 1, "Right" } }
	for t = 1, 12 do
		for _, sim_ in { a, b } do
			local turn = script_[t]
			if turn then
				TT.requestTurn(sim_, sim_.Riders[turn[1]], turn[2], t)
			end
			TT.step(sim_)
		end
	end
	eq(snapshot(a), snapshot(b), "same inputs, same outcome")
end)

test("steering: LEFT and RIGHT turn 90 degrees relative to the heading, on the next step", function()
	local sim = customSim(20, 20, { { 10, 10, 2 } }) -- heading east
	local rider = sim.Riders[1]
	ok(TT.requestTurn(sim, rider, "Left", 1), "left accepted")
	eq(rider.Dir, 2, "not applied until the step")
	TT.step(sim)
	eq(rider.Dir, 1, "east + left = north")
	eq(rider.X, 10)
	eq(rider.Y, 9)
	ok(TT.requestTurn(sim, rider, "Right", 2), "right accepted")
	TT.step(sim)
	eq(rider.Dir, 2, "north + right = east")
	eq(rider.X, 11)
	ok(TT.requestTurn(sim, rider, "Right", 3), "right")
	TT.step(sim)
	eq(rider.Dir, 3, "east + right = south")
end)

test("reverse rejected: never back into your previous cell", function()
	local sim = customSim(20, 20, { { 10, 10, 2 } })
	local rider = sim.Riders[1]
	ok(TT.requestTurn(sim, rider, "Left", 1), "first left")
	local accepted, why = TT.requestTurn(sim, rider, "Left", 1.5)
	ok(not accepted, "second turn in one step refused (would be a U-turn)")
	eq(why, "buffered")
	for _, bad in { "Back", "Reverse", "LeftStop", 3, nil } do
		local accepted2, why2 = TT.requestTurn(sim, rider, bad, 5)
		ok(not accepted2 and (why2 == "malformed" or why2 == "buffered"), "rejected " .. tostring(bad))
	end
	TT.step(sim)
	eq(rider.Dir, 1, "turned once only")
	-- Even a forged reverse in the buffer is ignored by the step.
	rider.Pending = 3
	TT.step(sim)
	eq(rider.Dir, 1, "forged reverse ignored")
	ok(rider.Alive, "and the rider didn't crash into itself")
end)

test("input buffering: one turn per step, cleared once applied", function()
	local sim = customSim(20, 20, { { 10, 10, 2 } })
	local rider = sim.Riders[1]
	ok(TT.requestTurn(sim, rider, "Right", 1), "buffered")
	eq(rider.Pending, 3)
	ok(not TT.requestTurn(sim, rider, "Right", 1.2), "second buffered turn refused")
	TT.step(sim)
	eq(rider.Pending, nil, "buffer cleared")
	ok(TT.requestTurn(sim, rider, "Right", 1.3), "next step's turn accepted")
end)

test("input rate limit: requests faster than the cooldown are dropped", function()
	local sim = customSim(20, 20, { { 10, 10, 2 } })
	local rider = sim.Riders[1]
	ok(TT.requestTurn(sim, rider, "Left", 1.0), "first")
	TT.step(sim)
	local accepted, why = TT.requestTurn(sim, rider, "Left", 1.0 + TT.TURN_COOLDOWN / 2)
	ok(not accepted, "too fast")
	eq(why, "too_fast")
	ok(TT.requestTurn(sim, rider, "Left", 1.0 + TT.TURN_COOLDOWN + 0.01), "after the cooldown")
	ok(not TT.requestTurn(sim, rider, "Left", 0 / 0), "NaN time rejected")
	TT.knockOut(sim, rider)
	local _, out = TT.requestTurn(sim, rider, "Right", 99)
	eq(out, "out", "knocked-out riders can't steer")
end)

-- Collisions -------------------------------------------------------------------------------------

test("boundary: riding off the grid knocks you out", function()
	local sim = customSim(10, 10, { { 9, 4, 2 }, { 0, 0, 3 } })
	local out = TT.step(sim)
	eq(#out, 1)
	eq(out[1], sim.Riders[1], "the one at the east edge")
	eq(sim.Riders[1].EliminatedTick, 1)
	eq(sim.Riders[1].X, 9, "stays on its last cell")
	ok(sim.Riders[2].Alive, "the other rides on")
end)

test("own trail: looping back into yourself knocks you out", function()
	local sim = customSim(20, 20, { { 10, 10, 2 } })
	local rider = sim.Riders[1]
	for t = 1, 3 do
		TT.requestTurn(sim, rider, "Right", t)
		TT.step(sim)
		ok(rider.Alive, "still in after turn " .. t)
	end
	TT.requestTurn(sim, rider, "Right", 4)
	TT.step(sim)
	ok(not rider.Alive, "fourth right turn runs into the start cell")
	eq(rider.EliminatedTick, 4)
end)

test("opponent trail: riding into someone else's trail knocks you out", function()
	local sim = customSim(20, 20, { { 5, 5, 2 }, { 12, 12, 1 } })
	sim.Cells[TT.cellIndex(sim, 6, 5)] = 2 -- rider 2's trail right in front of rider 1
	local out = TT.step(sim)
	eq(#out, 1)
	ok(not sim.Riders[1].Alive, "rider 1 out")
	ok(sim.Riders[2].Alive, "rider 2 fine")
end)

test("same cell: two riders entering one empty cell are both out", function()
	local sim = customSim(20, 20, { { 5, 5, 2 }, { 7, 5, 4 }, { 15, 15, 1 } })
	local out = TT.step(sim)
	eq(#out, 2, "both")
	eq(sim.Riders[1].EliminatedTick, sim.Riders[2].EliminatedTick, "same tick")
	eq(sim.Cells[TT.cellIndex(sim, 6, 5)], nil, "nobody claims the contested cell")
	ok(sim.Riders[3].Alive, "bystander unaffected")
end)

test("swap: two riders trading cells are both out, whatever order they're listed in", function()
	for _, order in { { 1, 2 }, { 2, 1 } } do
		local places = { { 5, 5, 2 }, { 6, 5, 4 } }
		local sim = customSim(20, 20, { places[order[1]], places[order[2]] })
		local out = TT.step(sim)
		eq(#out, 2, "both out")
	end
end)

test("cell taken earlier in the same tick: no rider gets there 'first'", function()
	-- Rider 1 heads west into (7,5) and rider 2 north into (7,5): neither is first, both out.
	local sim = customSim(20, 20, { { 8, 5, 4 }, { 7, 6, 1 } })
	local out = TT.step(sim)
	eq(#out, 2, "contested cell")
	-- Chasing a tail: rider 1 follows directly behind rider 2's head.
	sim = customSim(20, 20, { { 4, 5, 2 }, { 5, 5, 2 } })
	out = TT.step(sim)
	eq(#out, 1, "the chaser hits the head cell it was behind")
	ok(not sim.Riders[1].Alive and sim.Riders[2].Alive, "leader survives")
end)

test("simultaneous elimination: everyone left out on one tick", function()
	local sim = customSim(10, 10, { { 9, 2, 2 }, { 0, 7, 4 } })
	local out = TT.step(sim)
	eq(#out, 2)
	eq(#TT.alive(sim), 0, "nobody left")
end)

-- Ranking ---------------------------------------------------------------------------------------

test("results: last rider wins, the rest by how late they went out", function()
	local game_, _, folder, players = newGame(4)
	local sim = game_.Sim
	sim.Tick = 30
	sim.Riders[1].Alive, sim.Riders[1].EliminatedTick, sim.Riders[1].Claimed = false, 10, 50
	sim.Riders[2].Alive, sim.Riders[2].EliminatedTick, sim.Riders[2].Claimed = false, 25, 5
	sim.Riders[3].Alive, sim.Riders[3].Claimed = true, 3
	sim.Riders[4].Alive, sim.Riders[4].EliminatedTick, sim.Riders[4].Claimed = false, 18, 40
	local results = game_:GetResults()
	eq(placementOf(results, players[3]), 1, "last rider")
	eq(placementOf(results, players[2]), 2, "out latest")
	eq(placementOf(results, players[4]), 3)
	eq(placementOf(results, players[1]), 4, "first out, despite most cells")
	folder:Destroy()
end)

test("results at the time limit: survivors by cells; same-tick knockouts by cells; exact ties share", function()
	local game_, _, folder, players = newGame(4)
	local sim = game_.Sim
	sim.Tick = 120
	sim.Riders[1].Claimed = 60
	sim.Riders[2].Claimed = 75
	sim.Riders[3].Alive, sim.Riders[3].EliminatedTick, sim.Riders[3].Claimed = false, 90, 40
	sim.Riders[4].Alive, sim.Riders[4].EliminatedTick, sim.Riders[4].Claimed = false, 90, 55
	local results = game_:GetResults()
	eq(placementOf(results, players[2]), 1, "most cells among survivors")
	eq(placementOf(results, players[1]), 2)
	eq(placementOf(results, players[4]), 3, "same tick: more cells wins")
	eq(placementOf(results, players[3]), 4)
	-- Exact ties
	sim.Riders[1].Claimed = 75
	sim.Riders[3].Claimed = 55
	results = game_:GetResults()
	eq(placementOf(results, players[1]), 1, "tied survivors share 1st")
	eq(placementOf(results, players[2]), 1)
	eq(placementOf(results, players[3]), 3, "tied knockouts share 3rd")
	eq(placementOf(results, players[4]), 3)
	folder:Destroy()
end)

test("all out together: they tie unless cells separate them", function()
	local sim = customSim(10, 10, { { 9, 2, 2 }, { 0, 7, 4 } })
	TT.step(sim)
	eq(TT.score(sim, sim.Riders[1]), TT.score(sim, sim.Riders[2]), "exact tie")
	sim.Riders[2].Claimed += 1
	ok(TT.score(sim, sim.Riders[2]) > TT.score(sim, sim.Riders[1]), "cells break it")
end)

-- Speed ---------------------------------------------------------------------------------------

test("speed ramp: slow start, steady speed-up, capped at the final pace", function()
	eq(TT.intervalAt(0), TT.START_INTERVAL)
	eq(TT.intervalAt(TT.RAMP_START), TT.START_INTERVAL, "flat until the ramp")
	ok(math.abs(TT.intervalAt(TT.RAMP_END) - TT.FINAL_INTERVAL) < 1e-9, "final pace at ramp end")
	eq(TT.intervalAt(TT.ROUND_DURATION), TT.FINAL_INTERVAL, "stays there")
	local previous = math.huge
	for t = 0, TT.ROUND_DURATION, 0.5 do
		local interval = TT.intervalAt(t)
		ok(interval <= previous + 1e-9, "never slows down at " .. t)
		ok(interval >= TT.FINAL_INTERVAL - 1e-9, "never faster than final")
		previous = interval
	end
	-- The fixed schedule the server runs: how many steps a full round has.
	local at, steps = TT.intervalAt(0), 0
	while at <= TT.ROUND_DURATION do
		steps += 1
		at += TT.intervalAt(at)
	end
	ok(steps > 140 and steps < 200, "about 160 steps in 35 s, got " .. steps)
	ok(TT.START_INTERVAL >= 0.25, "slow enough to learn")
end)

-- Bots ------------------------------------------------------------------------------------------

local function playBots(skills, seed, maxTicks)
	local sim = TT.newSim(#skills)
	local rng = Random.new(seed)
	local illegal = 0
	local now = 0
	for _ = 1, maxTicks or 300 do
		now += 0.2
		for index, rider in sim.Riders do
			local side = TT.botChoice(sim, rider, skills[index], rng)
			if side ~= nil then
				if side ~= "Left" and side ~= "Right" then
					illegal += 1
				else
					local accepted, why = TT.requestTurn(sim, rider, side, now)
					if not accepted and why ~= "out" then
						illegal += 1
					end
				end
			end
		end
		TT.step(sim)
		if #TT.alive(sim) <= 1 then
			break
		end
	end
	return sim, illegal
end

test("bots: every request is a legal LEFT/RIGHT through the normal turn path", function()
	for seed = 1, 6 do
		local _, illegal = playBots({ 0, 0.4, 0.7, 1 }, seed)
		eq(illegal, 0, "seed " .. seed)
	end
end)

test("bots: avoid a wall dead ahead and pick the side with room", function()
	-- Heading east at x=9 in a 10-wide grid: straight on is the edge.
	local sim = customSim(10, 10, { { 9, 5, 2 } })
	local rng = Random.new(1)
	for _ = 1, 30 do
		local side = TT.botChoice(sim, sim.Riders[1], 1, rng)
		ok(side ~= nil, "a good bot always turns away from the edge")
	end
	-- A trail wall ahead, and a small pocket on the left: go right.
	sim = customSim(20, 20, { { 10, 10, 2 } })
	sim.Cells[TT.cellIndex(sim, 11, 10)] = 2
	for x = 9, 12 do
		sim.Cells[TT.cellIndex(sim, x, 8)] = 2 -- caps the north side: a 1-row pocket
	end
	sim.Cells[TT.cellIndex(sim, 9, 9)] = 2
	sim.Cells[TT.cellIndex(sim, 12, 9)] = 2
	for _ = 1, 30 do
		eq(TT.botChoice(sim, sim.Riders[1], 1, rng), "Right", "avoids the pocket")
	end
end)

test("bots: good bots outlast sloppy ones and spread out", function()
	local goodTicks, badTicks, goodFirst = 0, 0, math.huge
	for seed = 1, 8 do
		local sim = playBots({ 1, 0, 1, 0 }, seed)
		for index, rider in sim.Riders do
			local lasted = rider.EliminatedTick or sim.Tick + 1
			if index % 2 == 1 then
				goodTicks += lasted
				goodFirst = math.min(goodFirst, lasted)
			else
				badTicks += lasted
			end
		end
	end
	ok(goodTicks > badTicks, ("skill 1 lasted %d ticks in total vs skill 0 %d"):format(goodTicks, badTicks))
	ok(goodFirst >= 20, "good bots never crash in the opening, earliest " .. goodFirst)
	-- Spreading out: across several openings, heads rarely come within two cells of each other.
	local close = 0
	for seed = 1, 4 do
		local sim = TT.newSim(4)
		local rng = Random.new(seed)
		for t = 1, 20 do
			for _, rider in sim.Riders do
				local side = TT.botChoice(sim, rider, 1, rng)
				if side then
					TT.requestTurn(sim, rider, side, t)
				end
			end
			TT.step(sim)
			for i = 1, 4 do
				for j = i + 1, 4 do
					local a, b = sim.Riders[i], sim.Riders[j]
					if t >= 6 and a.Alive and b.Alive and math.abs(a.X - b.X) + math.abs(a.Y - b.Y) <= 2 then
						close += 1
					end
				end
			end
		end
	end
	ok(close <= 8, "bots rode head to head for " .. close .. " steps")
end)

test("bots: difficulty changes how often they slip, and slips are never instant crashes", function()
	-- Wall ahead, a one-row pocket to the left, open space to the right: Right is best.
	local sim = customSim(20, 20, { { 10, 10, 2 } })
	sim.Cells[TT.cellIndex(sim, 11, 10)] = 2
	for x = 9, 12 do
		sim.Cells[TT.cellIndex(sim, x, 8)] = 2
	end
	sim.Cells[TT.cellIndex(sim, 9, 9)] = 2
	sim.Cells[TT.cellIndex(sim, 12, 9)] = 2
	local function slips(skill)
		local rng, count = Random.new(9), 0
		for _ = 1, 600 do
			local side = TT.botChoice(sim, sim.Riders[1], skill, rng)
			ok(side ~= nil, "never rides straight into the wall")
			if side ~= "Right" then
				count += 1
			end
		end
		return count
	end
	local sloppy, sharp = slips(0), slips(1)
	ok(sloppy > sharp, ("skill 0 slipped %d times, skill 1 %d"):format(sloppy, sharp))
	ok(sharp <= 12, "skill 1 rarely slips: " .. sharp)
	ok(sloppy >= 15, "skill 0 visibly slips: " .. sloppy)
end)

-- Round wiring and cleanup ----------------------------------------------------------------------

test("round: inputs steer, a lost player is knocked out, last rider ends the round", function()
	local game_, round, folder, players = newGame(4)
	local rider = game_.RiderOf[players[1]]
	local dir = rider.Dir
	game_:OnInput(players[1], "LeftStop") -- release half of a held button: ignored
	eq(rider.Pending, nil)
	game_:OnInput(players[1], "Left")
	eq(rider.Pending, TT.turned(dir, "Left"))
	game_:OnParticipantLost(players[2], "Left")
	ok(not game_.RiderOf[players[2]].Alive, "leaver's rider out")
	TT.knockOut(game_.Sim, game_.RiderOf[players[3]])
	TT.knockOut(game_.Sim, game_.RiderOf[players[4]])
	game_.NextWarning = 1
	game_:_tick(1)
	eq(round.Ended, true, "one rider left")
	eq(round.EndReason, "LastRider")
	eq(placementOf(game_:GetResults(), players[1]), 1)
	folder:Destroy()
end)

test("cleanup: loop disconnected, bodies released, highlights removed, parts only in the arena", function()
	local before = #workspace:GetChildren()
	local game_, _, folder, players = newGame(4, true)
	local trails = 0
	for _, part in folder:GetChildren() do
		if part.Name == "Trail" then
			trails += 1
		end
	end
	eq(trails, 4, "one start cell each")
	game_:Start()
	local root = players[1].GetRoot()
	ok(root.Anchored, "riders anchored while playing")
	ok(players[1].GetCharacter():FindFirstChild("TrailTangleColor"), "colour highlight on")
	eq(#game_.Connections, 1, "one tick loop")
	local connection = game_.Connections[1]
	game_:Cleanup()
	ok(not connection.Connected, "tick loop disconnected")
	ok(not root.Anchored, "bodies released")
	ok(not players[1].GetCharacter():FindFirstChild("TrailTangleColor"), "highlight removed")
	folder:Destroy()
	for _, p in players do
		p.GetCharacter():Destroy()
	end
	eq(#workspace:GetChildren(), before, "nothing left behind outside the arena")
end)

-- Runner ------------------------------------------------------------------------------------------

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[TrailTangleTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[TrailTangleTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
