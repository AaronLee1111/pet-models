--[[
	Unit tests for the server's minigame pick (no voting), the roulette schedule, tutorial
	metadata and the tutorial ready-up. Run with RunAll (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Server = ServerScriptService.PartyServer
local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local MinigameInfo = require(Server.MinigameInfo)
local MinigameManager = require(Server.MinigameManager)
local ReadyState = require(Server.ReadyState)

local tests = {}
local function test(name: string, fn)
	table.insert(tests, { Name = name, Fn = fn })
end

local function eq(actual, expected, what: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function pool(ids)
	local list = {}
	for _, id in ids do
		table.insert(list, { Id = id })
	end
	return list
end

test("no voting left: no Vote phase, vote input or vote messages", function()
	eq(Net.Phase.Vote, nil, "Vote phase")
	eq(Net.Input.Vote, nil, "Vote input")
	eq(Net.Message.VoteUpdate, nil, "VoteUpdate message")
	eq(Config.VoteDuration, nil, "VoteDuration")
	eq(Config.BotVoteDelay, nil, "BotVoteDelay")
	eq(Net.Phase.Select, "Select", "Select phase")
	eq(Net.Input.TutorialReady, "TutorialReady", "ready input")
end)

test("pick: same seed, same picks (deterministic with a seeded Random)", function()
	local list = pool({ "A", "B", "C", "D", "E" })
	local function run(seed)
		local random, recent, out = Random.new(seed), {}, {}
		for _ = 1, 30 do
			local entry = MinigameManager.pick(list, recent, random)
			table.insert(recent, 1, entry.Id)
			recent[3] = nil
			table.insert(out, entry.Id)
		end
		return table.concat(out)
	end
	eq(run(7), run(7), "seed 7 twice")
	assert(run(7) ~= run(8), "different seeds differ")
end)

test("pick: never the previous game; not the previous two when the pool is big", function()
	local random = Random.new(3)
	local small = pool({ "A", "B", "C" })
	for _ = 1, 300 do
		assert(MinigameManager.pick(small, { "A" }, random).Id ~= "A", "3-game pool repeated the previous pick")
	end
	local big = pool({ "A", "B", "C", "D", "E", "F", "G" })
	local seen = {}
	for _ = 1, 500 do
		local id = MinigameManager.pick(big, { "A", "B" }, random).Id
		assert(id ~= "A" and id ~= "B", "7-game pool picked one of the previous two: " .. id)
		seen[id] = true
	end
	for _, id in { "C", "D", "E", "F", "G" } do
		assert(seen[id], "every other game still gets picked: " .. id)
	end
	-- a single game is never excluded, and two games just alternate
	eq(MinigameManager.pick(pool({ "Solo" }), { "Solo" }, random).Id, "Solo", "single-game pool")
	eq(MinigameManager.pick(pool({ "A", "B" }), { "A", "B" }, random).Id, "B", "two-game pool avoids only the last")
end)

test("roulette always lands on the server's pick", function()
	local random = Random.new(11)
	for count = 1, 12 do
		for result = 1, count do
			local start, steps = MinigameManager.rouletteSteps(count, result, random)
			assert(steps >= 16, "long enough to build anticipation")
			eq((start - 1 + steps) % count + 1, result, ("count %d result %d"):format(count, result))
		end
	end
	-- the client's eased schedule ends exactly on the last step
	local module = StarterPlayer.StarterPlayerScripts:FindFirstChild("RandomizerScreen", true)
	assert(module, "RandomizerScreen not mapped")
	local RandomizerScreen = require(module)
	eq(RandomizerScreen.moved(17, 1), 17, "all steps at the end")
	eq(RandomizerScreen.moved(17, 0), 0, "none at the start")
	assert(RandomizerScreen.moved(17, 0.5) > 17 / 2, "fast first, slows at the end")
end)

test("pools: normal rounds never pick Duel games; duels only pick Duel games; layouts fit", function()
	MinigameManager.loadMinigames()
	local layouts = {}
	for _, entry in MinigameManager.roundMinigames() do
		local layout = entry.Definition.Info.Layout
		assert(layout ~= "Duel", "Duel game in the normal pool: " .. entry.Id)
		layouts[layout] = true
	end
	assert(layouts.FFA and layouts["2v2"] and layouts["1v3"], "FFA, 2v2 and 1v3 all eligible for 4 players")
	for _, entry in MinigameManager.duelMinigames() do
		eq(entry.Definition.Info.Layout, "Duel", entry.Id)
	end
end)

test("every minigame has valid tutorial metadata and preview", function()
	MinigameManager.loadMinigames()
	for _, described in MinigameManager.getMinigames() do
		local tutorial = described.Tutorial
		assert(tutorial and type(tutorial.Objective) == "string", described.Id .. ": objective")
		assert(tutorial.Preview ~= nil, described.Id .. ": has a preview")
		assert(#tutorial.Controls >= 1, described.Id .. ": control lines")
		assert(not string.find(described.Description, "[\240-\244]"), described.Id .. ": no emoji in the description")
		for _, line in tutorial.Controls do
			for _, action in line.Actions do
				local found = false
				for _, real in described.Controls.Actions do
					found = found or real.Action == action
				end
				assert(found, ("%s: control line names unknown action %s"):format(described.Id, action))
			end
		end
	end
end)

test("preview validation rejects code-like or broken data; missing preview falls back", function()
	local good = {
		Loop = 4,
		Camera = { Position = Vector3.new(0, 5, 10), LookAt = Vector3.zero },
		Actors = { { Start = Vector3.zero } },
		Props = { { Id = "Ball", Shape = "Ball", Size = Vector3.one, Position = Vector3.zero, Color = Color3.new(1, 1, 1) } },
		Steps = { { At = 1, Prop = "Ball", To = Vector3.one } },
	}
	eq(MinigameInfo.validatePreview(good), nil, "valid preview")
	local bad = table.clone(good)
	bad.Steps = { { At = 1, Prop = "Ball", Run = function() end } }
	assert(MinigameInfo.validatePreview(bad), "unknown step key (e.g. a function) rejected")
	bad.Steps = { { At = 99, Prop = "Ball" } }
	assert(MinigameInfo.validatePreview(bad), "step outside the loop rejected")
	bad.Steps = { { At = 1, Prop = "Nope" } }
	assert(MinigameInfo.validatePreview(bad), "unknown prop rejected")
	bad.Steps, bad.Loop = {}, 30
	assert(MinigameInfo.validatePreview(bad), "loop too long rejected")
	-- missing / invalid preview: the tutorial still works, with no preview (client uses generic)
	local info = { Name = "X", Description = "Do the thing.", Duration = 10, Layout = "FFA", Tutorial = { Objective = "Win.", Preview = bad } }
	local described = MinigameInfo.normalize("X", info)
	eq(described.Tutorial.Preview, nil, "invalid preview dropped")
	eq(described.Tutorial.Objective, "Win.", "objective kept")
	local plain = MinigameInfo.normalize("Y", { Name = "Y", Description = "Plain.", Duration = 10, Layout = "FFA" })
	eq(plain.Tutorial.Objective, "Plain.", "no tutorial: description is the objective")
	eq(plain.Tutorial.Controls[1].Label, "MOVE", "default lines")
end)

test("ready: only in the tutorial, only for this round's players, once unlocked; leavers never block", function()
	local a, b, bot, outsider = { Id = "a" }, { Id = "b" }, { Id = "bot", IsBot = true }, { Id = "x" }
	local ready = ReadyState.new({ a, b, bot }, 100)
	assert(not ready:mark(a, "Instructions", 90), "too early (before READY unlocks)")
	assert(not ready:mark(a, "Playing", 101), "not outside the tutorial")
	assert(not ready:mark(outsider, "Instructions", 101), "not a participant (spectators)")
	assert(ready:mark(a, "Instructions", 101), "a readies")
	assert(not ready:mark(a, "Instructions", 102), "only once")
	assert(not ready:everyone(), "b and the bot still waiting")
	assert(ready:mark(bot, "Instructions", 102), "bots are readied by the server")
	assert(not ready:everyone(), "b still waiting")
	b.Left = true
	assert(ready:everyone(), "a player who left doesn't block the start")
	eq(ready:ids().a, true, "ids")
	eq(ready:ids().b, nil, "b not ready")
	eq(ready:leftIds().b, true, "b shown as left")
end)

test("touch tutorial lines never show keyboard or controller prompts", function()
	MinigameManager.loadMinigames()
	local module = StarterPlayer.StarterPlayerScripts:FindFirstChild("InstructionsCard", true)
	assert(module, "InstructionsCard not mapped")
	local InstructionsCard = require(module)
	for _, described in MinigameManager.getMinigames() do
		for _, line in InstructionsCard.controlLines(described.Tutorial.Controls, described.Controls, "Touch") do
			for _, prompt in line.Icons do
				assert(prompt.KeyText == nil, described.Id .. ": key text on touch")
				local icon = prompt.Icon or ""
				assert(string.sub(icon, 1, 3) ~= "Key" and not string.find(icon, "Xbox") and not string.find(icon, "PS") and icon ~= "GamepadAction", ("%s: %s on touch"):format(described.Id, icon))
			end
		end
		-- desktop shows real key prompts for every action line
		for _, line in InstructionsCard.controlLines(described.Tutorial.Controls, described.Controls, "Mouse") do
			assert(#line.Icons > 0, ("%s: %s has no desktop prompt"):format(described.Id, line.Label))
		end
	end
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local ok, err = pcall(case.Fn)
		if ok then
			passed += 1
		else
			failed += 1
			warn(("[SelectionTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[SelectionTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
