--[[
	BoardGame
	Runs one board-game match in the world: builds the board, takes turns (roll -> move ->
	space), runs a minigame after every full turn cycle, then shows the final standings.
	The rules themselves live in Match; this module adds timing, networking, bodies and bots.

	  BoardGame.play(participants, settings)   -> final standings rows (yields for the whole match)
	  BoardGame.cleanup()                      safe teardown, also after a crash
	  BoardGame.handleInput(player, payload)   -> true if it was a board input (Roll / Choice)

	Players who leave are replaced by a bot that keeps their seat, coins and collectibles.
	Players who join mid-match watch until the next match.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local Arena = require(script.Parent.Parent.Arena)
local BotService = require(script.Parent.Parent.BotService)
local CoinService = require(script.Parent.Parent.CoinService)
local Inventory = require(script.Parent.Parent.Inventory)
local MinigameManager = require(script.Parent.Parent.MinigameManager)
local Participant = require(script.Parent.Parent.Participant)
local BoardLayout = require(script.Parent.BoardLayout)
local BoardWorld = require(script.Parent.BoardWorld)
local Match = require(script.Parent.Match)
local SpaceTypes = require(script.Parent.SpaceTypes)

local BoardGame = {}

local rng = Random.new()
local current = nil -- the running match, see BoardGame.play
local nextPromptId = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function waitRandom(range: { number })
	task.wait(rng:NextNumber(range[1], range[2]))
end

local function isAway(participant): boolean
	return participant.Left or (not participant.IsBot and (not participant.Player or participant.Player.Parent == nil))
end

-- Messages -------------------------------------------------------------------------------------

local function layoutMessage(board)
	local spaces = {}
	for _, id in board.Order do
		local space = board.Spaces[id]
		local spaceType = SpaceTypes[space.Type]
		table.insert(spaces, {
			Id = id,
			Type = space.Type,
			Name = spaceType.Name,
			Color = spaceType.Color,
			Position = current.World.Tops[id],
		})
	end
	local legend = {}
	for key, spaceType in SpaceTypes do
		table.insert(legend, { Type = key, Name = spaceType.Name, Short = spaceType.Short, Color = spaceType.Color })
	end
	return { Type = Net.Message.BoardLayout, Name = board.Name, Spaces = spaces, Legend = legend }
end

local function stateMessage()
	local match = current.Match
	local seats = {}
	for orderIndex, seat in match.Order do
		local participant = seat.Participant
		table.insert(seats, {
			Id = participant.Id,
			Name = participant.Name,
			IsBot = participant.IsBot,
			Order = orderIndex,
			Coins = match:coinsOf(seat),
			Collectibles = match:collectiblesOf(seat),
			SpaceId = seat.SpaceId,
			Character = participant:GetCharacter(),
		})
	end
	local turn = current.Turn
	return {
		Type = Net.Message.BoardState,
		Round = match.Round,
		Rounds = match.Rounds,
		TurnId = turn and turn.Participant.Id,
		TurnName = turn and turn.Participant.Name,
		Stage = current.Stage,
		Roll = current.Roll,
		Remaining = current.Remaining,
		RollEndsAt = current.RollEndsAt,
		Text = current.Text,
		CollectibleSpace = match.CollectibleSpace,
		CollectibleName = Config.Collectible.Name,
		CollectiblePlural = Config.Collectible.Plural,
		CollectiblePrice = Config.Collectible.Price,
		Seats = seats,
	}
end

local function publish()
	if not current then
		return
	end
	local match = current.Match
	current.World:setCollectible(
		match.CollectibleSpace,
		("%s · %d coins"):format(Config.Collectible.Name, Config.Collectible.Price)
	)
	current.StateMessage = stateMessage()
	MinigameManager.broadcast(current.StateMessage)
end

local function feed(text: string?)
	if text and current then
		current.Text = text
		MinigameManager.broadcast({ Type = Net.Message.Toast, Text = text })
	end
end

-- Pieces on the board ---------------------------------------------------------------------------

local function slotOf(seat): number
	local slot = 0
	for _, other in current.Match.Seats do
		if other.SpaceId == seat.SpaceId then
			slot += 1
		end
		if other == seat then
			return slot
		end
	end
	return 1
end

local function placeSeat(seat)
	local participant = seat.Participant
	if not participant:IsAlive() then
		return
	end
	local facing = current.Match.Board:nextOptions(seat.SpaceId)[1]
	participant:Teleport(current.World:spaceCFrame(seat.SpaceId, slotOf(seat), facing))
	participant:Freeze()
	-- Pieces bumping on a shared tile can tip over; stand bots back up (players' own
	-- clients do the same in BoardView).
	local humanoid = participant:GetHumanoid()
	if participant.IsBot and humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function placeAll()
	for _, seat in current.Match.Seats do
		placeSeat(seat)
	end
end

local function ensureBodies()
	BotService.reviveAll(Arena.lobbySpot)
	for _, seat in current.Match.Seats do
		local participant = seat.Participant
		if not participant.IsBot and not isAway(participant) and not participant:IsAlive() then
			pcall(function()
				participant.Player:LoadCharacter()
			end)
		end
	end
end

-- Seats whose player left get a bot that keeps the seat (coins, collectibles, position).
local function refreshSeats()
	local match = current.Match
	for _, seat in match.Seats do
		local leaver = seat.Participant
		if not isAway(leaver) then
			continue
		end
		leaver.Left = true
		local seatedBots = {}
		for _, other in match.Seats do
			if other.Participant.IsBot then
				seatedBots[other.Participant.Bot] = other.Participant
			end
		end
		local count = 0
		for _ in seatedBots do
			count += 1
		end
		-- getBots clears every bot's Participant link, so restore the seated ones after.
		local bots = BotService.getBots(count + 1, Arena.lobbySpot)
		local newcomer
		for _, bot in bots do
			if seatedBots[bot] then
				bot.Participant = seatedBots[bot]
			else
				newcomer = bot
			end
		end
		if newcomer then
			local replacement = Participant.fromBot(newcomer)
			match:replaceParticipant(seat, replacement)
			feed(("%s left, %s takes over their seat"):format(leaver.Name, replacement.Name))
			placeSeat(seat)
		end
	end
end

-- Choices -----------------------------------------------------------------------------------------

-- Match's Ask: players get a prompt on screen, bots decide on their own.
local function ask(seat, request)
	local participant = seat.Participant
	local previousStage = current.Stage
	current.Stage = "Deciding"
	current.Text = ("%s is deciding: %s"):format(participant.Name, request.Prompt)
	publish()

	local answer
	if participant.IsBot or isAway(participant) then
		waitRandom(Config.Board.BotChoiceDelay)
		local skill = if participant.Bot then participant.Bot.Skill else 0.5
		answer = current.Match:botDecision(seat, request, skill)
	else
		nextPromptId += 1
		local prompt = {
			Id = nextPromptId,
			Player = participant.Player,
			Count = #request.Options,
			Answer = nil,
		}
		current.Prompt = prompt
		local endsAt = now() + Config.Board.ChoiceTimeout
		MinigameManager.sendTo(participant.Player, {
			Type = Net.Message.Prompt,
			PromptId = prompt.Id,
			Prompt = request.Prompt,
			Options = request.Options,
			Default = request.Default,
			EndsAt = endsAt,
		})
		while prompt.Answer == nil and now() < endsAt and not isAway(participant) do
			task.wait(0.1)
		end
		current.Prompt = nil
		if participant.Player.Parent then
			MinigameManager.sendTo(participant.Player, { Type = Net.Message.Prompt, PromptId = nil })
		end
		answer = prompt.Answer or request.Default
	end

	current.Stage = previousStage
	publish()
	return answer
end

-- Turns -------------------------------------------------------------------------------------------

local function takeTurn(seat)
	refreshSeats()
	local match = current.Match
	local participant = seat.Participant
	current.Turn = seat
	current.Stage = "Roll"
	current.Roll = nil
	current.Remaining = nil
	current.RollEndsAt = now() + Config.Board.RollTimeout
	current.Text = ("%s's turn"):format(participant.Name)
	current.RollRequested = false
	publish()

	if participant.IsBot or isAway(participant) then
		waitRandom(Config.Board.BotRollDelay)
	else
		current.RollWaiting = participant.Player
		while not current.RollRequested and now() < current.RollEndsAt and not isAway(participant) do
			task.wait(0.05)
		end
		current.RollWaiting = nil
	end

	local roll = match:roll()
	current.Stage = "Moving"
	current.Roll = roll
	current.Remaining = roll
	current.RollEndsAt = nil
	current.Text = ("%s rolled a %d"):format(seat.Participant.Name, roll)
	publish()
	task.wait(0.8)

	local landing = match:move(seat, roll, function(movedSeat, _, remaining)
		current.Remaining = remaining
		placeSeat(movedSeat)
		publish()
		task.wait(Config.Board.HopTime)
	end, function(note)
		feed(note)
		publish()
	end)

	placeAll() -- events can move other pieces too
	current.Stage = "Landed"
	local space = match.Board:get(seat.SpaceId)
	feed(landing or ("%s landed on a %s"):format(seat.Participant.Name, SpaceTypes[space.Type].Name))
	publish()
	task.wait(Config.Board.LandPause)
end

-- Match -------------------------------------------------------------------------------------------

local function describeRows(rows)
	local list = {}
	for _, row in rows do
		local entry = row.Participant:Describe()
		entry.Placement = row.Placement
		entry.Collectibles = row.Collectibles
		entry.Coins = row.Coins
		table.insert(list, entry)
	end
	return list
end

function BoardGame.play(participants, settings)
	BoardGame.cleanup()
	CoinService.resetAll()
	Inventory.resetBots()

	local data = require(script.Parent.Boards:FindFirstChild(settings.Board or Config.Match.Board))
	local board = BoardLayout.load(data, SpaceTypes)
	current = {
		World = BoardWorld.build(board, SpaceTypes, Config.Board.Origin),
		Stage = "Start",
	}
	current.Match = Match.new(board, participants, { Rounds = settings.Rounds }, {
		Wallet = CoinService,
		Inventory = Inventory,
		Rng = rng,
		Ask = ask,
	})
	local match = current.Match
	for _, seat in match.Seats do
		CoinService.add(seat.Participant, Config.Economy.StartingCoins)
	end
	current.LayoutMessage = layoutMessage(board)
	MinigameManager.broadcast(current.LayoutMessage)

	for round = 1, match.Rounds do
		match.Round = round
		current.Turn = nil
		current.Stage = "Start"
		current.Text = ("Round %d of %d"):format(round, match.Rounds)
		MinigameManager.setPhase(Net.Phase.Board, { Round = round, Rounds = match.Rounds })
		refreshSeats()
		ensureBodies()
		placeAll()
		publish()
		task.wait(1.5)

		for _, seat in match.Order do
			takeTurn(seat)
		end

		current.Turn = nil
		current.Stage = "Minigame"
		current.Text = "Minigame time!"
		publish()
		task.wait(1)
		refreshSeats()
		local ok, err = xpcall(MinigameManager.runRound, debug.traceback, match:participants())
		if not ok then
			warn("[BoardGame] Minigame crashed, carrying on with the board:\n" .. tostring(err))
			MinigameManager.abort("Minigame crashed, back to the board!")
		end
	end

	refreshSeats()
	local rows = match:standings()
	MinigameManager.setPhase(Net.Phase.Standings, {
		Rows = describeRows(rows),
		CollectiblePlural = Config.Collectible.Plural,
		EndsAt = now() + Config.Match.StandingsDuration,
	})
	ensureBodies()
	placeAll()
	task.wait(Config.Match.StandingsDuration)
	BoardGame.cleanup()
	return rows
end

-- Tears the match down and sends everyone back to the lobby. Safe to call any time.
function BoardGame.cleanup()
	local match = current and current.Match
	if current then
		current.World:destroy()
	end
	current = nil
	CoinService.resetAll()
	Inventory.resetBots()
	BotService.setBrain(nil)
	BotService.reviveAll(Arena.lobbySpot)
	if match then
		for index, seat in match.Seats do
			local participant = seat.Participant
			if participant:IsAlive() then
				participant:Teleport(Arena.lobbySpot(index))
				participant:ResetMovement()
			end
		end
	end
end

function BoardGame.isRunning(): boolean
	return current ~= nil
end

function BoardGame.handleInput(player: Player, payload): boolean
	local kind = payload.Kind
	if kind == Net.Input.Roll then
		if current and current.RollWaiting == player then
			current.RollRequested = true
		end
		return true
	elseif kind == Net.Input.Choice then
		local prompt = current and current.Prompt
		local index = payload.Index
		if
			prompt
			and prompt.Player == player
			and payload.PromptId == prompt.Id
			and type(index) == "number"
			and index % 1 == 0
			and index >= 1
			and index <= prompt.Count
		then
			prompt.Answer = index
		end
		return true
	end
	return false
end

-- Late joiners / reloads: send the board and where everyone is.
MinigameManager.onReady(function(player)
	if current and current.LayoutMessage then
		MinigameManager.sendTo(player, current.LayoutMessage)
		if current.StateMessage then
			MinigameManager.sendTo(player, current.StateMessage)
		end
	end
end)

-- A seated player who resets on the board goes straight back to their space.
local function watchCharacter(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		if not current or current.Stage == "Minigame" then
			return
		end
		for _, seat in current.Match.Seats do
			if seat.Participant.Player == player then
				placeSeat(seat)
				publish()
			end
		end
	end)
end
Players.PlayerAdded:Connect(watchCharacter)
for _, player in Players:GetPlayers() do
	watchCharacter(player)
end

Players.PlayerRemoving:Connect(function(player)
	if not current then
		return
	end
	for _, seat in current.Match.Seats do
		if seat.Participant.Player == player then
			seat.Participant.Left = true -- the turn loop hands the seat to a bot
		end
	end
end)

return BoardGame
