--[[
	BoardGame
	Runs one board-game match in the world: builds the board, takes turns (roll -> move ->
	space), runs a minigame after every full turn cycle, then shows the final standings.
	The rules themselves live in Match; this module adds timing, networking, bodies and bots.

	  BoardGame.play(participants, settings)   -> final standings rows (yields for the whole match)
	  BoardGame.cleanup()                      safe teardown, also after a crash
	  BoardGame.handleInput(player, payload)   -> true if it was a board input (Roll / Choice)
	  BoardGame.onPlayerLeft(player) / BoardGame.requestReclaim(player)
	                                           leave / rejoin entry points (PlayerRemoving and
	                                           PlayerAdded call them; the reclaim harness too)

	Players who leave are replaced by a bot that keeps their seat, coins and collectibles. The
	seat stays reserved for their UserId; if they rejoin they get it back at a safe moment
	(between turns, after a minigame; see SeatClaims). Players who join mid-match without a
	reserved seat watch until the next match.
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
local SeatClaims = require(script.Parent.Parent.SeatClaims)
local ReadyState = require(script.Parent.Parent.ReadyState)
local Tutorial = require(script.Parent.Parent.Tutorial)
local IntroPlan = require(script.Parent.IntroPlan)
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
			Next = space.Next, -- camera framing at forks
			Landmark = space.Landmark,
		})
	end
	local legend = {}
	for key, spaceType in SpaceTypes do
		table.insert(legend, { Type = key, Name = spaceType.Name, Short = spaceType.Short, Color = spaceType.Color })
	end
	return {
		Type = Net.Message.BoardLayout,
		Name = board.DisplayName,
		Spaces = spaces,
		Legend = legend,
		Festival = board.Bridge ~= nil,
		Presentation = board.Presentation, -- "Diorama": close turn camera + thrown dice
	}
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
			Zone = match.Board:get(seat.SpaceId).Zone,
			Stats = table.clone(seat.Stats),
			-- A bot holding a seat for a player who left: whose seat it is.
			ReservedFor = (function()
				local userId = current.Claims:reservedFor(seat)
				return if userId and participant.IsBot then "player_" .. userId else nil
			end)(),
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
		Bridge = match:bridgeState(),
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
		RollId = current.RollId, -- changes every roll (thrown-dice presentation)
		DiceFaces = current.DiceFaces,
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
	current.World:setFestivalLighting(current.Stage ~= "Minigame")
	current.World:setBridgeState(match:bridgeState())
	current.World:setTraps(match.Traps)
	current.World:setGates(match.Board.Gates, match.GateOpen)
	current.World:setActiveSpace(current.Turn and current.Turn.SpaceId)
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

-- Each seat keeps its own corner on every space: stable, never overlapping (up to four), and
-- an arriving piece walks straight into a free corner without nudging anyone.
local function slotOf(seat): number
	return table.find(current.Match.Seats, seat) or 1
end

local function placeSeat(seat)
	local participant = seat.Participant
	if not participant:IsAlive() then
		return
	end
	local facing = current.Match:nextOptions(seat.SpaceId)[1]
	participant:Teleport(current.World:spaceCFrame(seat.SpaceId, slotOf(seat), facing))
	participant:Freeze()
	-- Anchored on the board: no physics pushing, and clients animate moves locally (BoardMove)
	-- without fighting replication; this snap is the confirmed position.
	local root = participant:GetRoot()
	if root then
		root.Anchored = true
	end
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

-- Board pieces are anchored (placeSeat). Release before any minigame/duel or lobby transition.
local function releasePieces()
	if not current or not current.Match then
		return
	end
	for _, seat in current.Match.Seats do
		local root = seat.Participant:GetRoot()
		if root then
			root.Anchored = false
		end
	end
end

-- One move segment, presented: every client runs the piece along the visible route (BoardMove,
-- client BoardMotion) while the server waits the same time, then snaps it to the confirmed space.
-- Never waits on a client, so a slow or failed animation can't stall the match.
local function moveSeat(seat, fromId: number, step: number)
	local participant = seat.Participant
	local slot = slotOf(seat)
	local facing = current.Match:nextOptions(seat.SpaceId)[1]
	local target = current.World:spaceCFrame(seat.SpaceId, slot, facing)
	if fromId ~= seat.SpaceId and participant:IsAlive() then
		local from = current.World:spaceCFrame(fromId, slot).Position
		local points, stairs = current.World:movePath(from, fromId, seat.SpaceId, target.Position)
		local duration = BoardWorld.moveTime(points, stairs, step, participant.IsBot)
		current.Moving = seat
		MinigameManager.broadcast({
			Type = Net.Message.BoardMove,
			Id = participant.Id,
			Character = participant:GetCharacter(),
			Points = points,
			Face = target.LookVector,
			StartsAt = now(),
			Duration = duration,
		})
		task.wait(duration + Config.Board.StepPause * Config.Board.HopTime / 0.35)
		current.Moving = nil
	end
	placeSeat(seat)
end

local function warnRotation()
 local state=current.Match:bridgeState()
 current.Stage="RotationWarning"
 feed("Moon bridge: " .. state.Alignment .. " → " .. state.NextAlignment .. ". Stay on your space!")
 publish()
 task.wait(current.Match.Board.Bridge.WarningSeconds)
end

local function animateRotation()
 local match=current.Match
 current.Stage="Rotating"
 -- State and connectivity have already committed together; no turns or seam hops
 -- can run until this synchronous presentation finishes.
 publish()
 local startAngle=current.BridgeAngle or 0
 local duration=match.Board.Bridge.RotationSeconds
 local started=now()
 repeat
  local alpha=math.clamp((now()-started)/duration,0,1)
  current.World:setBridgeAngle(startAngle+((if match.Orientation==0 then 0 else -math.pi/2)-startAngle)*(alpha*alpha*(3-2*alpha)))
  for _,seat in match.Seats do
   if seat.SpaceId>=33 then placeSeat(seat) end
  end
  task.wait()
 until now()-started>=duration
 current.BridgeAngle=if match.Orientation==0 then 0 else -math.pi/2
 current.World:setBridgeAngle(current.BridgeAngle)
 placeAll()
 current.LayoutMessage=layoutMessage(match.Board)
 MinigameManager.broadcast(current.LayoutMessage)
 feed("Moon bridge now " .. match:bridgeState().Alignment .. ". Closed zones keep looping.")
end

--[[
	Safe recovery: while the board is up, any piece that has been knocked off its space,
	fallen off the board or lost its body is put back (bots get a new body first). Runs once
	a second; Match positions are the truth, the world just follows them.
]]
local function recoverPieces()
	if not current or current.Stage == "Minigame" or current.Stage == "Finished" or current.Stage == "Rotating" then
		return 0
	end
	local fixed = 0
	for _, seat in current.Match.Seats do
		local participant = seat.Participant
		if seat == current.Moving then
			continue -- mid-segment: the server snaps it when the segment ends
		end
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
		if leaver.UserId and Config.SeatReclaim.Enabled then
			current.Claims:reserve(seat, leaver.UserId)
		end
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

-- Rejoining -----------------------------------------------------------------------------------

local function tellPlayer(player: Player, text: string)
	if player.Parent then
		MinigameManager.sendTo(player, { Type = Net.Message.Toast, Text = text })
	end
end

-- Hands a reserved seat back to its returning player. Callers make sure it's a safe moment.
local function completeReclaim(seat): boolean
	local claims = current.Claims
	local player = claims:pendingFor(seat)
	if not player then
		return false
	end
	claims:consume(seat)
	local previous = seat.Participant
	local returning = Participant.fromPlayer(player)
	local ok = current.Match:reclaimSeat(seat, returning)
	if not ok then
		return false
	end
	if previous.IsBot and previous.Bot then
		BotService.release(previous.Bot) -- the takeover bot is done; lobby-fill bots stay
	elseif previous.Player and previous.Player ~= player then
		-- The earlier session's body, if Roblox hasn't removed it yet.
		local old = previous.Player.Character
		if old and old.Parent then
			old:Destroy()
		end
	end
	if returning:IsAlive() then
		placeSeat(seat)
	end -- otherwise watchCharacter seats the body when it spawns
	feed(("%s is back and takes their seat again"):format(returning.Name))
	tellPlayer(player, SeatClaims.Messages.now)
	publish()
	return true
end

-- Safe boundary (turn finished, minigame over, round start, standings): seat everyone waiting.
-- Runs before refreshSeats, so someone who left and came back within one minigame gets their
-- seat straight back instead of a bot taking it for a moment.
local function settleReclaims()
	if not current then
		return
	end
	for _, seat in current.Match.Seats do
		completeReclaim(seat)
	end
end

-- A player joined: if a seat is reserved for their UserId, queue the claim and take it now
-- if nothing is in progress for that seat.
local function requestReclaim(player: Player)
	if not current or not current.Claims or not Config.SeatReclaim.Enabled then
		return
	end
	local seat = current.Claims:request(player)
	if not seat then
		return
	end
	local timing = SeatClaims.timing(current.Stage, current.Turn == seat)
	if timing == "now" and completeReclaim(seat) then
		return
	end
	tellPlayer(player, SeatClaims.Messages[timing] or SeatClaims.Messages.later)
end
BoardGame.requestReclaim = requestReclaim

-- Choices -----------------------------------------------------------------------------------------

-- What a fork's buttons lead to, for the client's first-fork guidance: the first space of
-- each route and its distance to the Crown (nil when it can't be reached).
local function describeRoutes(request)
	local data = request.Kind == "Path" and request.Data
	if not data or not data.Spaces then
		return nil
	end
	local routes = {}
	for i, spaceId in data.Spaces do
		local info = data.Info and data.Info[i]
		local distance = info and info.CrownDistance
		table.insert(routes, {
			SpaceId = spaceId,
			CrownDistance = if distance and distance ~= math.huge then distance else nil,
			Toll = info and info.Toll or 0,
		})
	end
	return routes
end

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
			Kind = request.Kind,
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
			Kind = request.Kind, -- "Path" | "Collectible" | "Shop" | ... (guidance only)
			Routes = describeRoutes(request),
			Price = request.Price,
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
	releasePieces()
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
--[[
	Board-opening introduction: once per match, after the board is built and before turn order.
	The server owns the schedule (seat order, who arrives when, where they stand, when it ends);
	clients only run the cameras and the arrivals (BoardIntro). Pieces are already standing on
	Start here, so a client that misses it simply sees them there. Nobody can roll or move until
	it ends; humans may speed up the group shot once everyone has appeared (Input.IntroSkip).
]]
local function runIntro()
	local match = current.Match
	current.IntroPlayed = true
	current.Stage = "Intro"
	current.Text = match.Board.DisplayName or ""
	ensureBodies()
	placeAll()
	local spec = current.World:introSpec()
	local plan = IntroPlan.schedule(#match.Seats, spec ~= nil, spec and spec.Times, now() + Config.Board.Intro.Lead)
	local seats, humans = {}, {}
	for index, seat in match.Seats do
		local participant = seat.Participant
		table.insert(seats, {
			Id = participant.Id,
			Name = participant.Name,
			IsBot = participant.IsBot,
			Character = participant:GetCharacter(),
			ArriveAt = plan.ArriveAt[index],
			Destination = current.World:spaceCFrame(seat.SpaceId, slotOf(seat), match:nextOptions(seat.SpaceId)[1]),
		})
		if not participant.IsBot and not isAway(participant) then
			table.insert(humans, participant)
		end
	end
	current.Skips = ReadyState.new(humans, plan.GroupAt, "Intro")
	current.IntroMessage = {
		Type = Net.Message.BoardIntro,
		BoardName = match.Board.DisplayName,
		Spec = spec,
		Seats = seats,
		StartsAt = plan.ArriveAt[1] and (plan.ArriveAt[1] - (if spec then plan.Times.Establish else 0)) or now(),
		GroupAt = plan.GroupAt,
		EndsAt = plan.EndsAt,
		Out = plan.Times.Out,
	}
	print(("[BoardIntro] start: %d seats, %s, %.1fs"):format(#seats, if spec then spec.Effect else "no intro data", plan.EndsAt - now()))
	MinigameManager.broadcast(current.IntroMessage)
	publish()
	while now() < plan.EndsAt do
		if now() >= plan.GroupAt and #humans > 0 and current.Skips:everyone() then
			break -- everyone asked to move on
		end
		task.wait(0.05)
	end
	current.IntroMessage = nil
	current.Skips = nil
	MinigameManager.broadcast({ Type = Net.Message.BoardIntro, Done = true })
	placeAll() -- whatever any client showed, everyone stands on Start
	print("[BoardIntro] done")
end

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
		task.wait(2.4) -- every seat's die is thrown and lands on the client (BoardView order dice)
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
	local previousStage=current.Stage
 local revision=match.BridgeRevision
 if id=="MoonDial" and match:canUseMoonDial() and match.Turn and match.Turn.Seat==seat
  and match.Turn.Stage=="PreRoll" and not match.Turn.ItemUsed then warnRotation() end
 local used, text = match:useItem(seat, slot, target, choice)
 if match.BridgeRevision~=revision then animateRotation() end
 current.Stage=previousStage
	if used then
		Tutorial.complete(seat.Participant, "SawItem")
		feed(text)
		placeAll() -- swaps and warps move pieces
	elseif seat.Participant.Player and seat.Participant.Player.Parent then
		MinigameManager.sendTo(seat.Participant.Player, { Type = Net.Message.Toast, Text = "Can't use that: " .. text })
	end
	publish()
	return used
end

local function takeTurn(seat)
	settleReclaims() -- the previous turn is over
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
	current.RollId = (current.RollId or 0) + 1
	current.DiceFaces = dice
	current.Remaining = roll
	current.RollEndsAt = nil
	current.Text = if #dice > 1
		then ("%s rolled %s = %d"):format(seat.Participant.Name, table.concat(dice, " + "), roll)
		else ("%s rolled a %d"):format(seat.Participant.Name, roll)
	publish()
	-- Every board throws a physical die: give it time to fly and land before the first hop;
	-- bots get the short version.
	task.wait(if participant.IsBot then Config.Board.DiceRevealBot else Config.Board.DiceReveal)

	local fromId, step = seat.SpaceId, 0
	local landing = match:move(seat, roll, function(movedSeat, _, remaining)
		step += 1
		moveSeat(movedSeat, fromId, step)
		fromId = movedSeat.SpaceId
		current.Remaining = remaining -- counts down as each space is reached
		publish()
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
		Claims = SeatClaims.new(),
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
		settleReclaims()
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
			if not current.IntroPlayed then
				runIntro()
			end
			rollForTurnOrder()
		end

		for _, seat in match.Order do
			takeTurn(seat)
		end

		current.Turn = nil
		settleReclaims() -- the last turn of the round is over
		refreshSeats()
  if match:rotationDue() then
   warnRotation()
   if match:finishBoardRound() then animateRotation() end
  end
		current.Stage = "Minigame"
		current.Text = "Minigame time!"
		publish()
		task.wait(1)
		refreshSeats()
		releasePieces()
		local ok, results, rows = xpcall(MinigameManager.runRound, debug.traceback, match:participants())
		if ok then
			match:recordMinigame(results, rows)
		else
			warn("[BoardGame] Minigame crashed, carrying on with the board:\n" .. tostring(results))
			MinigameManager.abort("Minigame crashed, back to the board!")
		end
		-- Results are in: players who came back during the minigame get their seats now,
		-- before the next board turn.
		current.Stage = "Start"
		settleReclaims()
		refreshSeats()
	end

	-- Standings before bonuses -> bonus awards -> final standings.
	current.Stage = "Standings"
	settleReclaims()
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

	-- Last chance for anyone who came back during the standings; then the seats are final.
	settleReclaims()
	refreshSeats()
	local claims = current.Claims
	current.Claims = SeatClaims.new() -- reservations end with the match
	for _, player in claims:clear() do
		tellPlayer(player, SeatClaims.Messages.ended)
	end
	-- Permanent bank coins for real players (the only thing a match writes to a profile).
	-- One row per seat, paid once, so a rejoin can't be paid twice.
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
	releasePieces()
	if current then
		current.World:destroy()
		for _, player in current.Claims:clear() do
			tellPlayer(player, SeatClaims.Messages.ended)
		end
	end
	current = nil
	BoardWorld.clearStale()
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
			Tutorial.complete(player, "RolledBoardTurn")
			-- Rolled while holding an item they could have used: they've seen the item choice.
			local turn = current.Match.Turn
			if current.Turn and #current.Turn.Items > 0 and turn and not turn.ItemUsed then
				Tutorial.complete(player, "SawItem")
			end
		elseif current and current.OrderWaiting and current.OrderWaiting[player] == false then
			current.OrderWaiting[player] = true
			Tutorial.complete(player, "RolledForOrder")
		end
		return true
	elseif kind == Net.Input.IntroSkip then
		-- Yourself only; ReadyState checks the stage and that everyone has appeared.
		local skips = current and current.Skips
		if skips then
			for _, participant in skips.Participants do
				if participant.Player == player then
					skips:mark(participant, current.Stage, now())
				end
			end
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
			if prompt.Kind == "Path" then
				Tutorial.complete(player, "ChoseFork")
			elseif prompt.Kind == "Collectible" then
				Tutorial.complete(player, "SawCrownPurchase")
			end
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
			MinigameManager.sendTo(player, stateMessage())
		end
		-- Joined during the board intro: the same schedule, picked up where it is now (never restarted).
		if current.IntroMessage then
			MinigameManager.sendTo(player, current.IntroMessage)
		end
		-- Still waiting for their seat (the queued message may have arrived before the
		-- client was listening): say so again.
		local seat = current.Claims:keyFor(player.UserId)
		if seat and current.Claims:pendingFor(seat) == player then
			local timing = SeatClaims.timing(current.Stage, current.Turn == seat)
			tellPlayer(player, SeatClaims.Messages[if timing == "now" then "later" else timing])
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
Players.PlayerAdded:Connect(function(player)
	watchCharacter(player)
	requestReclaim(player)
end)
for _, player in Players:GetPlayers() do
	watchCharacter(player)
end

-- A player left: their seat goes to a bot at the next turn and stays reserved for them.
-- PlayerRemoving calls this; the multi-client harness calls it to simulate a leave.
function BoardGame.onPlayerLeft(player: Player)
	if not current then
		return
	end
	current.Claims:cancel(player) -- left again while waiting for their seat
	for _, seat in current.Match.Seats do
		if seat.Participant.Player == player then
			seat.Participant.Left = true -- the turn loop hands the seat to a bot
			if Config.SeatReclaim.Enabled then
				current.Claims:reserve(seat, player.UserId)
			end
		end
	end
end
Players.PlayerRemoving:Connect(BoardGame.onPlayerLeft)

return BoardGame
