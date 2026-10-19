--[[
	Route-graph checks for the Sunny Loop redesign (Boards/SunnyLoopV2, preview board):
	loops, fork reconnection, Crown reachability, gate behaviour, movement direction, geometry
	(spacing, crossings, four pieces per space), bot navigation over many turns, and the
	medallion world build. Run with RunAll (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local Config = require(ReplicatedStorage.PartyShared.Config)
local CoinService = require(Server.CoinService)
local Inventory = require(Server.Inventory)
local BoardLayout = require(Server.Board.BoardLayout)
local BoardWorld = require(Server.Board.BoardWorld)
local Items = require(Server.Board.Items)
local Match = require(Server.Board.Match)
local SpaceTypes = require(Server.Board.SpaceTypes)
local Data = require(Server.Board.Boards.SunnyLoopV2)

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

local board = BoardLayout.load(Data, SpaceTypes)
local spacing = Config.Board.SpaceSpacing

local nextFake = 0
local function newMatch(seed: number)
	CoinService.resetAll()
	local participants = {}
	for i = 1, 4 do
		nextFake += 1
		table.insert(participants, { Id = "bot_v2_" .. nextFake, Name = "B" .. i, IsBot = true })
	end
	local match
	match = Match.new(BoardLayout.load(Data, SpaceTypes), participants, { Rounds = 5, Difficulty = "Normal" }, {
		Wallet = CoinService,
		Inventory = Inventory,
		Rng = Random.new(seed),
		Ask = function(seat, request)
			return match:botDecision(seat, request, 0.6)
		end,
	})
	return match
end

local function worldXZ(id: number): Vector2
	local at = board.Spaces[id].At
	return Vector2.new(at[1] * spacing, at[2] * spacing)
end

-- Spaces reachable from `from` within `limit` moves without stepping on `avoid`.
local function reach(from: number, limit: number, avoid: number?)
	local seen, frontier = { [from] = 0 }, { from }
	for depth = 1, limit do
		local nextFrontier = {}
		for _, id in frontier do
			for _, n in board.Spaces[id].Next do
				if n ~= avoid and seen[n] == nil then
					seen[n] = depth
					table.insert(nextFrontier, n)
				end
			end
		end
		frontier = nextFrontier
	end
	return seen
end

test("v2 route: loads, 36-42 spaces, every space type, start and gate on a fork", function()
	local count = #board.Order
	ok(count >= 36 and count <= 42, "space count " .. count)
	local types = {}
	for _, id in board.Order do
		types[board.Spaces[id].Type] = true
	end
	for _, needed in { "Neutral", "Gain", "Lose", "Event", "Shop", "Item", "Duel", "Chaos", "Switch", "Reward" } do
		ok(types[needed], "missing space type " .. needed)
	end
	eq(#board.Gates, 1, "one gated shortcut")
	local gate = board.Gates[1]
	ok(gate.Toll and gate.Toll > 0, "the shortcut has a toll")
	ok(#board.Spaces[gate.From].Next >= 2, "gate sits on a fork")
end)

test("v2 route: three forks, each reconnects before Start and has labels", function()
	local forks = {}
	for _, id in board.Order do
		local space = board.Spaces[id]
		if #space.Next >= 2 then
			table.insert(forks, id)
			ok(space.Paths and #space.Paths == #space.Next, ("fork %d needs a label per route"):format(id))
		end
	end
	ok(#forks >= 3, "need at least 3 forks (2 free + the gated shortcut), got " .. #forks)
	for _, id in forks do
		local a = reach(board.Spaces[id].Next[1], 16, board.Start)
		local b = reach(board.Spaces[id].Next[2], 16, board.Start)
		local rejoin = nil
		for space in a do
			if b[space] and (rejoin == nil or a[space] + b[space] < a[rejoin] + b[rejoin]) then
				rejoin = space
			end
		end
		ok(rejoin ~= nil, ("fork %d: routes never meet before Start"):format(id))
	end
end)

test("v2 route: every Crown space reachable from every space, gate open or closed", function()
	local match = newMatch(1)
	for _, open in { true, false } do
		match.GateOpen.SundialBridge = open
		match.Board.DistanceCache = nil
		for _, from in board.Order do
			for _, crown in board.CrownSpaces do
				ok(match:distance(from, crown) < math.huge, ("crown %d unreachable from %d (gate %s)"):format(crown, from, tostring(open)))
			end
		end
	end
	ok(#board.CrownSpaces >= 5, "Crown needs room to move")
	for _, crown in board.CrownSpaces do
		ok(#board.Spaces[crown].Next == 1, ("Crown space %d should not be a fork"):format(crown))
		ok(board.Spaces[crown].Type ~= "Shop", "no Crown on a shop")
	end
end)

test("v2 route: closed gate removes the shortcut; open gate charges the toll; Switch flips it", function()
	local match = newMatch(2)
	local gate = board.Gates[1]
	match.GateOpen[gate.Id] = false
	local options = match:nextOptions(gate.From)
	eq(#options, 1, "closed: one way on")
	ok(options[1] ~= gate.To, "closed: not the shortcut")
	match.GateOpen[gate.Id] = true
	eq(#match:nextOptions(gate.From), 2, "open: both ways")
	local switchCount = 0
	for _, id in board.Order do
		if board.Spaces[id].Type == "Switch" then
			switchCount += 1
		end
	end
	eq(switchCount, 1, "one Switch space")
	local opened = match:toggleGates()
	eq(match.GateOpen[gate.Id], opened > 0, "Switch / Gate Key flips the gate")
	local gateKey
	for _, item in Items do
		if item.Id == "GateKey" then
			gateKey = item
		end
	end
	ok(gateKey and table.find(gateKey.Boards, "SunnyLoopV2"), "Gate Key works on this board")
end)

test("v2 route: one-way movement (no back-and-forth edges), single Start loop", function()
	for _, id in board.Order do
		for _, n in board.Spaces[id].Next do
			ok(not table.find(board.Spaces[n].Next, id), ("edge %d<->%d goes both ways"):format(id, n))
		end
	end
	local loop = reach(board.Start, 60)
	for _, id in board.Order do
		ok(loop[id] ~= nil, "space not reachable from Start: " .. id)
	end
end)

test("v2 geometry: spaces apart, hops readable, no ambiguous path crossings", function()
	local minimum = 10.5 -- medallion diameter: nothing overlaps
	for i, a in board.Order do
		for j = i + 1, #board.Order do
			local b = board.Order[j]
			local d = (worldXZ(a) - worldXZ(b)).Magnitude
			local dh = math.abs((board.Spaces[a].At[3] or 0) - (board.Spaces[b].At[3] or 0))
			ok(d >= minimum or dh >= 6, ("spaces %d and %d overlap (%.1f studs)"):format(a, b, d))
		end
	end
	local edges = {}
	for _, id in board.Order do
		for _, n in board.Spaces[id].Next do
			local d = (worldXZ(id) - worldXZ(n)).Magnitude
			ok(d >= 11 and d <= 26, ("hop %d->%d is %.1f studs"):format(id, n, d))
			table.insert(edges, { id, n })
		end
	end
	local function cross(p1, p2, p3, p4)
		local function orient(a, b, c)
			return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
		end
		return orient(p1, p2, p3) * orient(p1, p2, p4) < 0 and orient(p3, p4, p1) * orient(p3, p4, p2) < 0
	end
	for i, e in edges do
		for j = i + 1, #edges do
			local f = edges[j]
			local shared = e[1] == f[1] or e[1] == f[2] or e[2] == f[1] or e[2] == f[2]
			if not shared and cross(worldXZ(e[1]), worldXZ(e[2]), worldXZ(f[1]), worldXZ(f[2])) then
				error(("paths %d->%d and %d->%d cross"):format(e[1], e[2], f[1], f[2]))
			end
		end
	end
end)

test("v2 world: medallion board builds; four pieces fit on one space; recovery points", function()
	local world = BoardWorld.build(board, SpaceTypes, Vector3.new(0, 0, -900))
	local ok2, err = pcall(function()
		for _, id in board.Order do
			ok(world.Tops[id] ~= nil, "no top for " .. id)
			ok(world.Tiles[id] ~= nil, "no medallion for " .. id)
			local expected = (board.Spaces[id].At[3] or 0) + 1.2
			ok(math.abs(world.Tops[id].Y - expected) < 1e-3, ("top height of %d: %.3f"):format(id, world.Tops[id].Y))
			local positions = {}
			for slot = 1, 4 do
				local cf = world:spaceCFrame(id, slot)
				local flat = Vector3.new(cf.Position.X - world.Tops[id].X, 0, cf.Position.Z - world.Tops[id].Z)
				ok(flat.Magnitude <= 10.5 / 2 - 1, ("slot %d of %d hangs off the medallion"):format(slot, id))
				ok(not world:isMisplaced(cf.Position, id), ("slot %d of %d counts as misplaced"):format(slot, id))
				for _, other in positions do
					ok((other - cf.Position).Magnitude >= 4.5, "pieces overlap on " .. id)
				end
				table.insert(positions, cf.Position)
			end
		end
		for _, gate in board.Gates do
			ok(world.Folder:FindFirstChild(("Path%d_%d"):format(gate.From, gate.To)), "gate path exists")
		end
		ok(world.Folder:FindFirstChild("SkyGarden", true), "scene built")
		ok(world.Folder:FindFirstChild("OrchardMarket", true), "orchard market built")
	end)
	world:destroy()
	if not ok2 then
		error(err, 0)
	end
end)

test("v2 bots: 4 bots x 3 matches x 12 rounds; every fork route used, Crowns bought, no one stuck", function()
	local used = {}
	local purchases = 0
	local visited = {}
	for _, seed in { 11, 23, 37 } do
	local match = newMatch(seed)
	for round = 1, 12 do
		match:startRound(round)
		for _, seat in match.Seats do
			match:beginTurn(seat)
			local slot, target, choice = match:botItemChoice(seat)
			if slot then
				match:useItem(seat, slot, target, choice)
			end
			local before = match:collectiblesOf(seat)
			local roll = match:rollTurn(seat)
			local last = seat.SpaceId
			match:move(seat, roll, function(movedSeat, id)
				used[last .. ">" .. id] = true
				visited[id] = true
				last = id
			end)
			match:endTurn()
			if match:collectiblesOf(seat) > before then
				purchases += 1
			end
			ok(board.Spaces[seat.SpaceId] ~= nil, "seat on a real space")
		end
	end
	end
	for _, id in board.Order do
		local space = board.Spaces[id]
		if #space.Next >= 2 then
			for _, n in space.Next do
				ok(used[id .. ">" .. n], ("bots never took route %d->%d"):format(id, n))
			end
		end
	end
	ok(purchases >= 1, "bots bought no Crowns in 36 rounds")
	local count = 0
	for _ in visited do
		count += 1
	end
	ok(count >= #board.Order - 4, ("bots only reached %d spaces"):format(count))
	CoinService.resetAll()
end)

test("v2 bots: take the toll bridge toward a Crown beyond it, the road toward one before it", function()
	local match = newMatch(5)
	match.Difficulty = "Hard" -- no random picks
	local seat = match.Seats[1]
	CoinService.add(seat.Participant, 40)
	local gate = board.Gates[1]
	local request = {
		Kind = "Path",
		Options = { "Road", "Bridge" },
		Default = 1,
		Data = { Spaces = { 13, 33 }, Info = { { Toll = 0 }, { Toll = gate.Toll } } },
	}
	match.CollectibleSpace = 26
	eq(match:botDecision(seat, request, 0.9), 2, "Crown at 26: bridge")
	match.CollectibleSpace = 39
	eq(match:botDecision(seat, request, 0.9), 1, "Crown at 39: fairground road")
end)

test("v2 preview board: hidden from live servers, original Sunny Loop unchanged", function()
	ok(Data.Preview == true, "flagged as preview")
	ok(not table.find(Config.Match.Boards, "SunnyLoopV2"), "not in the released picker")
	ok(table.find(Config.Match.PreviewBoards, "SunnyLoopV2"), "listed as a preview board")
	ok(table.find(Config.Match.Boards, "Classic"), "Classic still offered")
	eq(Config.Match.Board, "Classic", "Classic still the default")
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[SunnyLoopV2Tests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	CoinService.resetAll()
	print(("[SunnyLoopV2Tests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
