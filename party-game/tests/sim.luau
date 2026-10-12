--[[
	Headless end-to-end smoke test: 1 simulated real player + 3 bots play several rounds.
	Run from the party-game folder:   lune run tests/sim

	Checks every round goes Vote -> Instructions -> Countdown x3 -> Playing -> Finished ->
	Results -> Lobby, results/coins are consistent, the arena is cleaned up, nobody is left
	frozen, and no script errored or warned. Also fuzzes the input remote with junk and
	covers a player leaving mid-round.
]]

local Engine = require("./mock/engine")
local roblox = require("@lune/roblox")
local Vector3, Enum = roblox.Vector3, roblox.Enum

local args = require("@lune/process").args
local SEED = tonumber(args[1]) or 1234
local VERBOSE = args[2] == "-v"
math.randomseed(SEED)

local ROOT = "src"
local shared = Engine.mount(ROOT .. "/shared", Engine.ReplicatedStorage, "PartyShared")
local server = Engine.mount(ROOT .. "/server", Engine.ServerScriptService, "PartyServer")
local client = Engine.mount(ROOT .. "/client", Engine.StarterPlayer.StarterPlayerScripts, "PartyClient")

-- Speed up the boring waits; minigame logic is untouched.
local Config = Engine.requireAs(shared.Config, "server")
Config.IntermissionDuration = 1
Config.VoteDuration = 4

local failures = {}
local function check(condition, message)
	if not condition then
		table.insert(failures, message)
	end
	return condition
end

-- Boot the server, then join one player and start their client.
Engine.runScript(server.Main, "server")
Engine.run(0.5)
local player = Engine.addPlayer("TestPlayer", 1001)
Engine.localPlayer = player
Engine.Players.LocalPlayer = player
if #Engine.errors > 0 then
	error("server failed to boot:\n" .. table.concat(Engine.errors, "\n"))
end
Engine.run(0.2)
Engine.runScript(client.Main, "client")

-- Record everything the client receives.
local stateRemote = Engine.ReplicatedStorage.PartyRemotes.PartyState
local inputRemote = Engine.ReplicatedStorage.PartyRemotes.PartyInput

local rounds = {}
local current = nil
stateRemote.OnClientEvent:Connect(function(message)
	if message.Type == "Toast" then
		if current then
			current.Toasts = current.Toasts or {}
			table.insert(current.Toasts, message.Text)
		end
	end
	if message.Type == "Chips" and current then
		current.ChipCount = #message.Chips
		for _, chip in message.Chips do
			if chip.Value ~= nil then
				current.SawChipValue = true
			end
		end
	end
	if message.Type ~= "Phase" then
		return
	end
	if message.Phase == "Vote" then
		current = { Phases = {}, Choices = message.Choices }
		table.insert(rounds, current)
	end
	if current then
		table.insert(current.Phases, message.Phase)
		if message.Phase == "Instructions" then
			current.Minigame = message.Minigame.Name
			current.Participants = message.Participants
		elseif message.Phase == "Results" then
			current.Results = message.Results
		elseif message.Phase == "Lobby" then
			current.Done = true
			current = nil
		end
	end
end)

-- Fake "human": clicks a vote card through the real UI, wanders, spams its action buttons,
-- and occasionally sends garbage to the server.
local playerGui = player.PlayerGui
local lastPhase = nil
local nextAct = 0
local function humanBrain()
	local phase = rounds[#rounds] and rounds[#rounds].Phases[#rounds[#rounds].Phases]
	if phase ~= lastPhase then
		lastPhase = phase
		if phase == "Vote" then
			Engine.task.delay(1, function()
				local cards = {}
				for _, d in playerGui:GetDescendants() do
					if d.ClassName == "TextButton" and string.sub(d.Name, 1, 4) == "Card" then
						table.insert(cards, d)
					end
				end
				-- Alternate preferences so both minigames get covered.
				local cycle = { "Hot Potato", "Falling Platforms", "Mash Dash" }
				local wanted = cycle[#rounds % #cycle + 1]
				local pick = cards[1]
				for i, choice in rounds[#rounds].Choices do
					if choice.Name == wanted and cards[i] then
						for _, card in cards do
							if card.Name == "Card" .. i then
								pick = card
							end
						end
					end
				end
				if pick then
					pick.Activated:Fire()
				end
				-- junk inputs a malicious client could send
				Engine.fireServerRaw(inputRemote, player, { Kind = "Vote", Choice = 99 })
				Engine.fireServerRaw(inputRemote, player, { Kind = "Vote", Choice = 0 / 0 })
				Engine.fireServerRaw(inputRemote, player, { Kind = "Vote", Choice = 1.5 })
				Engine.fireServerRaw(inputRemote, player, "lol")
				Engine.fireServerRaw(inputRemote, player, nil)
			end)
		end
	end
	local round = rounds[#rounds]
	if round and phase == "Playing" then
		local camera = Engine.Workspace.CurrentCamera
		round.SawScriptable = round.SawScriptable or camera.CameraType == Enum.CameraType.Scriptable
		local bar = playerGui.PartyUI:FindFirstChild("SpectatorBar")
		round.SawSpectator = round.SawSpectator or (bar and bar.Visible)
		local actionBar = playerGui.PartyUI:FindFirstChild("ActionBar")
		round.SawActionBar = round.SawActionBar or (actionBar and actionBar.Visible)
	end
	if phase == "Playing" and Engine.now() >= nextAct then
		nextAct = Engine.now() + 0.4
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local origin = Config.ArenaOrigin
			humanoid:MoveTo(origin + Vector3.new(math.random(-15, 15), 0, math.random(-15, 15)))
		end
		for name, handler in Engine.boundActions do
			if name ~= "Party_SpectateCycle" then
				handler("x", Enum.UserInputState.Begin, nil)
			end
		end
		-- also tap the on-screen buttons like a phone player would
		local actionBar = playerGui.PartyUI:FindFirstChild("ActionBar")
		for _, button in (actionBar and actionBar:GetChildren() or {}) do
			if button.ClassName == "TextButton" then
				button.Activated:Fire()
			end
		end
		-- and poke the spectator arrows if they're up
		local bar = playerGui.PartyUI:FindFirstChild("SpectatorBar")
		if bar and bar.Visible then
			bar.Next.Activated:Fire()
		end
		Engine.fireServerRaw(inputRemote, player, { Kind = "Action", Action = "DeleteServer" })
		Engine.fireServerRaw(inputRemote, player, { Kind = "Action", Action = 5 })
	end
	return false
end

-- Per-round invariants checked right when the round returns to the lobby.
local checkedRounds = 0
local function checkRound(round, index)
	local label = ("round %d (%s)"):format(index, tostring(round.Minigame))
	local expected = { "Vote", "Instructions", "Countdown", "Countdown", "Countdown", "Playing", "Finished", "Results", "Lobby" }
	check(
		table.concat(round.Phases, ",") == table.concat(expected, ","),
		label .. ": phase order was " .. table.concat(round.Phases, ",")
	)
	check(#(round.Participants or {}) == 4, label .. ": expected 4 participants")
	local bots = 0
	for _, p in round.Participants or {} do
		if p.IsBot then
			bots += 1
		end
	end
	check(bots == 3, label .. ": expected 3 bots, got " .. bots)

	local results = round.Results or {}
	check(#results == 4, label .. ": expected 4 result rows")
	local last = 0
	for i, row in results do
		check(row.Placement >= last, label .. ": placements not sorted")
		check(row.Placement >= 1 and row.Placement <= i, label .. ": bad placement " .. row.Placement)
		check(row.Coins == (Config.CoinsByPlacement[row.Placement] or 0), label .. ": wrong coins for " .. row.Name)
		last = row.Placement
	end
	check(results[1] and results[1].Placement == 1, label .. ": nobody placed 1st")
	check(round.ChipCount == 4, label .. ": expected 4 player chips")
	check(round.SawChipValue, label .. ": no ReportProgress values reached the chips")
	check(round.SawScriptable, label .. ": camera never went Scriptable")
	check(Engine.Workspace.CurrentCamera.CameraType == Enum.CameraType.Custom, label .. ": camera not restored")
	check(not playerGui.PartyUI.ActionBar.Visible, label .. ": action bar left visible")
	check(not playerGui.PartyUI.SpectatorBar.Visible, label .. ": spectator bar left visible")
	if round.Minigame ~= "Falling Platforms" then
		check(round.SawActionBar, label .. ": action buttons never shown")
	end

	-- World state back to normal
	for _, child in Engine.Workspace:GetChildren() do
		check(string.sub(child.Name, 1, 6) ~= "Arena_", label .. ": arena not cleaned up")
	end
	for _, d in Engine.Workspace:GetDescendants() do
		check(d.ClassName ~= "Highlight", label .. ": leftover Highlight")
	end
	for _, bot in Engine.Workspace.PartyBots:GetChildren() do
		local humanoid = bot:FindFirstChildOfClass("Humanoid")
		check(humanoid and humanoid.Health > 0 and humanoid.WalkSpeed == 16, label .. ": bot not reset " .. bot.Name)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		check(humanoid.WalkSpeed == 16, label .. ": player still frozen")
		check(player.Character.HumanoidRootPart.Position.Y < 40, label .. ": player not back in lobby")
	end
end

local ROUNDS = 9
Engine.run(60 * 30, function()
	humanBrain()
	for index, round in rounds do
		if round.Done and index > checkedRounds then
			checkedRounds = index
			checkRound(round, index)
		end
	end
	return checkedRounds >= ROUNDS
end)
check(checkedRounds >= ROUNDS, ("only %d/%d rounds completed"):format(checkedRounds, ROUNDS))

local played = {}
for _, round in rounds do
	if round.Minigame then
		played[round.Minigame] = true
	end
end
check(played["Hot Potato"], "Hot Potato never played")
check(played["Falling Platforms"], "Falling Platforms never played")
check(played["Mash Dash"], "Mash Dash never played")
local sawSpectator = false
for _, round in rounds do
	sawSpectator = sawSpectator or round.SawSpectator
end
check(sawSpectator, "eliminated player never got the spectator camera/bar")
local coins = player.leaderstats.Coins.Value
check(coins > 0, "player never earned coins")

-- UI sanity: results screen built rows during the last round.
local ui = playerGui:FindFirstChild("PartyUI")
check(ui ~= nil, "client UI missing")

-- Scenario: the real player rage-quits mid-round; the round must still finish cleanly.
local leaveRoundIndex = #rounds + 1
local left = false
Engine.run(60 * 10, function()
	local round = rounds[leaveRoundIndex]
	if not left and round and round.Phases[#round.Phases] == "Playing" then
		Engine.task.delay(2, function()
			Engine.removePlayer(player)
		end)
		left = true
	end
	return left and Engine.now() > 0 and #Engine.Players:GetPlayers() == 0 and Engine.Workspace:FindFirstChild("Arena_HotPotato") == nil
		and Engine.Workspace:FindFirstChild("Arena_FallingPlatforms") == nil
end)
Engine.run(15)
check(left, "leave scenario never reached Playing")
check(rounds[leaveRoundIndex] and not rounds[leaveRoundIndex].Done, "leave round should not have reached the leaver's client")

-- A new player joins the empty server: the loop must recover and start a fresh round.
local roundsBefore = #rounds
local newcomer = Engine.addPlayer("Newcomer", 2002)
Engine.run(60, function()
	local round = rounds[#rounds]
	return #rounds > roundsBefore and round.Phases[#round.Phases] == "Playing"
end)
check(#rounds > roundsBefore, "server did not start a new round after a player rejoined")
local _ = newcomer

-- Report
print(("Seed %d: %d rounds played"):format(SEED, checkedRounds))
for _, round in rounds do
	if round.Results then
		local line = {}
		for _, row in round.Results do
			table.insert(line, ("%s%s=%d(+%d)"):format(if row.IsBot then "🤖" else "", row.Name, row.Placement, row.Coins))
		end
		print(("  %-18s %s"):format(round.Minigame, table.concat(line, "  ")))
		if VERBOSE then
			print("     " .. table.concat(round.Toasts or {}, " | "))
		end
	end
end
for _, w in Engine.warnings do
	table.insert(failures, "warn: " .. w)
end
for _, e in Engine.errors do
	table.insert(failures, "error: " .. e)
end
if #failures > 0 then
	print(("\nFAILED (%d):"):format(#failures))
	for _, f in failures do
		print(" - " .. f)
	end
	error("simulation failed")
end
print("PASS")
