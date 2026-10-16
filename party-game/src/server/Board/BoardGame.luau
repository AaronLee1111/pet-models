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
local CosmeticService = require(script.Parent.Parent.CosmeticService)
local Inventory = require(script.Parent.Parent.Inventory)
local MinigameManager = require(script.Parent.Parent.MinigameManager)
local Participant = require(script.Parent.Parent.Participant)
local Profiles = require(script.Parent.Parent.Profiles)
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
	return { Type = Net.Message.BoardLayout, Name = board.DisplayName, Spaces = spaces, Legend = legend }
end

local function describeItems(seat)
	local list = {}
	for _, id in seat.Items do
		local item = Match.getItem(id)
		table.insert(list, { Id = id, Name = item.Name, Description = item.Description })
	end
	return list
end

local function stateMessage()
	local match = current.Match
	local seats = {}
	for orderIndex, seat in match.Order do
		local participant = seat.Participant
		table.insert(seats, {
			Items = describeItems(seat),
			Shield = seat.Shield,
			Underdog = match:isUnderdog(seat),
			OrderRolls = current.OrderRolls and current.OrderRolls[seat],
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
	local pending = {}
	for player, pressed in current.OrderWaiting or {} do
		if not pressed then
			pending["player_" .. player.UserId] = true
		end
	end
	return {
		OrderPending = pending,
		Dice = match.Turn and match.Turn.Dice,
		ItemUsed = match.Turn and match.Turn.ItemUsed,
		MaxItems = Config.Items.MaxHeld,
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
		CollectiblePrice = match.CollectiblePrice,
		Frenzy = match:isFrenzy(),
		Gates = (function()
			local gates = {}
			for _, gate in match.Board.Gates or {} do
				table.insert(gates, { Id = gate.Id, Open = match.GateOpen[gate.Id], Toll = gate.Toll or 0, From = gate.From, To = gate.To })
			end
			return gates
		end)(),
		Traps = (function()
			local traps = {}
			for id, trap in match.Traps do
				table.insert(traps, { SpaceId = id, Owner = trap.Owner.Participant.Name })
			end
			return traps
		end)(),
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
		("%s · %d coins"):format(Config.Collectible.Name, match.CollectiblePrice)
	)
	current.World:setTraps(match.Traps)
	current.World:setGates(match.Board.Gates, match.GateOpen)
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

--[[
	Safe recovery: while the board is up, any piece that has been knocked off its space,
	fallen off the board or lost its body is put back (bots get a new body first). Runs once
	a second; Match positions are the truth, the world just follows them.
]]
local function recoverPieces()
	if not current or current.Stage == "Minigame" or current.Stage == "Finished" then
		return 0
	end
	local fixed = 0
	for _, seat in current.Match.Seats do
		local participant = seat.Participant
		if participant.IsBot and not participant:IsAlive() then
			BotService.reviveAll(Arena.lobbySpot)
		end
		local root = participant:GetRoot()
		if participant:IsAlive() and root and current.World:isMisplaced(root.Position, seat.SpaceId) then
			placeSeat(seat)
			fixed += 1
		end
	end
	return fixed
end
BoardGame.recoverPieces = recoverPieces

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

-- Duel space: play a Duel minigame between the two seats, then bring everyone back to the board.
-- Returns winner seat (nil = draw) and whether a duel was played at all.
local function playDuel(seatA, seatB)
	if #MinigameManager.duelMinigames() == 0 then
		return nil, false
	end
	local match = current.Match
	local previousStage = current.Stage
	current.Stage = "Minigame"
	publish()
	task.wait(1)
	local ok, winner = xpcall(MinigameManager.runDuel, debug.traceback, seatA.Participant, seatB.Participant)
	if not ok then
		warn("[BoardGame] Duel crashed, using dice instead:\n" .. tostring(winner))
		MinigameManager.abort("Duel crashed, rolling dice instead")
	end
	MinigameManager.setPhase(Net.Phase.Board, { Round = match.Round, Rounds = match.Rounds })
	current.Stage = previousStage
	ensureBodies()
	placeAll()
	publish()
	if not ok then
		return nil, false
	end
	return if winner then match:seatOf(winner) else nil, true
end

-- Turns -------------------------------------------------------------------------------------------

-- Turn order: everyone rolls once before round 1; ties roll again among themselves.
local function rollForTurnOrder()
	local match = current.Match
	current.Stage = "OrderRoll"
	current.OrderRolls = {}
	current.Text = "Everyone rolls for turn order!"

	local function rollFor(seats, attempt)
		current.OrderWaiting = {}
		for _, seat in seats do
			local participant = seat.Participant
			if not participant.IsBot and not isAway(participant) then
				current.OrderWaiting[participant.Player] = false
			end
		end
		current.RollEndsAt = now() + Config.Match.OrderRollTimeout
		if attempt > 1 then
			current.Text = "Tie! Tied players roll again"
		end
		publish()
		task.wait(1) -- bots "roll" after a beat
		while now() < current.RollEndsAt do
			local waiting = false
			for player, pressed in current.OrderWaiting do
				if not pressed and player.Parent then
					waiting = true
				end
			end
			if not waiting then
				break
			end
			task.wait(0.05)
		end
		current.OrderWaiting = nil
		current.RollEndsAt = nil
		local rolls = {}
		for _, seat in seats do
			rolls[seat] = match:roll()
			current.OrderRolls[seat] = current.OrderRolls[seat] or {}
			table.insert(current.OrderRolls[seat], rolls[seat])
		end
		publish()
		task.wait(1.5)
		return rolls
	end

	local order = match:decideTurnOrder(rollFor)
	local names = {}
	for index, seat in order do
		table.insert(names, ("%d. %s"):format(index, seat.Participant.Name))
	end
	current.Stage = "OrderDone"
	feed("Turn order: " .. table.concat(names, "   "))
	publish()
	task.wait(2.5)
	current.OrderRolls = nil
end

-- Uses an item for the seat whose turn it is. Players pick a target / number here; bots pass
-- theirs in. Match:useItem does all the validation for both.
local function useItem(seat, slot, target, choice)
	local match = current.Match
	local id = type(slot) == "number" and seat.Items[slot]
	local item = id and Match.getItem(id)
	if item and item.Target == "Opponent" and target == nil then
		local opponents = match:opponentsOf(seat)
		local labels = {}
		for i, other in opponents do
			labels[i] = other.Participant.Name
		end
		table.insert(labels, "Cancel")
		local pick = ask(seat, {
			Kind = "Target",
			Prompt = ("%s: pick an opponent"):format(item.Name),
			Options = labels,
			Default = #labels,
			Data = { Seats = opponents },
		})
		target = opponents[pick]
		if not target then
			return false
		end
	end
	if item and item.Choice == "DieFace" and choice == nil then
		local labels = {}
		for face = 1, Config.Board.DieSides do
			labels[face] = tostring(face)
		end
		table.insert(labels, "Cancel")
		choice = ask(seat, {
			Kind = "DieFace",
			Prompt = ("%s: pick your roll"):format(item.Name),
			Options = labels,
			Default = #labels,
		})
		if choice > Config.Board.DieSides then
			return false
		end
	end
	local used, text = match:useItem(seat, slot, target, choice)
	if used then
		feed(text)
		placeAll() -- swaps and warps move pieces
	elseif seat.Participant.Player and seat.Participant.Player.Parent then
		MinigameManager.sendTo(seat.Participant.Player, { Type = Net.Message.Toast, Text = "Can't use that: " .. text })
	end
	publish()
	return used
end

local function takeTurn(seat)
	refreshSeats()
	local match = current.Match
	local participant = seat.Participant
	match:beginTurn(seat)
	current.Turn = seat
	current.Stage = "Roll"
	current.Roll = nil
	current.Remaining = nil
	current.RollEndsAt = now() + Config.Board.RollTimeout
	current.Text = ("%s's turn"):format(participant.Name)
	current.RollRequested = false
	current.ItemRequest = nil
	publish()

	if participant.IsBot or isAway(participant) then
		waitRandom(Config.Board.BotRollDelay)
		local slot, target, choice = match:botItemChoice(seat)
		if slot and useItem(seat, slot, target, choice) then
			task.wait(1)
		end
	else
		current.RollWaiting = participant.Player
		while not current.RollRequested and now() < current.RollEndsAt and not isAway(participant) do
			local request = current.ItemRequest
			if request then
				current.ItemRequest = nil
				if useItem(seat, request.Slot) then
					current.RollEndsAt = math.max(current.RollEndsAt, now() + 5)
					publish()
				end
			end
			task.wait(0.05)
		end
		current.RollWaiting = nil
	end

	local roll, dice = match:rollTurn(seat)
	current.Stage = "Moving"
	current.Roll = roll
	current.Remaining = roll
	current.RollEndsAt = nil
	current.Text = if #dice > 1
		then ("%s rolled %s = %d"):format(seat.Participant.Name, table.concat(dice, " + "), roll)
		else ("%s rolled a %d"):format(seat.Participant.Name, roll)
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
	match:endTurn()
	publish()
	task.wait(Config.Board.LandPause)
end

-- Match -------------------------------------------------------------------------------------------

local function describeBonuses(awarded)
	local list = {}
	for _, entry in awarded do
		local winners = {}
		for _, seat in entry.Winners do
			table.insert(winners, { Id = seat.Participant.Id, Name = seat.Participant.Name })
		end
		table.insert(list, {
			Name = entry.Bonus.Name,
			Description = entry.Bonus.Description,
			Crowns = entry.Bonus.Crowns or 1,
			Value = entry.Value,
			Winners = winners,
		})
	end
	return list
end

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
	current.Match = Match.new(board, participants, { Rounds = settings.Rounds, Difficulty = settings.Difficulty }, {
		Wallet = CoinService,
		Inventory = Inventory,
		Rng = rng,
		Ask = ask,
		Duel = playDuel,
	})
	local match = current.Match
	for _, seat in match.Seats do
		CoinService.add(seat.Participant, Config.Economy.StartingCoins)
		for _, itemId in Config.Items.StartingItems do
			match:giveItem(seat, itemId)
		end
	end
	current.LayoutMessage = layoutMessage(board)
	local watched = current
	task.spawn(function()
		while current == watched do
			pcall(recoverPieces)
			task.wait(1)
		end
	end)
	MinigameManager.broadcast(current.LayoutMessage)

	for round = 1, match.Rounds do
		local catchUp = match:startRound(round)
		current.Turn = nil
		current.Stage = "Start"
		current.Text = ("Round %d of %d"):format(round, match.Rounds)
			.. (if match:isFrenzy() then "  ·  FINAL FRENZY: coin spaces x2" else "")
		MinigameManager.setPhase(Net.Phase.Board, { Round = round, Rounds = match.Rounds })
		refreshSeats()
		ensureBodies()
		placeAll()
		publish()
		task.wait(1.5)
		if catchUp then
			feed(catchUp)
			publish()
			task.wait(1.5)
		end
		if round == 1 then
			rollForTurnOrder()
		end

		for _, seat in match.Order do
			takeTurn(seat)
		end

		current.Turn = nil
		current.Stage = "Minigame"
		current.Text = "Minigame time!"
		publish()
		task.wait(1)
		refreshSeats()
		local ok, results, rows = xpcall(MinigameManager.runRound, debug.traceback, match:participants())
		if ok then
			match:recordMinigame(results, rows)
		else
			warn("[BoardGame] Minigame crashed, carrying on with the board:\n" .. tostring(results))
			MinigameManager.abort("Minigame crashed, back to the board!")
		end
	end

	-- Standings before bonuses -> bonus awards -> final standings.
	refreshSeats()
	MinigameManager.setPhase(Net.Phase.Standings, {
		Stage = "Before",
		Rows = describeRows(match:standings()),
		CollectiblePlural = Config.Collectible.Plural,
		EndsAt = now() + Config.Match.PreBonusDuration,
	})
	ensureBodies()
	placeAll()
	task.wait(Config.Match.PreBonusDuration)

	local awarded = match:awardBonuses()
	MinigameManager.setPhase(Net.Phase.Standings, {
		Stage = "Bonus",
		Bonuses = describeBonuses(awarded),
		CollectiblePlural = Config.Collectible.Plural,
		EndsAt = now() + Config.Match.BonusDuration,
	})
	task.wait(Config.Match.BonusDuration)

	-- Permanent bank coins for real players (the only thing a match writes to a profile).
	local rows = match:standings()
	local described = describeRows(rows)
	for index, row in rows do
		local player = row.Participant.Player
		local amount = Config.Profile.BankCoinsByPlacement[row.Placement] or 0
		if player and player.Parent and not row.Participant.Left and amount > 0 then
			Profiles.addBankCoins(player, amount)
			described[index].BankCoins = amount
			CosmeticService.sendInventory(player)
		end
	end
	MinigameManager.setPhase(Net.Phase.Standings, {
		Stage = "Final",
		Rows = described,
		CollectiblePlural = Config.Collectible.Plural,
		EndsAt = now() + Config.Match.StandingsDuration,
	})
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
		elseif current and current.OrderWaiting and current.OrderWaiting[player] == false then
			current.OrderWaiting[player] = true
		end
		return true
	elseif kind == Net.Input.UseItem then
		-- Only queued here; takeTurn hands it to Match:useItem, which checks everything.
		if current and current.RollWaiting == player and not current.ItemRequest then
			current.ItemRequest = { Slot = payload.Slot }
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
