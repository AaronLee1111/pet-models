--[[
	Unit tests for board arrival and movement presentation: the visible route of every move
	segment (BoardWorld:movePath / moveTime, Via waypoints), the board-opening intro schedule
	(IntroPlan) and its skip rules, intro data on every board, stacking slots, and that the
	move rules hand over to presentation in the right order (every hop is a real edge, forks and
	interactions only on the space the piece has reached, remaining counts, closed gates).
	Run with RunAll (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Server = ServerScriptService.PartyServer
local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local CoinService = require(Server.CoinService)
local Inventory = require(Server.Inventory)
local ReadyState = require(Server.ReadyState)
local BoardLayout = require(Server.Board.BoardLayout)
local BoardWorld = require(Server.Board.BoardWorld)
local IntroPlan = require(Server.Board.IntroPlan)
local Match = require(Server.Board.Match)
local SpaceTypes = require(Server.Board.SpaceTypes)

local BOARDS = { "Classic", "MagicalFestival", "SunnyLoopV2" }

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

local function load(name: string)
	return BoardLayout.load(require(Server.Board.Boards[name]), SpaceTypes)
end

local function withWorld(name: string, fn)
	local world = BoardWorld.build(load(name), SpaceTypes, Vector3.new(0, 0, -2100))
	local success, err = pcall(fn, world)
	world:destroy()
	if not success then
		error(err, 0)
	end
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

test("net: move and intro messages and the skip input exist", function()
	eq(Net.Message.BoardMove, "BoardMove", "BoardMove")
	eq(Net.Message.BoardIntro, "BoardIntro", "BoardIntro")
	eq(Net.Input.IntroSkip, "IntroSkip", "IntroSkip")
end)

test("every route edge on every board has a valid visible path (no jumps, ends on the slot)", function()
	for _, name in BOARDS do
		withWorld(name, function(world)
			local board = world.Board
			local edges, stairs = 0, 0
			for _, id in board.Order do
				for _, nextId in board.Spaces[id].Next do
					for slot = 1, 4 do
						local from = world:spaceCFrame(id, slot).Position
						local to = world:spaceCFrame(nextId, slot).Position
						local points, climb = world:movePath(from, id, nextId, to)
						local where = ("%s %d->%d slot %d"):format(name, id, nextId, slot)
						ok(#points >= 2, where .. ": too few points")
						ok(points[1] == from and points[#points] == to, where .. ": must start at the piece and end on its slot")
						local length = 0
						for i = 2, #points do
							ok(finite(points[i]), where .. ": bad point")
							local leg = points[i] - points[i - 1]
							ok(math.abs(leg.Y) <= 2.6, ("%s: %.1f-stud vertical jump"):format(where, leg.Y))
							length += leg.Magnitude
						end
						local straight = (to - from).Magnitude
						ok(length <= straight * 1.6 + 6, ("%s: path %.0f studs for %.0f straight"):format(where, length, straight))
						if climb then
							stairs += 1
							ok(#points >= 5, where .. ": stairs need a point per step")
						end
						local seconds = BoardWorld.moveTime(points, climb, 1, false)
						local band = if climb then Config.Board.StairTime else Config.Board.MoveTime
						local scale = Config.Board.HopTime / 0.35
						ok(seconds >= band[1] * scale - 1e-6 and seconds <= band[2] * scale + 1e-6, where .. ": time outside its band")
					end
					edges += 1
				end
			end
			ok(edges > 0, name .. ": no edges")
			if name == "SunnyLoopV2" then
				ok(stairs > 0, "Sunny Loop's terraces climb stairs")
			end
		end)
	end
end)

test("move time: long rolls speed up, bots a little faster, never below the ramp floor", function()
	local points = { Vector3.zero, Vector3.new(0, 0, 12) }
	local first = BoardWorld.moveTime(points, false, 1, false)
	local tenth = BoardWorld.moveTime(points, false, 10, false)
	local far = BoardWorld.moveTime(points, false, 60, false)
	ok(tenth < first, "later steps of a long roll are quicker")
	ok(math.abs(far / first - Config.Board.MoveRampMin) < 1e-6, "ramp floor")
	ok(BoardWorld.moveTime(points, false, 1, true) < first, "bots slightly faster")
	local normal = Config.Board.HopTime / 0.35
	ok(first >= 0.3 * normal and first <= 0.5 * normal, "a normal segment is 0.3-0.5 s")
	local stair = BoardWorld.moveTime(points, true, 1, false)
	ok(stair >= 0.45 * normal and stair <= 0.7 * normal, "a stair segment is 0.45-0.7 s")
	local pause = Config.Board.StepPause
	ok(pause >= 0.08 and pause <= 0.15, "landing pause 0.08-0.15 s")
end)

test("Via waypoints: validated against Next, used by the path, never change routes", function()
	local data = table.clone(require(Server.Board.Boards.Classic))
	data.Spaces = table.clone(data.Spaces)
	local first = table.clone(data.Spaces[1])
	first.Via = { [first.Next[1]] = { { 0.5, -0.4, 0 } } }
	data.Spaces[1] = first
	eq(BoardLayout.validate(data, SpaceTypes), nil, "valid Via")
	local board = BoardLayout.load(data, SpaceTypes)
	eq(#board.Spaces[1].Next, 1, "Via adds no route")
	local world = BoardWorld.build(board, SpaceTypes, Vector3.new(0, 0, -2100))
	local points = world:movePath(world:spaceCFrame(1, 1).Position, 1, first.Next[1], world:spaceCFrame(first.Next[1], 1).Position)
	world:destroy()
	eq(#points, 3, "start, the waypoint, the slot")
	first.Via = { [99] = { { 0, 0 } } }
	ok(BoardLayout.validate(data, SpaceTypes) ~= nil, "Via to a space that isn't Next is rejected")
	first.Via = { [first.Next[1]] = { "nope" } }
	ok(BoardLayout.validate(data, SpaceTypes) ~= nil, "malformed waypoint rejected")
end)

test("every board has intro data that resolves; broken or missing intro data is handled", function()
	for _, name in BOARDS do
		local data = require(Server.Board.Boards[name])
		ok(data.Intro ~= nil, name .. ": no Intro")
		eq(BoardLayout.validate(data, SpaceTypes), nil, name .. " validates")
		withWorld(name, function(world)
			local spec = world:introSpec()
			ok(spec and #spec.Entry >= 1, name .. ": entry")
			for _, key in { "Establish", "Arrival", "Group" } do
				ok(finite(spec[key].Camera) and (spec[key].Camera - spec[key].Look).Magnitude > 5, name .. ": " .. key .. " shot")
			end
			-- the entrance is near Start, not across the board
			local start = world.Tops[world.Board.Start]
			local landing = spec.Entry[#spec.Entry]
			ok((Vector3.new(landing.X, 0, landing.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude < 30, name .. ": entry far from Start")
		end)
	end
	local broken = table.clone(require(Server.Board.Boards.Classic))
	broken.Intro = { Establish = { Camera = { 0, 0 } } }
	ok(BoardLayout.validate(broken, SpaceTypes) ~= nil, "incomplete Intro rejected")
	broken.Intro = nil
	withWorld("Classic", function(world)
		world.Board.Intro = nil
		eq(world:introSpec(), nil, "no Intro: no spec (everyone on Start, group shot only)")
	end)
end)

test("intro cameras see the entrance and every Start slot; the entrance is open ground", function()
	for _, name in BOARDS do
		withWorld(name, function(world)
			local spec = world:introSpec()
			local slots = {}
			for slot = 1, 4 do
				local position = world:spaceCFrame(world.Board.Start, slot).Position
				table.insert(slots, position)
				table.insert(slots, position + Vector3.new(0, 1.5, 0))
			end
			local parts = {}
			for _, item in world.Folder:GetDescendants() do
				if item:IsA("BasePart") and item.Transparency < 0.9 and (item.Position - slots[1]).Magnitude < 90 then
					table.insert(parts, item)
				end
			end
			-- Scene props don't all collide or take queries, so test against their boxes directly.
			local function inside(point)
				for _, item in parts do
					local local_ = item.CFrame:PointToObjectSpace(point)
					local half = item.Size / 2
					if math.abs(local_.X) < half.X and math.abs(local_.Y) < half.Y and math.abs(local_.Z) < half.Z then
						return item
					end
				end
				return nil
			end
			local function blocker(from, targets)
				for _, target in targets do
					local delta = target - from
					local steps = math.ceil(delta.Magnitude / 0.6)
					for i = 1, steps - 2 do
						local hit = inside(from + delta * (i / steps))
						if hit then
							return hit:GetFullName()
						end
					end
				end
				return nil
			end
			local landing = spec.Entry[#spec.Entry]
			local arrival = blocker(spec.Arrival.Camera, { landing, table.unpack(slots) })
			ok(not arrival, ("%s: arrival camera blocked by %s"):format(name, tostring(arrival)))
			local group = blocker(spec.Group.Camera, slots)
			ok(not group, ("%s: group camera blocked by %s"):format(name, tostring(group)))
			ok(not inside(landing), name .. ": the entrance is inside a prop")
			local walk = blocker(landing, slots)
			ok(not walk, ("%s: the walk onto Start crosses %s"):format(name, tostring(walk)))
		end)
	end
end)

test("intro schedule: seat order, about 7-10 s, skipping only after everyone appeared", function()
	local plan = IntroPlan.schedule(4, true, nil, 100)
	for i = 2, 4 do
		ok(plan.ArriveAt[i] > plan.ArriveAt[i - 1], "arrivals follow seat order")
	end
	local times = Config.Board.Intro
	ok(times.Establish >= 1 and times.Establish <= 1.5, "establishing 1-1.5 s")
	ok(times.Each >= 1 and times.Each <= 1.4, "each arrival 1-1.4 s")
	ok(math.abs(times.Out - 0.4) < 1e-6, "transition 0.4 s")
	local total = plan.EndsAt - 100
	ok(total >= 7 and total <= 10, ("total %.1f s"):format(total))
	ok(plan.GroupAt >= plan.ArriveAt[4], "the group shot comes after the last arrival")
	-- board overrides
	local quick = IntroPlan.schedule(4, true, { Each = 1 }, 0)
	ok(math.abs(quick.ArriveAt[2] - quick.ArriveAt[1] - 1) < 1e-6, "Times override")
	-- no intro data: everyone already on Start, short group shot
	local none = IntroPlan.schedule(4, false, nil, 50)
	eq(none.ArriveAt[4], 50, "all at once")
	ok(none.EndsAt - 50 <= 2, "short")
	-- skip: humans only, after GroupAt, in the Intro stage, leavers never block
	local a, b = { Id = "a" }, { Id = "b" }
	local skips = ReadyState.new({ a, b }, plan.GroupAt, "Intro")
	ok(not skips:mark(a, "Intro", plan.ArriveAt[2]), "can't skip before everyone appeared")
	ok(not skips:mark(a, "OrderRoll", plan.GroupAt + 1), "only during the intro")
	ok(skips:mark(a, "Intro", plan.GroupAt + 0.1), "a skips")
	ok(not skips:everyone(), "b hasn't")
	b.Left = true
	ok(skips:everyone(), "a player who left doesn't block")
	ok(ReadyState.new({}, 0, "Intro"):everyone(), "bots only: nobody to wait for")
	-- the tutorial ready-up is unchanged
	ok(ReadyState.new({ a }, 0):mark(a, "Instructions", 1), "default phase still Instructions")
end)

test("stacking: four distinct, stable slots per space on every board", function()
	for _, name in BOARDS do
		withWorld(name, function(world)
			for _, id in world.Board.Order do
				local seen = {}
				for slot = 1, 4 do
					local position = world:spaceCFrame(id, slot).Position
					for _, other in seen do
						ok((other - position).Magnitude >= 4.5, ("%s space %d: slots overlap"):format(name, id))
					end
					table.insert(seen, position)
					eq(world:spaceCFrame(id, slot).Position, position, "same slot, same spot")
				end
			end
		end)
	end
end)

test("moves: every hop is a real edge, remaining counts down, closed gates never crossed, forks and interactions only on the reached space", function()
	for _, name in { "Classic", "SunnyLoopV2", "MagicalFestival" } do
		CoinService.resetAll()
		local participants = {}
		for i = 1, 4 do
			table.insert(participants, { Id = ("bot_motion_%s_%d"):format(name, i), Name = "M" .. i, IsBot = true })
		end
		local match
		local events = {}
		match = Match.new(load(name), participants, { Rounds = 5, Difficulty = "Normal" }, {
			Wallet = CoinService,
			Inventory = Inventory,
			Rng = Random.new(5),
			Ask = function(seat, request)
				table.insert(events, { Ask = request.Kind, At = seat.SpaceId })
				return match:botDecision(seat, request, 0.6)
			end,
			Duel = function() end,
		})
		for _, gate in match.Board.Gates or {} do
			match.GateOpen[gate.Id] = false
		end
		for turn = 1, 120 do
			local seat = match.Seats[(turn - 1) % 4 + 1]
			match:beginTurn(seat)
			local roll = (turn % 10) + 1 -- 1 .. 10: short, medium and large rolls
			local from, expected = seat.SpaceId, roll - 1
			table.clear(events)
			match:move(seat, roll, function(moved, id, remaining)
				eq(remaining, expected, name .. ": remaining")
				expected -= 1
				ok(moved.SpaceId == id, name .. ": hop reports the new space")
				local edge = table.find(match.Board.Spaces[from].Next, id) or table.find(match.Board.Spaces[id].Next, from)
				ok(edge, ("%s: hop %d->%d is not an edge"):format(name, from, id))
				for _, gate in match.Board.Gates or {} do
					ok(not (gate.From == from and gate.To == id), name .. ": crossed a closed gate")
				end
				table.insert(events, { Hop = id })
				from = id
			end)
			eq(expected, -1, name .. ": one hop per pip")
			-- Every question (fork, Crown, shop...) is asked where the piece stands after its last hop.
			local at = nil
			for _, event in events do
				if event.Hop then
					at = event.Hop
				elseif event.Ask and at then
					eq(event.At, at, ("%s: %s asked before landing"):format(name, event.Ask))
				end
			end
			match:endTurn()
		end
	end
	CoinService.resetAll()
end)

test("client motion: path sampling starts, ends and interpolates correctly", function()
	local module = StarterPlayer.StarterPlayerScripts:FindFirstChild("BoardMotion", true)
	ok(module, "BoardMotion not mapped")
	local BoardMotion = require(module)
	local points = { Vector3.zero, Vector3.new(0, 0, 10), Vector3.new(10, 0, 10) }
	eq(BoardMotion.length(points), 20, "length")
	eq(BoardMotion.sample(points, 0), Vector3.zero, "start")
	eq(BoardMotion.sample(points, 20), Vector3.new(10, 0, 10), "end")
	eq(BoardMotion.sample(points, 99), Vector3.new(10, 0, 10), "past the end clamps (snap to the space)")
	local middle, direction = BoardMotion.sample(points, 15)
	eq(middle, Vector3.new(5, 0, 10), "second leg")
	eq(direction, Vector3.new(10, 0, 0), "facing the leg")
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[BoardMotionTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[BoardMotionTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
