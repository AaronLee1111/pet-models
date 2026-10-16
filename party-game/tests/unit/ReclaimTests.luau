--[[
	Unit tests for rejoining players reclaiming their seats: SeatClaims (reservations by
	UserId, queued claims, timing), Match:reclaimSeat (same seat, control handed back) and
	MinigameMode.reclaim. Sunny Loop (Classic) and Magical Festival Island.

	Run (Studio, edit mode is fine):
	  require(game.ServerStorage.PartyTests.ReclaimTests)()
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local CoinService = require(Server.CoinService)
local Inventory = require(Server.Inventory)
local Participant = require(Server.Participant)
local SeatClaims = require(Server.SeatClaims)
local MinigameMode = require(Server.MinigameMode)
local BoardLayout = require(Server.Board.BoardLayout)
local Match = require(Server.Board.Match)
local SpaceTypes = require(Server.Board.SpaceTypes)
local Classic = require(Server.Board.Boards.Classic)
local Festival = require(Server.Board.Boards.MagicalFestival)

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

-- A stand-in for a Player: what Participant, CoinService and SeatClaims read from one.
local IN_GAME = {} -- any non-nil Parent means "still in the game"
local function fakePlayer(userId, name: string?)
	return {
		UserId = userId,
		DisplayName = name or ("P" .. tostring(userId)),
		Parent = IN_GAME,
		FindFirstChild = function()
			return nil
		end,
	}
end

local nextBot = 0
local function fakeBot()
	nextBot += 1
	return { Id = "bot_reclaim" .. nextBot, Name = "Bot" .. nextBot, IsBot = true }
end

-- Seat 1 is a real player (UserId 101), the rest bots.
local function newMatch(data)
	CoinService.resetAll()
	local player = fakePlayer(101, "Ada")
	local participants = { Participant.fromPlayer(player), fakeBot(), fakeBot(), fakeBot() }
	local match = Match.new(BoardLayout.load(data or Classic, SpaceTypes), participants, { Rounds = 5, Difficulty = "Hard" }, {
		Wallet = CoinService,
		Inventory = Inventory,
		Rng = Random.new(11),
		Ask = function(_, request)
			return request.Default
		end,
	})
	return match, match.Seats[1], player
end

-- What must never change when a seat changes hands.
local function snapshot(match, seat)
	return {
		SpaceId = seat.SpaceId,
		Items = table.concat(seat.Items, ","),
		Shield = tostring(seat.Shield),
		Stats = ("%d/%d/%d"):format(seat.Stats.MinigamePoints, seat.Stats.CoinsEarned, seat.Stats.SpacesMoved),
		Order = table.find(match.Order, seat),
		Index = seat.Index,
		Coins = match:coinsOf(seat),
		Crowns = match:collectiblesOf(seat),
	}
end

local function sameSnapshot(a, b)
	for key, value in a do
		eq(b[key], value, key)
	end
end

-- Puts a seat into a lived-in state: moved, items, coins, Crowns, stats, turn order.
local function liveIn(match, seat)
	match.Order = { match.Seats[3], seat, match.Seats[2], match.Seats[4] }
	seat.SpaceId = match.Board.Order[7]
	match:giveItem(seat, "DoubleDice")
	CoinService.add(seat.Participant, 23)
	CoinService.addCollectibles(seat.Participant, 2)
	seat.Stats.MinigamePoints = 5
	seat.Stats.CoinsEarned = 30
	seat.Stats.SpacesMoved = 12
end

-- The leave flow BoardGame runs: mark Left, reserve by UserId, a bot takes the seat.
local function leave(match, claims, seat, player)
	player.Parent = nil
	seat.Participant.Left = true
	claims:cancel(player)
	ok(claims:reserve(seat, player.UserId), "reserve")
	local bot = fakeBot()
	match:replaceParticipant(seat, bot)
	return bot
end

local function rejoin(claims, userId)
	local player = fakePlayer(userId, "Ada")
	local key, code = claims:request(player)
	return player, key, code
end

local function reclaim(match, claims, seat)
	local player = claims:pendingFor(seat)
	if not player then
		return false
	end
	claims:consume(seat)
	return match:reclaimSeat(seat, Participant.fromPlayer(player))
end

local function uniqueIds(match)
	local seen = {}
	for _, participant in match:participants() do
		ok(not seen[participant.Id], "duplicate participant " .. participant.Id)
		seen[participant.Id] = true
	end
	return #match:participants()
end

-- Leave / takeover -------------------------------------------------------------------------------

test("leave: a bot takes over the same seat with everything, seat reserved by UserId", function()
	local match, seat, player = newMatch()
	liveIn(match, seat)
	local before = snapshot(match, seat)
	local claims = SeatClaims.new()
	local bot = leave(match, claims, seat, player)
	eq(seat.Participant, bot, "bot holds the seat")
	sameSnapshot(before, snapshot(match, seat))
	eq(claims:keyFor(101), seat, "reserved for UserId 101")
	eq(claims:reservedFor(seat), 101, "seat knows its owner")
	eq(uniqueIds(match), 4, "still four participants")
end)

-- Rejoin ------------------------------------------------------------------------------------------

test("rejoin: idle board -> taken back immediately, same seat, state intact", function()
	local match, seat, player = newMatch()
	liveIn(match, seat)
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	local before = snapshot(match, seat)
	eq(SeatClaims.timing("Roll", false), "now", "another seat waiting to roll is a safe moment")
	local back, key, code = rejoin(claims, 101)
	eq(code, "queued")
	eq(key, seat)
	local done, previous = reclaim(match, claims, seat)
	ok(done, "reclaimed")
	ok(previous.IsBot, "the bot was replaced")
	eq(seat.Participant.Player, back, "the returning player controls the seat")
	eq(seat.Participant.Id, "player_101", "same id the client knows")
	sameSnapshot(before, snapshot(match, seat))
	eq(uniqueIds(match), 4, "no fifth participant")
	eq(match:seatOf(seat.Participant), seat)
	eq(claims:pendingFor(seat), nil, "claim consumed")
end)

test("rejoin during an active turn or transition is queued, then completes at the boundary", function()
	eq(SeatClaims.timing("Roll", true), "after_turn", "own seat's turn")
	eq(SeatClaims.timing("Moving", true), "after_turn", "own seat moving")
	eq(SeatClaims.timing("Landed", true), "after_turn", "own seat resolving")
	for _, stage in { "Moving", "Deciding", "OrderRoll", "RotationWarning", "Rotating" } do
		eq(SeatClaims.timing(stage, false), "later", stage)
	end
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	-- The bot's turn is in progress: dice and movement resolve for the bot.
	match:beginTurn(seat)
	rejoin(claims, 101)
	local roll = match:rollTurn(seat)
	match:move(seat, roll)
	ok(seat.Participant.IsBot, "bot still plays the turn")
	ok(claims:pendingFor(seat) ~= nil, "claim waits")
	local afterMove = snapshot(match, seat)
	match:endTurn()
	ok(reclaim(match, claims, seat), "reclaimed when the turn ended")
	sameSnapshot(afterMove, snapshot(match, seat))
	ok(not seat.Participant.IsBot, "player back in control")
end)

test("rejoin during a minigame: spectates it, gets the seat after results with the bot's winnings", function()
	eq(SeatClaims.timing("Minigame", false), "after_minigame")
	eq(SeatClaims.timing("Minigame", true), "after_minigame")
	eq(SeatClaims.Messages.after_minigame, "Rejoining your seat after this minigame.")
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	local bot = leave(match, claims, seat, player)
	local roster = match:participants() -- what the minigame was started with
	local back = rejoin(claims, 101)
	for _, participant in roster do
		ok(participant.Player ~= back, "returning player is not in the running minigame")
	end
	-- Results: the bot wins the minigame for the seat.
	CoinService.add(bot, 10)
	match:recordMinigame({ { Participant = bot, Placement = 1 } }, { { Id = bot.Id, Coins = 10 } })
	local afterResults = snapshot(match, seat)
	ok(reclaim(match, claims, seat), "reclaimed after results")
	sameSnapshot(afterResults, snapshot(match, seat))
	eq(seat.Stats.MinigamePoints > 0, true, "minigame points stay with the seat")
end)

test("repeated leave/rejoin cycles keep one seat and the same totals", function()
	local match, seat, player = newMatch()
	liveIn(match, seat)
	local claims = SeatClaims.new()
	local before = snapshot(match, seat)
	for _ = 1, 4 do
		leave(match, claims, seat, player)
		sameSnapshot(before, snapshot(match, seat))
		player = rejoin(claims, 101)
		ok(reclaim(match, claims, seat), "reclaimed")
		sameSnapshot(before, snapshot(match, seat))
		eq(uniqueIds(match), 4, "four participants")
	end
	eq(claims:keyFor(101), seat, "still the same reservation")
end)

test("quick return before a bot took over: same wallet, coins not doubled", function()
	local match, seat, player = newMatch()
	liveIn(match, seat)
	local before = snapshot(match, seat)
	local claims = SeatClaims.new()
	player.Parent = nil
	seat.Participant.Left = true
	claims:reserve(seat, 101)
	rejoin(claims, 101)
	ok(reclaim(match, claims, seat), "reclaimed")
	sameSnapshot(before, snapshot(match, seat))
	eq(match:coinsOf(seat), 23, "coins exactly once")
end)

-- Security ----------------------------------------------------------------------------------------

test("wrong UserId: no reservation, can't take someone else's seat", function()
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	local stranger = fakePlayer(202)
	local key, code = claims:request(stranger)
	eq(key, nil)
	eq(code, "none", "a new late joiner just watches")
	eq(claims:pendingFor(seat), nil)
	-- A player whose UserId doesn't match the reservation is never handed the seat.
	claims.Pending[101] = stranger
	eq(claims:pendingFor(seat), nil, "pending entry for the wrong user is dropped")
	ok(seat.Participant.IsBot, "bot keeps the seat")
	for _, bad in { "101", 0, -5, 1.5, nil } do
		local _, badCode = claims:request({ UserId = bad, Parent = IN_GAME })
		eq(badCode, "bad_user", tostring(bad))
	end
end)

test("two reserved seats: each returning player only gets their own", function()
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	local other = match.Seats[2]
	other.Participant = Participant.fromPlayer(fakePlayer(303, "Bea"))
	leave(match, claims, seat, player)
	leave(match, claims, other, { UserId = 303, Parent = IN_GAME })
	local bea = rejoin(claims, 303)
	eq(claims:pendingFor(seat), nil, "Ada's seat has nobody waiting")
	ok(reclaim(match, claims, other), "Bea back in her seat")
	eq(other.Participant.Player, bea)
	ok(seat.Participant.IsBot, "Ada's seat still bot-held")
	ok(not claims:reserve(seat, 303), "a seat holds one reservation")
	ok(not claims:reserve(match.Seats[3], 101), "a user holds one seat")
end)

test("no duplicate seat or participant, never push out a present player", function()
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	rejoin(claims, 101)
	ok(reclaim(match, claims, seat), "first reclaim")
	-- Seat is owned by a present player now: nothing can take it.
	local again = Participant.fromPlayer(fakePlayer(101))
	local done, why = match:reclaimSeat(seat, again)
	ok(not done, "occupied seat refused")
	eq(why, "occupied")
	-- The same user can't be seated twice through another bot seat.
	done, why = match:reclaimSeat(match.Seats[2], again)
	ok(not done, "second seat refused")
	eq(why, "seated")
	ok(not match:reclaimSeat(match.Seats[2], fakeBot()), "bots never reclaim")
	eq(uniqueIds(match), 4, "four participants")
end)

test("two joins for one UserId: one owner only", function()
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	local first = fakePlayer(101)
	eq(select(2, claims:request(first)), "queued")
	eq(select(2, claims:request(first)), "queued", "same session asking twice is fine")
	local second = fakePlayer(101)
	eq(select(2, claims:request(second)), "duplicate", "second session while first waits")
	first.Parent = nil
	eq(select(2, claims:request(second)), "queued", "first session gone: second may claim")
	ok(reclaim(match, claims, seat), "reclaimed once")
	eq(seat.Participant.Player, second)
end)

test("leaving again while the claim is queued: seat stays with the bot", function()
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	local back = rejoin(claims, 101)
	back.Parent = nil
	claims:cancel(back)
	eq(claims:pendingFor(seat), nil)
	ok(not reclaim(match, claims, seat), "nothing to reclaim")
	ok(seat.Participant.IsBot, "bot keeps playing")
	eq(claims:keyFor(101), seat, "still reserved for a later return")
	-- Gone without cancel (PlayerRemoving not seen yet): the stale entry is ignored.
	local again = rejoin(claims, 101)
	again.Parent = nil
	eq(claims:pendingFor(seat), nil, "stale claim ignored")
end)

-- Rewards and match end --------------------------------------------------------------------------

test("no duplicated rewards: one standings row per seat, Crowns and coins counted once", function()
	local match, seat, player = newMatch()
	liveIn(match, seat)
	local claims = SeatClaims.new()
	local totalCoins, totalCrowns = 0, 0
	for _, s in match.Seats do
		totalCoins += match:coinsOf(s)
		totalCrowns += match:collectiblesOf(s)
	end
	leave(match, claims, seat, player)
	rejoin(claims, 101)
	reclaim(match, claims, seat)
	local rows = match:standings()
	eq(#rows, 4, "four rows")
	local coins, crowns, mine = 0, 0, 0
	for _, row in rows do
		coins += row.Coins
		crowns += row.Collectibles
		if row.Participant.UserId == 101 then
			mine += 1
		end
	end
	eq(coins, totalCoins, "coins conserved")
	eq(crowns, totalCrowns, "Crowns conserved")
	eq(mine, 1, "player paid on exactly one row")
	ok(not rows[1].Participant.Left or rows[1].Participant.IsBot, "rows hold live participants")
end)

test("match ends before the queued reclaim: waiting players told, reservations gone", function()
	local match, seat, player = newMatch()
	local claims = SeatClaims.new()
	leave(match, claims, seat, player)
	local back = rejoin(claims, 101)
	local waiting = claims:clear()
	eq(#waiting, 1)
	eq(waiting[1], back)
	eq(claims:keyFor(101), nil, "reservation cleared")
	eq(claims:reservedFor(seat), nil)
	eq(claims:pendingFor(seat), nil)
	local _, code = claims:request(back)
	eq(code, "none", "after the match they are an ordinary joiner")
	ok(seat.Participant.IsBot, "final seat stays with the bot")
	eq(SeatClaims.Messages.ended, "The match ended before you could rejoin your seat.")
end)

-- Minigames mode ----------------------------------------------------------------------------------

test("Minigames mode: same slot handed back, coins moved, wrong player refused", function()
	CoinService.resetAll()
	local ada = fakePlayer(101, "Ada")
	local participants = { fakeBot(), fakeBot(), fakeBot(), fakeBot() }
	CoinService.add(participants[2], 17)
	local claims = SeatClaims.new()
	claims:reserve(2, 101)
	eq(MinigameMode.reclaim(participants, claims, 2, fakePlayer(404)), nil, "not their seat")
	claims:request(ada)
	local returning, previous = MinigameMode.reclaim(participants, claims, 2, ada)
	ok(returning ~= nil, "reclaimed")
	ok(previous.IsBot, "replaced the bot")
	eq(participants[2], returning, "same slot")
	eq(#participants, 4)
	eq(CoinService.get(returning), 17, "coins moved")
	eq(CoinService.get(previous), 0, "bot's wallet emptied")
	eq(MinigameMode.reclaim(participants, claims, 2, ada), nil, "can't claim twice")
end)

-- Magical Festival Island -------------------------------------------------------------------------

test("festival: reclaim keeps bridge orientation, revision, Crown, Moon Dial and a bridge seat", function()
	local match, seat, player = newMatch(Festival)
	local claims = SeatClaims.new()
	seat.SpaceId = 34 -- standing on the moving bridge
	ok(match:rotateBridge(), "bridge rotated once")
	local function bridge()
		local state = match:bridgeState()
		return ("%s/%s/%s/%s/%s"):format(
			tostring(match.Orientation),
			tostring(match.BridgeRevision),
			tostring(match.CollectibleSpace),
			tostring(state.Alignment),
			tostring(match:canUseMoonDial())
		)
	end
	local before = bridge()
	local seatBefore = snapshot(match, seat)
	leave(match, claims, seat, player)
	eq(bridge(), before, "unchanged by the takeover")
	rejoin(claims, 101)
	ok(reclaim(match, claims, seat), "reclaimed")
	eq(bridge(), before, "unchanged by the reclaim")
	sameSnapshot(seatBefore, snapshot(match, seat))
	eq(seat.SpaceId, 34, "still on the bridge")
	ok(#match:nextOptions(34) > 0, "bridge seat can still move")
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
			warn(("[ReclaimTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	CoinService.resetAll()
	print(("[ReclaimTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
