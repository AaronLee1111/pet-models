--[[
	MinigameManager
	Runs one minigame round from start to finish. The server owns all game state;
	clients only receive PartyState messages and send validated inputs.

	Round flow (MinigameManager.runRound):
	  Select (the server picks the minigame; clients animate the pick as a roulette)
	    -> Instructions (tutorial: preview, controls, ready-up; the arena is built and everyone
	       teleported & frozen meanwhile) -> Countdown 3-2-1 -> Playing -> Finished
	    -> back to lobby -> Results
	Nobody votes: the pick is server-authoritative (MinigameManager.pick).

	Minigames are ModuleScripts in PartyServer/Minigames (names starting with "_" are
	ignored, e.g. _Template). See _Template.luau for the full interface.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local Arena = require(script.Parent.Arena)
local BotService = require(script.Parent.BotService)
local CoinService = require(script.Parent.CoinService)
local MinigameInfo = require(script.Parent.MinigameInfo)
local ReadyState = require(script.Parent.ReadyState)
local ResultsUtil = require(script.Parent.ResultsUtil)
local RoundContext = require(script.Parent.RoundContext)
local Tutorial = require(script.Parent.Tutorial)

local MinigameManager = {}

local stateRemote = Net.stateRemote()
local inputRemote = Net.inputRemote()
local rng = Random.new()

local registry = {} -- { { Id = moduleName, Definition = module table } }
local extraInputHandler: ((Player, any) -> boolean)? = nil -- board game / lobby inputs
local readyHooks: { (Player) -> () } = {}

local state = {
	PhaseMessage = { Type = Net.Message.Phase, Phase = Net.Phase.Lobby } :: any,
	Status = nil :: string?,
	Participants = {},
	ByPlayer = {} :: { [Player]: any },
	Tutorial = nil :: any, -- Instructions phase: a ReadyState
	History = { Normal = {}, Duel = {} } :: any, -- minigame ids picked, newest first
	Active = nil :: any, -- the round in progress, see runRound
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Messaging ---------------------------------------------------------------------------

local function broadcast(message)
	stateRemote:FireAllClients(message)
end

local function setPhase(phase: string, data)
	local message = data or {}
	message.Type = Net.Message.Phase
	message.Phase = phase
	state.PhaseMessage = message
	if phase ~= Net.Phase.Playing then
		state.Status = nil
	end
	broadcast(message)
end

local function setStatus(text: string?)
	state.Status = text
	broadcast({ Type = Net.Message.Status, Text = text })
end

local function describeParticipants(participants)
	local list = {}
	for _, participant in participants do
		table.insert(list, participant:Describe())
	end
	return list
end

-- Player chips ----------------------------------------------------------------------------
-- One chip per participant: name, team, live value reported by the minigame, eliminated flag.
-- Updates are batched and sent at most every Config.ChipFlushInterval seconds.

local chipFlushQueued = false

local function chipsMessage()
	local active = state.Active
	local chips = {}
	for _, participant in state.Participants do
		local chip = participant:Describe()
		local progress = active and active.Progress[participant]
		chip.Value = progress and progress.Value
		chip.Label = progress and progress.Label or (active and active.Described.ProgressLabel)
		chip.Eliminated = active ~= nil and active.Round:IsEliminated(participant)
		chip.Character = participant:GetCharacter() -- lets clients spectate this participant
		table.insert(chips, chip)
	end
	return { Type = Net.Message.Chips, Chips = chips }
end

local function queueChipFlush()
	if chipFlushQueued then
		return
	end
	chipFlushQueued = true
	task.delay(Config.ChipFlushInterval, function()
		chipFlushQueued = false
		broadcast(chipsMessage())
	end)
end

local function readyMessage(tutorial)
	return { Type = Net.Message.TutorialReady, Ready = tutorial:ids(), Left = tutorial:leftIds() }
end

-- Late joiners / reloaded clients get the current screen re-sent.
local function sendSnapshot(player: Player)
	stateRemote:FireClient(player, state.PhaseMessage) -- Select / Instructions carry their own timing
	if state.Tutorial then
		stateRemote:FireClient(player, readyMessage(state.Tutorial))
	end
	if state.Status then
		stateRemote:FireClient(player, { Type = Net.Message.Status, Text = state.Status })
	end
	if state.Active then
		stateRemote:FireClient(player, chipsMessage())
	end
	for _, hook in readyHooks do
		task.spawn(hook, player)
	end
end

-- Registry ----------------------------------------------------------------------------

local function loadMinigames()
	if #registry > 0 then
		return -- already loaded (init, or a test that loaded it first)
	end
	local folder = script.Parent:WaitForChild("Minigames")
	for _, module in folder:GetChildren() do
		if not module:IsA("ModuleScript") or string.sub(module.Name, 1, 1) == "_" then
			continue
		end
		local ok, definition = pcall(require, module)
		local problem = if ok then MinigameInfo.validate(definition) else tostring(definition)
		if problem then
			warn(("[MinigameManager] Skipping minigame %s: %s"):format(module.Name, problem))
			continue
		end
		table.insert(registry, {
			Id = module.Name,
			Definition = definition,
			Described = MinigameInfo.normalize(module.Name, definition.Info),
		})
	end
	table.sort(registry, function(a, b)
		return a.Id < b.Id
	end)
	print(("[MinigameManager] Loaded %d minigame(s)"):format(#registry))
end

local function describeMinigame(entry)
	return table.clone(entry.Described)
end

-- Calls an optional minigame method, logging (not propagating) errors.
local function safeCall(instance, methodName: string, ...)
	local method = instance[methodName]
	if type(method) ~= "function" then
		return true, nil
	end
	local ok, result = pcall(method, instance, ...)
	if not ok then
		warn(("[MinigameManager] %s:%s errored: %s"):format(instance.Info.Name, methodName, tostring(result)))
	end
	return ok, result
end

-- Selection ----------------------------------------------------------------------------
-- The server picks; clients only animate the pick. Nobody votes.

local CATEGORY_TITLES = {
	FFA = "FREE-FOR-ALL MINIGAME",
	["2v2"] = "2 vs 2 MINIGAME",
	["1v3"] = "1 vs 3 MINIGAME",
	Duel = "DUEL MINIGAME",
}

-- Layouts that fit `count` players.
local function layoutFits(layout: string, count: number): boolean
	if layout == "Duel" then
		return count == 2
	elseif layout == "1v3" or layout == "2v2" then
		return count == 4
	end
	return count >= 2
end

-- Minigames a round can pick from: Duel games only for duels, never in normal rounds.
local function selectionPool(duel: boolean, count: number)
	local pool = {}
	for _, entry in registry do
		local layout = entry.Definition.Info.Layout
		if (layout == "Duel") == duel and layoutFits(layout, count) then
			table.insert(pool, entry)
		end
	end
	return pool
end

--[[
	Picks one entry from `pool`, every eligible game equally likely, avoiding repeats:
	never the previous pick (recent[1]) while anything else is eligible, and not the previous
	two when the pool has at least Config.AvoidTwoPoolSize games. No game is ever excluded for
	good. `recent` = ids, newest first. `random` = a Random (seed it in tests).
]]
function MinigameManager.pick(pool, recent, random)
	assert(#pool > 0, "empty minigame pool")
	local avoid = if #pool >= Config.AvoidTwoPoolSize then 2 else 1
	local options = {}
	for _, entry in pool do
		local repeated = false
		for i = 1, math.min(avoid, #recent) do
			repeated = repeated or recent[i] == entry.Id
		end
		if not repeated then
			table.insert(options, entry)
		end
	end
	if #options == 0 then
		options = pool
	end
	return options[random:NextInteger(1, #options)]
end

--[[
	The roulette every client plays: the highlight starts on row `Start` and moves `Steps`
	rows (wrapping) to land on the picked row. Chosen here so all clients agree.
]]
function MinigameManager.rouletteSteps(count: number, resultIndex: number, random)
	local start = random:NextInteger(1, count)
	local steps = 16 + random:NextInteger(0, 3)
	if count > 1 then
		while (start - 1 + steps) % count ~= resultIndex - 1 do
			steps += 1
		end
	end
	return start, steps
end

-- Picks (or takes the forced `entry`), shows the roulette, records the history. Returns the entry.
local function runSelection(participants, duel: boolean, forced)
	local kind = if duel then "Duel" else "Normal"
	local history = state.History[kind]
	local candidates = selectionPool(duel, #participants)
	local entry = forced or MinigameManager.pick(candidates, history, rng)
	local layout = entry.Definition.Info.Layout
	if not table.find(candidates, entry) then
		table.insert(candidates, entry) -- a forced pick outside the pool (tests)
	end
	local names, resultIndex = {}, 1
	for index, candidate in candidates do
		table.insert(names, candidate.Definition.Info.Name)
		if candidate == entry then
			resultIndex = index
		end
	end
	local start, steps = MinigameManager.rouletteSteps(#names, resultIndex, rng)
	local startsAt = now() + 0.3 -- a beat so every client receives it before the first tick
	-- The roulette runs over every game this round could have picked (every eligible game is
	-- equally likely, whatever its layout), so the category is revealed with the result.
	setPhase(Net.Phase.Select, {
		Category = layout,
		Title = if duel then CATEGORY_TITLES.Duel else "MINIGAME TIME!",
		ResultTitle = CATEGORY_TITLES[layout] or "MINIGAME",
		Candidates = names,
		ResultIndex = resultIndex,
		ResultId = entry.Id,
		Start = start,
		Steps = steps,
		StartsAt = startsAt,
		SpinEndsAt = startsAt + Config.SelectDuration - Config.SelectHold,
		EndsAt = startsAt + Config.SelectDuration,
	})
	table.insert(history, 1, entry.Id)
	history[3] = nil
	task.wait(math.max(0, startsAt + Config.SelectDuration - now()))
	return entry
end

-- Tutorial ready-up ----------------------------------------------------------------------

local function markReady(participant)
	local tutorial = state.Tutorial
	if tutorial and tutorial:mark(participant, state.PhaseMessage.Phase, now()) then
		broadcast(readyMessage(tutorial))
	end
end

-- Teams ----------------------------------------------------------------------------------

local function assignTeams(participants, layout: string)
	local shuffled = table.clone(participants)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	for i, participant in shuffled do
		if layout == "1v3" then
			participant.Team = if i == 1 then 1 else 2 -- team 1 is the solo player
		elseif layout == "2v2" then
			participant.Team = if i <= 2 then 1 else 2
		else
			participant.Team = nil
		end
	end
end

-- Round lifecycle --------------------------------------------------------------------------

local function returnToLobby(participants)
	BotService.reviveAll(Arena.lobbySpot)
	for index, participant in participants do
		participant.Team = nil
		if participant:IsAlive() then
			participant:Teleport(Arena.lobbySpot(index))
			participant:ResetMovement()
		end
		-- Dead real players simply respawn at the lobby SpawnLocation.
	end
end

-- Tears down the active round. Safe to call more than once (used by abort too).
local function finishRound()
	local active = state.Active
	if not active then
		return
	end
	state.Active = nil
	BotService.setBrain(nil)
	for _, connection in active.Connections do
		connection:Disconnect()
	end
	safeCall(active.Instance, "Cleanup")
	Arena.destroy(active.Arena)
	returnToLobby(active.Round.Participants)
	if state.Status then
		setStatus(nil)
	end
end

-- A participant died, reset, or left mid-round: they are out.
local function onParticipantLost(participant, reason: string)
	local active = state.Active
	if not active or active.Round.Ended or active.Round:IsEliminated(participant) then
		return
	end
	active.Round:Eliminate(participant, true)
	active.Round:Toast(
		if reason == "Left" then ("👋 %s left the game"):format(participant.Name) else ("💥 %s is out"):format(participant.Name)
	)
	safeCall(active.Instance, "OnParticipantLost", participant, reason)
end

-- True if `participant` may press `action` right now (playing, alive, in this round).
local function canAct(participant, action: string): boolean
	local active = state.Active
	if not active or state.PhaseMessage.Phase ~= Net.Phase.Playing or active.Round.Ended then
		return false
	end
	if not active.Actions[action] or active.Round:IsEliminated(participant) or not participant:IsAlive() then
		return false
	end
	-- Only people playing this round (a duel has two; everyone else just watches).
	return table.find(active.Round.Participants, participant) ~= nil
end

-- Same entry point for real-player inputs (via the remote) and bot inputs (bot:Input).
local function submitAction(participant, action: string)
	if not canAct(participant, action) then
		return
	end
	Tutorial.complete(participant, "UsedMinigameAction") -- bots are ignored
	safeCall(state.Active.Instance, "OnInput", participant, action)
end

local function awardCoins(results)
	local rows = {}
	for _, result in results do
		local participant = result.Participant
		local coins = if participant.Left then 0 else (Config.CoinsByPlacement[result.Placement] or 0)
		local total = CoinService.add(participant, coins)
		local row = participant:Describe()
		row.Placement = result.Placement
		row.Coins = coins
		row.Total = total
		table.insert(rows, row)
	end
	return rows
end

local function ensureBodies(participants)
	BotService.reviveAll(Arena.lobbySpot)
	for _, participant in participants do
		if not participant.IsBot and not participant.Left and not participant:IsAlive() then
			pcall(function()
				participant.Player:LoadCharacter()
			end)
		end
	end
end

--[[
	Plays one full round with exactly Config.PlayersPerMatch participants.
	Returns the normalized ranked results and the coin rows shown on the results screen.
	BoardGame calls this after every full turn cycle.
]]
function MinigameManager.runRound(participants, options)
	options = options or {}
	assert(#registry > 0, "No minigames loaded")
	state.Participants = participants
	state.ByPlayer = {}
	for _, participant in participants do
		if participant.Player then
			state.ByPlayer[participant.Player] = participant
		end
	end

	-- 1. Pick the minigame (the server decides; the roulette only shows it). options.Entry
	-- forces the result (tests / harnesses); the roulette still lands on it.
	local entry = runSelection(participants, options.Duel == true, options.Entry)
	local definition = entry.Definition
	local info = definition.Info
	local described = describeMinigame(entry)
	assignTeams(participants, info.Layout)

	-- 2. Build the arena + a fresh minigame instance (all per-round state lives on it)
	local arena = Arena.create(entry.Id)
	local progress = {}
	local round = RoundContext.new({
		Participants = participants,
		Arena = arena,
		Broadcast = broadcast,
		SetStatus = setStatus,
		OnProgress = function(participant, value, label)
			progress[participant] = { Value = value, Label = label }
			queueChipFlush()
		end,
		OnEliminated = queueChipFlush,
	})
	local instance = setmetatable({ Round = round, Arena = arena, Participants = participants }, { __index = definition })

	local actions = {}
	for _, control in described.Controls.Actions do
		actions[control.Action] = true
		if control.Hold then
			actions[control.Action .. "Stop"] = true
		end
	end
	state.Active = {
		Entry = entry,
		Instance = instance,
		Round = round,
		Arena = arena,
		Actions = actions,
		Described = described,
		Progress = progress,
		Connections = {},
	}

	-- 3. Tutorial: preview + controls + ready-up; build the map and teleport meanwhile.
	-- READY unlocks after one preview loop; bots ready themselves; the round starts when
	-- everyone still here is ready, or at the timeout (an idle player never blocks it).
	local readyAt = now() + Config.TutorialMinDuration
	local instructionsEnd = now() + Config.InstructionsDuration
	local tutorial = ReadyState.new(participants, readyAt)
	state.Tutorial = tutorial
	ensureBodies(participants) -- so every portrait has an avatar to show
	local tutorialParticipants = describeParticipants(participants)
	for index, participant in participants do
		tutorialParticipants[index].Character = participant:GetCharacter() -- avatar portraits
	end
	setPhase(Net.Phase.Instructions, {
		Minigame = described,
		Participants = tutorialParticipants,
		ArenaOrigin = arena.Origin,
		ReadyAt = readyAt,
		EndsAt = instructionsEnd,
	})
	broadcast(readyMessage(tutorial))
	for _, participant in participants do
		if participant.IsBot then
			task.delay(Config.TutorialMinDuration + rng:NextNumber(Config.BotReadyDelay[1], Config.BotReadyDelay[2]), function()
				if state.Tutorial == tutorial then
					markReady(participant)
				end
			end)
		end
	end

	local spawns = instance:Setup(arena, participants, round) or {}
	ensureBodies(participants)
	for index, participant in participants do
		local spawn = spawns[index] or (arena.Origin + Vector3.new(index * 4, 4, 0))
		participant:Teleport(spawn)
		participant:Freeze()
	end
	broadcast(chipsMessage()) -- characters exist now, so spectating works from the start
	while now() < instructionsEnd and not (now() >= readyAt and tutorial:everyone()) do
		task.wait(0.1)
	end
	if now() < instructionsEnd then
		task.wait(0.6) -- everyone's ready: let the last READY show for a beat
	end
	state.Tutorial = nil

	-- 4. Countdown
	for number = Config.CountdownFrom, 1, -1 do
		setPhase(Net.Phase.Countdown, { Number = number, Minigame = described, ArenaOrigin = arena.Origin })
		task.wait(1)
	end

	-- 5. Play
	for _, participant in participants do
		local humanoid = participant:GetHumanoid()
		if humanoid then
			table.insert(
				state.Active.Connections,
				humanoid.Died:Connect(function()
					onParticipantLost(participant, "Died")
				end)
			)
		end
		if participant:IsAlive() then
			participant:ApplyControls(described.Controls) -- server-side movement locking
		else
			onParticipantLost(participant, "Died")
		end
	end

	round.EndsAt = now() + info.Duration
	setPhase(Net.Phase.Playing, {
		Minigame = described,
		Participants = describeParticipants(participants),
		ArenaOrigin = arena.Origin,
		EndsAt = round.EndsAt,
	})
	BotService.setBrain(function(bot, dt)
		if
			instance.UpdateBot
			and not round.Ended
			and table.find(participants, bot.Participant)
			and not round:IsEliminated(bot.Participant)
		then
			instance:UpdateBot(bot, dt)
		end
	end)
	safeCall(instance, "Start")

	while not round.Ended and now() < round.EndsAt do
		task.wait(0.1)
	end
	local reason = if round.Ended then round.EndReason else "TimeUp"
	round:End(reason)
	BotService.setBrain(nil)
	safeCall(instance, "OnRoundEnding", reason)

	-- 6. Freeze, collect results, clean up, go home
	for _, participant in participants do
		if participant:IsAlive() then
			participant:Freeze()
		end
	end
	setPhase(Net.Phase.Finished, { Minigame = described })
	local ok, rawResults = safeCall(instance, "GetResults")
	local results = ResultsUtil.normalize(if ok then rawResults else nil, participants)
	task.wait(Config.FinishBannerDuration)
	finishRound()

	-- 7. Results screen
	local rows = if options.NoCoins then (function()
		local list = {}
		for _, result in results do
			local row = result.Participant:Describe()
			row.Placement = result.Placement
			row.Coins = 0
			row.Total = CoinService.get(result.Participant)
			table.insert(list, row)
		end
		return list
	end)() else awardCoins(results)
	setPhase(Net.Phase.Results, {
		Minigame = described,
		Results = rows,
		EndsAt = now() + Config.ResultsDuration,
	})
	task.wait(Config.ResultsDuration)
	return results, rows
end

-- Minigames a normal 4-player round picks from (never Duel ones).
function MinigameManager.roundMinigames()
	return selectionPool(false, Config.PlayersPerMatch)
end

-- Loads the minigame registry without starting anything else (tests; init does this too).
MinigameManager.loadMinigames = function()
	loadMinigames()
end

-- Duel minigames (Info.Layout = "Duel") registered, for Duel spaces.
function MinigameManager.duelMinigames()
	local list = {}
	for _, entry in registry do
		if entry.Definition.Info.Layout == "Duel" then
			table.insert(list, entry)
		end
	end
	return list
end

--[[
	Plays a random Duel minigame between two participants (everyone else watches) without
	placement coins. Returns the winning participant, or nil for a draw / no duel minigames.
]]
function MinigameManager.runDuel(a, b)
	local duels = MinigameManager.duelMinigames()
	if #duels == 0 then
		return nil
	end
	local results = MinigameManager.runRound({ a, b }, { Duel = true, NoCoins = true })
	local first = {}
	for _, result in results do
		if result.Placement == 1 then
			table.insert(first, result.Participant)
		end
	end
	return if #first == 1 then first[1] else nil
end

-- Emergency stop if anything in runRound threw. Leaves the server ready for the next round.
function MinigameManager.abort(message: string?)
	state.Tutorial = nil
	finishRound()
	broadcast({ Type = Net.Message.Toast, Text = message or "Round cancelled" })
end

-- Shows the lobby screen and waits `duration` seconds (0 = just show it).
function MinigameManager.showLobby(text: string, duration: number?)
	setPhase(Net.Phase.Lobby, {
		Text = text,
		EndsAt = if duration then now() + duration else nil,
	})
	if duration then
		task.wait(duration)
	end
end

-- Hooks for the board game and lobby, which share the same remotes and phase snapshot.
MinigameManager.setPhase = setPhase
MinigameManager.broadcast = broadcast

function MinigameManager.sendTo(player: Player, message)
	stateRemote:FireClient(player, message)
end

-- fn(player, payload) -> true if it handled the input. Runs after rate limiting, before ready/actions.
function MinigameManager.setInputHandler(fn: ((Player, any) -> boolean)?)
	extraInputHandler = fn
end

-- fn(player) runs whenever a client asks for the current state (join / reload).
function MinigameManager.onReady(fn: (Player) -> ())
	table.insert(readyHooks, fn)
end

function MinigameManager.getMinigames()
	local list = {}
	for _, entry in registry do
		table.insert(list, describeMinigame(entry))
	end
	return list
end

function MinigameManager.init()
	loadMinigames()
	BotService.setActionHandler(submitAction)

	-- Messages from a minigame's own client code go to the running minigame, rate limited.
	-- The minigame must validate them: they are whatever the client chose to send.
	local messageBuckets: { [Player]: { Start: number, Count: number } } = {}
	local function onMinigameMessage(player: Player, payload)
		local clock = os.clock()
		local bucket = messageBuckets[player]
		if not bucket or clock - bucket.Start >= 1 then
			bucket = { Start = clock, Count = 0 }
			messageBuckets[player] = bucket
		end
		bucket.Count += 1
		if bucket.Count > Config.MinigameMessageRateLimit then
			return
		end
		local active = state.Active
		local participant = state.ByPlayer[player]
		if not active or not participant or state.PhaseMessage.Phase ~= Net.Phase.Playing or active.Round.Ended then
			return
		end
		if active.Round:IsEliminated(participant) then
			return
		end
		safeCall(active.Instance, "OnClientMessage", participant, payload)
	end
	Net.minigameRemote().OnServerEvent:Connect(onMinigameMessage)
	Net.minigameFastRemote().OnServerEvent:Connect(onMinigameMessage)
	Players.PlayerRemoving:Connect(function(player)
		messageBuckets[player] = nil
	end)

	-- Rate limit: at most Config.InputRateLimit inputs per player per second.
	local buckets: { [Player]: { Start: number, Count: number } } = {}
	inputRemote.OnServerEvent:Connect(function(player: Player, payload)
		if type(payload) ~= "table" then
			return
		end
		local clock = os.clock()
		local bucket = buckets[player]
		if not bucket or clock - bucket.Start >= 1 then
			bucket = { Start = clock, Count = 0 }
			buckets[player] = bucket
		end
		bucket.Count += 1
		if bucket.Count > Config.InputRateLimit then
			return
		end

		local kind = payload.Kind
		if kind == Net.Input.Ready then
			sendSnapshot(player)
			return
		end
		if extraInputHandler and extraInputHandler(player, payload) then
			return
		end
		local participant = state.ByPlayer[player]
		if not participant then
			return -- spectators (5th+ player) can't ready up or act
		end
		if kind == Net.Input.TutorialReady then
			markReady(participant) -- yourself only; ReadyState checks the phase and the unlock time
		elseif kind == Net.Input.Action and type(payload.Action) == "string" then
			submitAction(participant, payload.Action)
		elseif kind == Net.Input.ActionUsed and type(payload.Action) == "string" then
			-- The minigame's own client code sent this action (e.g. Bumper Bout's dash); it only
			-- counts for the tutorial, and only when that action could really be pressed now.
			if canAct(participant, payload.Action) then
				Tutorial.complete(participant, "UsedMinigameAction")
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		local participant = state.ByPlayer[player]
		if not participant then
			return
		end
		participant.Left = true
		state.ByPlayer[player] = nil
		if state.Tutorial then
			broadcast(readyMessage(state.Tutorial)) -- they no longer block the start
		end
		onParticipantLost(participant, "Left")
	end)
end

return MinigameManager
