--[[
	MinigameManager
	Runs one minigame round from start to finish. The server owns all game state;
	clients only receive PartyState messages and send validated inputs.

	Round flow (MinigameManager.runRound):
	  Vote -> Instructions (arena is built + everyone teleported & frozen)
	       -> Countdown 3-2-1 -> Playing -> Finished -> back to lobby -> Results

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
local ResultsUtil = require(script.Parent.ResultsUtil)
local RoundContext = require(script.Parent.RoundContext)

local MinigameManager = {}

local stateRemote = Net.stateRemote()
local inputRemote = Net.inputRemote()
local rng = Random.new()

local registry = {} -- { { Id = moduleName, Definition = module table } }

local state = {
	PhaseMessage = { Type = Net.Message.Phase, Phase = Net.Phase.Lobby } :: any,
	Status = nil :: string?,
	Participants = {},
	ByPlayer = {} :: { [Player]: any },
	Vote = nil :: any, -- { Choices, Votes = { [participant] = choiceIndex } }
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

-- Counts votes per card; also returns who voted for what (shown under each card).
local function tallyVotes(vote)
	local counts, voters = {}, {}
	for i = 1, #vote.Choices do
		counts[i] = 0
		voters[i] = {}
	end
	for participant, choice in vote.Votes do
		counts[choice] += 1
		table.insert(voters[choice], participant.Name)
	end
	return counts, voters
end

local function voteUpdateMessage(vote)
	local counts, voters = tallyVotes(vote)
	return { Type = Net.Message.VoteUpdate, Counts = counts, Voters = voters }
end

-- Late joiners / reloaded clients get the current screen re-sent.
local function sendSnapshot(player: Player)
	stateRemote:FireClient(player, state.PhaseMessage)
	if state.Vote then
		stateRemote:FireClient(player, voteUpdateMessage(state.Vote))
	end
	if state.Status then
		stateRemote:FireClient(player, { Type = Net.Message.Status, Text = state.Status })
	end
end

-- Registry ----------------------------------------------------------------------------

local REQUIRED_FUNCTIONS = { "Setup", "Start", "Cleanup", "GetResults" }

local function validateDefinition(definition): string?
	if type(definition) ~= "table" then
		return "module must return a table"
	end
	local info = definition.Info
	if type(info) ~= "table" then
		return "missing Info table"
	end
	if type(info.Name) ~= "string" or type(info.Description) ~= "string" then
		return "Info.Name and Info.Description must be strings"
	end
	if type(info.Duration) ~= "number" or info.Duration <= 0 then
		return "Info.Duration must be a positive number"
	end
	if not table.find({ "FFA", "1v3", "2v2" }, info.Layout) then
		return "Info.Layout must be FFA, 1v3 or 2v2"
	end
	for _, name in REQUIRED_FUNCTIONS do
		if type(definition[name]) ~= "function" then
			return ("missing function %s"):format(name)
		end
	end
	return nil
end

local function loadMinigames()
	local folder = script.Parent:WaitForChild("Minigames")
	for _, module in folder:GetChildren() do
		if not module:IsA("ModuleScript") or string.sub(module.Name, 1, 1) == "_" then
			continue
		end
		local ok, definition = pcall(require, module)
		local problem = if ok then validateDefinition(definition) else tostring(definition)
		if problem then
			warn(("[MinigameManager] Skipping minigame %s: %s"):format(module.Name, problem))
			continue
		end
		table.insert(registry, { Id = module.Name, Definition = definition })
	end
	table.sort(registry, function(a, b)
		return a.Id < b.Id
	end)
	print(("[MinigameManager] Loaded %d minigame(s)"):format(#registry))
end

local function describeMinigame(entry)
	local info = entry.Definition.Info
	return {
		Id = entry.Id,
		Name = info.Name,
		Description = info.Description,
		Layout = info.Layout,
		Duration = info.Duration,
		Controls = info.Controls or {},
	}
end

local function findEntry(id: string)
	for _, entry in registry do
		if entry.Id == id then
			return entry
		end
	end
	return nil
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

-- Voting -------------------------------------------------------------------------------

local function castVote(participant, choice)
	local vote = state.Vote
	if not vote or participant.Left then
		return
	end
	-- Inputs are untrusted: must be an integer index of a real card.
	if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > #vote.Choices then
		return
	end
	vote.Votes[participant] = choice
	broadcast(voteUpdateMessage(vote))
end

local function everyoneVoted(vote, participants): boolean
	for _, participant in participants do
		if not participant.Left and vote.Votes[participant] == nil then
			return false
		end
	end
	return true
end

local function runVote(participants)
	local pool = table.clone(registry)
	for i = #pool, 2, -1 do -- shuffle
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local choices = {}
	for i = 1, math.min(Config.VoteChoices, #pool) do
		table.insert(choices, describeMinigame(pool[i]))
	end
	if #choices < Config.VoteChoices and #registry > 1 then
		table.insert(choices, table.clone(Config.RandomChoice))
	end

	local vote = { Choices = choices, Votes = {} }
	state.Vote = vote
	local endsAt = now() + Config.VoteDuration
	setPhase(Net.Phase.Vote, { Choices = choices, EndsAt = endsAt })
	broadcast(voteUpdateMessage(vote))

	-- Bots vote after a short "thinking" delay, through the same validated path as players.
	for _, participant in participants do
		if participant.IsBot then
			task.delay(rng:NextNumber(Config.BotVoteDelay[1], Config.BotVoteDelay[2]), function()
				if state.Vote == vote then
					castVote(participant, rng:NextInteger(1, #choices))
				end
			end)
		end
	end

	while now() < endsAt and not everyoneVoted(vote, participants) do
		task.wait(0.1)
	end
	if now() < endsAt then
		task.wait(1) -- everyone voted early: let them see the final tally for a beat
	end
	state.Vote = nil

	-- Most votes wins; ties (and no votes at all) are broken randomly.
	local tally = tallyVotes(vote)
	local best, bestCount = {}, -1
	for i, count in tally do
		if count > bestCount then
			best, bestCount = { i }, count
		elseif count == bestCount then
			table.insert(best, i)
		end
	end
	local winner = choices[best[rng:NextInteger(1, #best)]]

	if winner.Id == Config.RandomChoice.Id then
		return registry[rng:NextInteger(1, #registry)]
	end
	return findEntry(winner.Id)
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
		if reason == "Left" then ("👋 %s rage quit"):format(participant.Name) else ("💀 %s got bonked"):format(participant.Name)
	)
	safeCall(active.Instance, "OnParticipantLost", participant, reason)
end

-- Same entry point for real-player inputs (via the remote) and bot inputs (bot:Input).
local function submitAction(participant, action: string)
	local active = state.Active
	if not active or state.PhaseMessage.Phase ~= Net.Phase.Playing or active.Round.Ended then
		return
	end
	if not active.Actions[action] or active.Round:IsEliminated(participant) or not participant:IsAlive() then
		return
	end
	safeCall(active.Instance, "OnInput", participant, action)
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
	This is the hook a future board game calls between turns.
]]
function MinigameManager.runRound(participants)
	assert(#registry > 0, "No minigames loaded")
	state.Participants = participants
	state.ByPlayer = {}
	for _, participant in participants do
		if participant.Player then
			state.ByPlayer[participant.Player] = participant
		end
	end

	-- 1. Vote
	local entry = runVote(participants)
	local definition = entry.Definition
	local info = definition.Info
	local described = describeMinigame(entry)
	assignTeams(participants, info.Layout)

	-- 2. Build the arena + a fresh minigame instance (all per-round state lives on it)
	local arena = Arena.create(entry.Id)
	local round = RoundContext.new({
		Participants = participants,
		Arena = arena,
		Broadcast = broadcast,
		SetStatus = setStatus,
	})
	local instance = setmetatable({ Round = round, Arena = arena, Participants = participants }, { __index = definition })

	local actions = {}
	for _, control in info.Controls or {} do
		actions[control.Action] = true
	end
	state.Active = {
		Entry = entry,
		Instance = instance,
		Round = round,
		Arena = arena,
		Actions = actions,
		Connections = {},
	}

	-- 3. Instructions card; build the map and teleport while everyone reads it
	local instructionsEnd = now() + Config.InstructionsDuration
	setPhase(Net.Phase.Instructions, {
		Minigame = described,
		Participants = describeParticipants(participants),
		EndsAt = instructionsEnd,
	})

	local spawns = instance:Setup(arena, participants, round) or {}
	ensureBodies(participants)
	for index, participant in participants do
		local spawn = spawns[index] or (arena.Origin + Vector3.new(index * 4, 4, 0))
		participant:Teleport(spawn)
		participant:Freeze()
	end
	task.wait(math.max(0, instructionsEnd - now()))

	-- 4. Countdown
	for number = Config.CountdownFrom, 1, -1 do
		setPhase(Net.Phase.Countdown, { Number = number, Minigame = described })
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
			participant:ResetMovement()
		else
			onParticipantLost(participant, "Died")
		end
	end

	round.EndsAt = now() + info.Duration
	setPhase(Net.Phase.Playing, {
		Minigame = described,
		Participants = describeParticipants(participants),
		EndsAt = round.EndsAt,
	})
	BotService.setBrain(function(bot, dt)
		if instance.UpdateBot and not round.Ended and not round:IsEliminated(bot.Participant) then
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
	local rows = awardCoins(results)
	setPhase(Net.Phase.Results, {
		Minigame = described,
		Results = rows,
		EndsAt = now() + Config.ResultsDuration,
	})
	task.wait(Config.ResultsDuration)
	return results, rows
end

-- Emergency stop if anything in runRound threw. Leaves the server ready for the next round.
function MinigameManager.abort(message: string?)
	state.Vote = nil
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
		local participant = state.ByPlayer[player]
		if not participant then
			return -- spectators (5th+ player) can't vote or act
		end
		if kind == Net.Input.Vote then
			castVote(participant, payload.Choice)
		elseif kind == Net.Input.Action and type(payload.Action) == "string" then
			submitAction(participant, payload.Action)
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
		if state.Vote then
			state.Vote.Votes[participant] = nil
			broadcast(voteUpdateMessage(state.Vote))
		end
		onParticipantLost(participant, "Left")
	end)
end

return MinigameManager
