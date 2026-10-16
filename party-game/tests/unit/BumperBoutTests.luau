--[[
	Unit tests for Bumper Bout: dash validation and cooldown, hit detection (one per dash,
	clashes), knockback limits, ring-outs (including both at once), the shrink schedule, the
	time limit (centre, hits, sudden death), leaving, bot planning, cleanup, and that Duel
	spaces can pick it while the 4-player vote never does. Run with RunAll (see README).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local MinigameInfo = require(Server.MinigameInfo)
local MinigameManager = require(Server.MinigameManager)
local BB = require(Server.Minigames.BumperBout)

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

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

-- Two fighters. With bodies, each has a real (anchored) character in the workspace.
local function fighters(withBodies: boolean?)
	local list = {}
	for i = 1, 2 do
		local character, root, humanoid
		if withBodies then
			character = Instance.new("Model")
			character.Name = "BumperTest" .. i
			root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Anchored = true
			root.Size = Vector3.new(2, 2, 1)
			root.Parent = character
			humanoid = Instance.new("Humanoid")
			humanoid.Parent = character
			character.PrimaryPart = root
			character.Parent = workspace
		end
		local participant = { Id = "bot_bb" .. i, Name = "B" .. i, IsBot = false }
		function participant:GetCharacter()
			return character
		end
		function participant:GetRoot()
			return root
		end
		function participant:GetHumanoid()
			return humanoid
		end
		function participant:IsAlive()
			return character ~= nil and character.Parent ~= nil
		end
		table.insert(list, participant)
	end
	return list
end

local function fakeRound(participants)
	local round = { Participants = participants, Ended = false, Toasts = {}, Progress = {}, Eliminated = {}, EndsAt = 100 }
	function round:ReportProgress(p, value)
		self.Progress[p] = value
	end
	function round:SetStatus(text)
		self.Status = text
	end
	function round:Toast(text)
		table.insert(self.Toasts, text)
	end
	function round:End(reason)
		self.Ended = true
		self.EndReason = reason
	end
	function round:Eliminate(p)
		self.Eliminated[p] = true
	end
	function round:IsEliminated(p)
		return self.Eliminated[p] == true
	end
	return round
end

local ORIGIN = CFrame.new(0, 1200, 0)

local function newGame(withBodies)
	local participants = fighters(withBodies)
	local folder = Instance.new("Folder")
	folder.Name = "BumperBoutTestArena"
	folder.Parent = workspace
	local arena = { Folder = folder, Origin = ORIGIN, SpectatorCFrame = ORIGIN + Vector3.new(0, 45, 0) }
	local round = fakeRound(participants)
	local game_ = setmetatable({ Round = round, Arena = arena, Participants = participants }, { __index = BB })
	game_:Setup(arena, participants, round)
	return game_, round, folder, participants
end

local function placementOf(results, participant)
	for _, result in results do
		if result.Participant == participant then
			return result.Placement
		end
	end
end

local function activeCore()
	local a, b = table.unpack(fighters())
	local core = BB.newCore({ a, b })
	core.Active = true
	return core, a, b
end

local function place(participant, x: number, z: number, y: number?)
	participant:GetRoot().CFrame = ORIGIN * CFrame.new(x, y or 3, z)
end

-- Framework ----------------------------------------------------------------------------------

test("info: a valid Duel with free movement, no jump, DASH on E/Space, X/R1 and screen", function()
	eq(MinigameInfo.validate(BB), nil, "validates")
	local info = MinigameInfo.normalize("BumperBout", BB.Info)
	eq(info.Layout, "Duel")
	eq(info.Camera.Mode, "AngledOverhead")
	eq(info.Controls.Move, true, "free movement")
	eq(info.Controls.Jump, false, "no jumping")
	eq(info.Controls.WalkSpeed, BB.WALK_SPEED)
	eq(#info.Controls.Actions, 1)
	local dash = info.Controls.Actions[1]
	eq(dash.Action, "Dash")
	eq(table.concat(dash.Keys, ","), "E,Space")
	eq(table.concat(dash.Gamepads, ","), "ButtonX,ButtonR1")
	ok(BB.ROUND_LIMIT >= 12 and BB.ROUND_LIMIT <= 20, "12-20 s target")
end)

test("duel spaces pick from both Duel games; the 4-player vote never offers them", function()
	MinigameManager.loadMinigames()
	local duels, vote = {}, {}
	for _, entry in MinigameManager.duelMinigames() do
		duels[entry.Id] = true
	end
	for _, entry in MinigameManager.voteMinigames() do
		vote[entry.Id] = true
	end
	ok(duels.QuickDraw and duels.BumperBout, "both Duel games eligible")
	ok(not vote.QuickDraw and not vote.BumperBout, "neither in the vote")
	ok(vote.TrailTangle and vote.IceDash, "normal games still in the vote")
end)

-- Dash requests ----------------------------------------------------------------------------------

test("dash cooldown: one dash, then nothing until the cooldown has passed", function()
	local core, a = activeCore()
	ok(BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 10), "first dash")
	local accepted, why = BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 10 + BB.DASH_COOLDOWN * 0.5)
	ok(not accepted, "inside the cooldown")
	eq(why, "cooldown")
	ok(not BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 10), "duplicate request at the same instant")
	ok(BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 10 + BB.DASH_COOLDOWN + 0.01), "after the cooldown")
	eq(core.Fighters[a].DashCount, 2)
end)

test("dash validation: identity, phase, state, malformed / NaN / infinite input", function()
	local core, a, b = activeCore()
	local stranger = fighters()[1]
	eq(select(2, BB.validateDash(core, stranger, Vector3.new(1, 0, 0), nil, 1)), "not_in_duel")
	core.Active = false
	eq(select(2, BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 1)), "not_playing")
	core.Active = true
	core.Fighters[b].Out = true
	eq(select(2, BB.validateDash(core, b, Vector3.new(1, 0, 0), nil, 1)), "out")
	local nan, inf = 0 / 0, math.huge
	for label, dir in {
		text = "left",
		number = 5,
		nanX = { X = nan, Z = 0 },
		infZ = { X = 0, Z = inf },
		huge = Vector3.new(30, 0, 0),
		vecNaN = Vector3.new(nan, 0, 1),
		missingZ = { X = 1 },
	} do
		local accepted, why = BB.validateDash(core, a, dir, nil, 5)
		ok(not accepted, "rejected " .. label)
		eq(why, "malformed", label)
	end
	eq(select(2, BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, nan)), "cooldown", "NaN time")
	eq(select(2, BB.validateDash(core, a, Vector3.zero, nil, 5)), "no_direction", "no input, no facing")
	local accepted, _, dir = BB.validateDash(core, a, Vector3.zero, Vector3.new(0, 0.8, -2), 5)
	ok(accepted, "standing still: uses facing")
	ok(near(dir.Y, 0) and near(dir.Z, -1), "flat, normalized facing")
	core.Fighters[a].LastDashAt = -math.huge
	local _, _, moving = BB.validateDash(core, a, { X = 0.6, Z = 0.8 }, Vector3.new(1, 0, 0), 9)
	ok(near(moving.X, 0.6, 1e-3) and near(moving.Z, 0.8, 1e-3), "moving: uses the move direction")
end)

-- Hits ---------------------------------------------------------------------------------------------

test("hit detection: a lunge into the opponent knocks them away, once per dash", function()
	local core, a, b = activeCore()
	BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 0)
	local positions = { [a] = Vector3.new(0, 0, 0), [b] = Vector3.new(3, 0, 0.5) }
	local hits = BB.detectHits(core, positions, 0.1)
	eq(#hits, 1)
	eq(hits[1].Attacker, a)
	eq(hits[1].Victim, b)
	ok(hits[1].Dir.X > 0.9, "pushed away from the attacker, along the lunge")
	eq(hits[1].Speed, BB.KNOCKBACK)
	eq(core.Fighters[a].Hits, 1)
	ok(core.Fighters[b].HitStep ~= nil, "victim's hit step recorded")
	eq(#BB.detectHits(core, positions, 0.15), 0, "still overlapping: no second hit from the same dash")
	eq(#BB.detectHits(core, positions, 0.2), 0)
end)

test("no hit when out of reach, when the lunge has ended, or just walking into them", function()
	local core, a, b = activeCore()
	BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 0)
	eq(#BB.detectHits(core, { [a] = Vector3.zero, [b] = Vector3.new(BB.HIT_RADIUS + 0.5, 0, 0) }, 0.1), 0, "out of reach")
	local late = BB.DASH_DURATION + BB.HIT_WINDOW_EXTRA + 0.05
	eq(#BB.detectHits(core, { [a] = Vector3.zero, [b] = Vector3.new(2, 0, 0) }, late), 0, "lunge over")
	local core2, c, d = activeCore()
	eq(#BB.detectHits(core2, { [c] = Vector3.zero, [d] = Vector3.new(1, 0, 0) }, 1), 0, "no lunge, no hit")
end)

test("simultaneous dashes: a clash bounces both back, weaker, in opposite directions", function()
	local core, a, b = activeCore()
	BB.validateDash(core, a, Vector3.new(1, 0, 0), nil, 0)
	BB.validateDash(core, b, Vector3.new(-1, 0, 0), nil, 0)
	local hits = BB.detectHits(core, { [a] = Vector3.zero, [b] = Vector3.new(3, 0, 0) }, 0.1)
	eq(#hits, 2, "both")
	ok(hits[1].Speed < BB.KNOCKBACK and near(hits[1].Speed, hits[2].Speed), "equal, weaker bounce")
	ok(near(hits[1].Dir:Dot(hits[2].Dir), -1, 1e-3), "opposite directions")
	eq(core.Fighters[a].Hits, core.Fighters[b].Hits, "a clash counts the same for both")
	eq(core.Fighters[a].HitStep, core.Fighters[b].HitStep, "hit on the same step")
end)

test("knockback: capped, decays, stops; a hit can't throw anyone across the map", function()
	eq(BB.knockbackSpeed(1000, 0), BB.KNOCKBACK_MAX, "capped")
	ok(BB.knockbackSpeed(BB.KNOCKBACK, 0.2) < BB.knockbackSpeed(BB.KNOCKBACK, 0.05), "decays")
	eq(BB.knockbackSpeed(BB.KNOCKBACK, BB.KNOCKBACK_TIME + 0.01), 0, "over")
	eq(BB.knockbackSpeed(0 / 0, 0.1), 0, "NaN speed")
	eq(BB.knockbackSpeed(BB.KNOCKBACK, 0 / 0), 0, "NaN time")
	eq(BB.knockbackSpeed(BB.KNOCKBACK, -1), 0, "before impact")
	local distance, t = 0, 0
	while t < BB.KNOCKBACK_TIME do
		distance += BB.knockbackSpeed(BB.KNOCKBACK_MAX, t) * (1 / 240)
		t += 1 / 240
	end
	ok(distance > 6 and distance < 16, ("a full-strength push moves %.1f studs"):format(distance))
	local normal, t2 = 0, 0
	while t2 < BB.KNOCKBACK_TIME do
		normal += BB.knockbackSpeed(BB.KNOCKBACK, t2) * (1 / 240)
		t2 += 1 / 240
	end
	ok(BB.SPAWN_DISTANCE + normal + BB.HIT_RADIUS < BB.START_RADIUS, "one opening hit can't ring anyone out")
	ok(BB.MAX_PLAUSIBLE_SPEED > BB.DASH_SPEED and BB.MAX_PLAUSIBLE_SPEED < BB.KNOCKBACK_MAX + BB.DASH_SPEED, "watchdog sits above legit speeds")
end)

-- Ring-outs -------------------------------------------------------------------------------------

test("ring-out: past the safe radius, fallen, under the platform, or nonsense positions", function()
	local r = 15
	ok(not BB.isOut(Vector3.new(r - 1, 3, 0), r), "inside")
	ok(not BB.isOut(Vector3.new(r + BB.EDGE_GRACE - 0.1, 3, 0), r), "feet on the rim")
	ok(BB.isOut(Vector3.new(r + BB.EDGE_GRACE + 0.1, 3, 0), r), "past the edge")
	ok(BB.isOut(Vector3.new(0, -BB.FALL_DEPTH - 0.1, 2), r), "knocked under the platform")
	ok(BB.isOut(Vector3.new(0 / 0, 3, 0), r), "NaN position")
	ok(BB.isOut(Vector3.new(math.huge, 3, 0), r), "infinite position")
	-- The safe radius decides, not where the old, bigger platform was.
	ok(BB.isOut(Vector3.new(14, 3, 0), BB.FINAL_RADIUS), "outside the shrunken circle")
	local core, a, b = activeCore()
	local out, loser = BB.ringOuts(core, { [a] = Vector3.new(0, 3, 0), [b] = Vector3.new(30, 3, 0) }, r)
	eq(#out, 1)
	eq(loser, b)
	ok(core.Fighters[b].Out and not core.Fighters[a].Out, "marked")
end)

test("both out on one step: hit first loses, then farther out loses, then a tie", function()
	local core, a, b = activeCore()
	core.Fighters[a].HitStep, core.Fighters[b].HitStep = 4, 7
	local _, loser = BB.ringOuts(core, { [a] = Vector3.new(20, 3, 0), [b] = Vector3.new(-25, 3, 0) }, 10)
	eq(loser, a, "a was hit first")
	core, a, b = activeCore()
	core.Fighters[a].HitStep, core.Fighters[b].HitStep = 5, 5
	_, loser = BB.ringOuts(core, { [a] = Vector3.new(20, 3, 0), [b] = Vector3.new(-25, 3, 0) }, 10)
	eq(loser, b, "same step: b farther from the middle")
	core, a, b = activeCore()
	local out
	out, loser = BB.ringOuts(core, { [a] = Vector3.new(20, 3, 0), [b] = Vector3.new(0, 3, -20) }, 10)
	eq(#out, 2)
	eq(loser, nil, "exactly level: shared result")
end)

-- Shrink and time limit -------------------------------------------------------------------------

test("shrink: holds, warns, shrinks smoothly to a still-roomy final circle", function()
	eq(BB.radiusAt(0), BB.START_RADIUS)
	eq(BB.radiusAt(BB.SHRINK_DELAY), BB.START_RADIUS, "flat until the delay")
	eq(BB.radiusAt(BB.SHRINK_DELAY + BB.SHRINK_DURATION), BB.FINAL_RADIUS)
	eq(BB.radiusAt(1000), BB.FINAL_RADIUS, "stays final")
	ok(BB.SHRINK_WARNING > 0 and BB.SHRINK_WARNING < BB.SHRINK_DELAY, "warning comes before it starts")
	local previous, fastest = math.huge, 0
	for t = 0, BB.ROUND_LIMIT, 0.05 do
		local r = BB.radiusAt(t)
		ok(r <= previous + 1e-9, "never grows")
		fastest = math.max(fastest, (previous == math.huge and 0 or previous - r) / 0.05)
		previous = r
	end
	ok(fastest < BB.WALK_SPEED / 4, ("edge moves at most %.1f studs/s: easy to walk away from"):format(fastest))
	ok(BB.FINAL_RADIUS >= 8, "final circle leaves room to move")
	ok(BB.SHRINK_DELAY + BB.SHRINK_DURATION < BB.ROUND_LIMIT, "final circle before the time limit")
end)

test("time limit: closest to the middle wins; hits break a tie; else sudden death", function()
	local core, a, b = activeCore()
	eq(BB.timeLimitWinner(core, { [a] = Vector3.new(2, 3, 0), [b] = Vector3.new(0, 3, 6) }), a, "closer")
	eq(BB.timeLimitWinner(core, { [a] = Vector3.new(5, 3, 0), [b] = Vector3.new(0, 3, 5.3) }), nil, "level, no hits: sudden death")
	core.Fighters[b].Hits = 2
	core.Fighters[a].Hits = 1
	eq(BB.timeLimitWinner(core, { [a] = Vector3.new(5, 3, 0), [b] = Vector3.new(0, 3, 5.3) }), b, "more hits")
	core.Fighters[a].Out = true
	eq(BB.timeLimitWinner(core, { [a] = Vector3.new(0, 3, 0), [b] = Vector3.new(9, 3, 0) }), b, "only one still in")
end)

test("round: time limit tie goes to sudden death, which is then decided by position", function()
	local game_, round, folder, players = newGame(true)
	local a, b = players[1], players[2]
	game_:Start()
	place(a, 5, 0)
	place(b, 0, 5)
	game_.StartedAt = os.clock() - BB.ROUND_LIMIT - 0.1
	game_:_step(1 / 60)
	ok(game_.SuddenDeath, "sudden death")
	ok(not round.Ended, "still going")
	ok(round.Status and round.Status:find("Sudden death"), "announced")
	eq(game_.Radius, BB.FINAL_RADIUS, "final circle")
	place(b, 0, 2)
	game_.SuddenDeathEnds = os.clock() - 0.01
	game_:_step(1) -- a second later: a 3-stud walk is plausible
	ok(round.Ended, "over")
	eq(placementOf(game_:GetResults(), b), 1, "closer at the end wins")
	eq(placementOf(game_:GetResults(), a), 2)
	game_:Cleanup()
	folder:Destroy()
	for _, p in players do
		p:GetCharacter():Destroy()
	end
end)

test("round: a ring-out ends it at once, loser eliminated, winner first", function()
	local game_, round, folder, players = newGame(true)
	local a, b = players[1], players[2]
	game_:Start()
	place(a, 0, 0)
	place(b, BB.START_RADIUS + 3, 0)
	game_:_step(1 / 60)
	ok(round.Ended, "ended")
	eq(round.EndReason, "RingOut")
	ok(round.Eliminated[b], "loser out")
	eq(placementOf(game_:GetResults(), a), 1)
	game_:Cleanup()
	folder:Destroy()
	for _, p in players do
		p:GetCharacter():Destroy()
	end
end)

test("leaving or dying hands the duel to the other player without stalling", function()
	local game_, round, folder, players = newGame(true)
	game_:Start()
	game_:OnParticipantLost(players[1], "Left")
	ok(round.Ended, "ended at once")
	eq(placementOf(game_:GetResults(), players[2]), 1, "the one who stayed wins")
	game_:OnParticipantLost(players[2], "Died") -- after it's decided: ignored
	eq(placementOf(game_:GetResults(), players[2]), 1)
	game_:Cleanup()
	folder:Destroy()
	for _, p in players do
		p:GetCharacter():Destroy()
	end
end)

-- Bots ------------------------------------------------------------------------------------------

local function plan(overrides, skill, seed)
	local state = {
		Me = Vector3.new(0, 0, 0),
		MyVel = Vector3.zero,
		Them = Vector3.new(8, 0, 0),
		TheirVel = Vector3.zero,
		TheirDash = nil,
		Radius = 18,
		RadiusSoon = 18,
		CanDash = true,
	}
	for key, value in overrides or {} do
		state[key] = value
	end
	return BB.botPlan(state, skill or 1, Random.new(seed or 1))
end

test("bots head back to the middle near the edge, including an edge that's about to move", function()
	local p = plan({ Me = Vector3.new(16.5, 0, 0), Them = Vector3.new(-5, 0, 0) })
	eq(p.MoveTo, Vector3.zero, "near the edge: back to the middle")
	p = plan({ Me = Vector3.new(9, 0, 0), Them = Vector3.new(-5, 0, 0), Radius = 18, RadiusSoon = 11 })
	eq(p.MoveTo, Vector3.zero, "shrink coming: back in early")
	p = plan({ Me = Vector3.new(2, 0, 0), Them = Vector3.new(-12, 0, 0), CanDash = false })
	ok(p.MoveTo.Magnitude < 18 - BB.BOT.EdgeMargin[2] + 0.01, "positions inside the safe area")
	ok((p.MoveTo - Vector3.new(-12, 0, 0)).Magnitude < 10, "closes in on the opponent")
end)

test("bots never lunge themselves off the platform", function()
	for seed = 1, 300 do
		local rng = Random.new(seed)
		local radius = rng:NextNumber(BB.FINAL_RADIUS, BB.START_RADIUS)
		local angle = rng:NextNumber(0, math.pi * 2)
		local me = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, radius)
		local them = me + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
		local p = BB.botPlan({ Me = me, Them = them, Radius = radius, RadiusSoon = radius, CanDash = true }, rng:NextNumber(), rng)
		if p.Dash then
			local landing = me + p.Dash * (BB.DASH_SPEED * BB.DASH_DURATION)
			ok(landing.Magnitude < radius, ("seed %d: lunge would land off the edge"):format(seed))
		end
	end
end)

test("bots lunge when lined up, lead a moving target, and only use legal dashes", function()
	local p = plan({ Me = Vector3.new(-2, 0, 0), Them = Vector3.new(6, 0, 0) })
	ok(p.Dash and p.Dash.X > 0.9, "lined up between me and the edge: lunge")
	eq(plan({ CanDash = false }).Dash, nil, "no lunge on cooldown")
	eq(plan({ Them = Vector3.new(16, 0, 0), Me = Vector3.new(-4, 0, 0) }).Dash, nil, "out of reach")
	local led = plan({ Me = Vector3.new(-2, 0, 0), Them = Vector3.new(6, 0, 0), TheirVel = Vector3.new(0, 0, 14) }, 1)
	ok(led.Dash and led.Dash.Z > 0.2, "skilled bots aim where they're going")
	local naiveZ, naiveCount = 0, 0
	for seed = 1, 60 do
		local naive = plan({ Me = Vector3.new(-2, 0, 0), Them = Vector3.new(6, 0, 0), TheirVel = Vector3.new(0, 0, 14) }, 0, seed)
		if naive.Dash then
			naiveZ += naive.Dash.Z
			naiveCount += 1
		end
	end
	ok(naiveCount > 0 and naiveZ / naiveCount < led.Dash.Z / 2, "unskilled bots aim at where they are")
	-- Whatever a bot asks for goes through the same validation as a player.
	local core, a = activeCore()
	ok(BB.validateDash(core, a, p.Dash, nil, 1), "bot dash direction is valid input")
end)

test("bot skill: better bots dodge more and mistime less", function()
	local function count(skill)
		local dodges, wild = 0, 0
		for seed = 1, 400 do
			local incoming = plan({ Me = Vector3.new(0, 0, 0), Them = Vector3.new(-6, 0, 0), TheirDash = Vector3.new(1, 0, 0) }, skill, seed)
			if incoming.MoveTo.Magnitude > 0.1 and math.abs(incoming.MoveTo.Z) > 4 then
				dodges += 1
			end
			local attack = plan({ Me = Vector3.new(-2, 0, 0), Them = Vector3.new(6, 0, 0) }, skill, seed + 1000)
			if attack.Dash and attack.Dash.X < math.cos(math.rad(8)) then
				wild += 1
			end
		end
		return dodges, wild
	end
	local dodgeLow, wildLow = count(0)
	local dodgeHigh, wildHigh = count(1)
	ok(dodgeHigh > dodgeLow + 100, ("dodges: skill 1 %d vs skill 0 %d"):format(dodgeHigh, dodgeLow))
	ok(wildLow > wildHigh, ("bad angles: skill 0 %d vs skill 1 %d"):format(wildLow, wildHigh))
end)

-- Cleanup ---------------------------------------------------------------------------------------

test("cleanup: loop disconnected, lunge/push constraints and cues removed, parts only in the arena", function()
	local before = #workspace:GetChildren()
	local game_, _, folder, players = newGame(true)
	game_:Start()
	place(players[1], -5, 0)
	place(players[2], -2, 0)
	ok(game_:RequestDash(players[1], Vector3.new(1, 0, 0)), "dash accepted")
	local root = players[1]:GetRoot()
	ok(root:FindFirstChild("BumperBoutDash"), "lunge constraint while dashing")
	ok(players[1]:GetCharacter():FindFirstChild("BumperBoutCue"), "dash cue")
	ok(not game_:RequestDash(players[1], Vector3.new(1, 0, 0)), "second request inside the cooldown refused")
	game_:_step(1 / 60) -- the lunge connects
	ok(players[2]:GetRoot():FindFirstChild("BumperBoutPush"), "knockback on the victim")
	local connection = game_.Connections[1]
	game_:Cleanup()
	ok(not connection.Connected, "loop disconnected")
	for _, p in players do
		local r = p:GetRoot()
		ok(not r:FindFirstChild("BumperBoutDash") and not r:FindFirstChild("BumperBoutPush"), "constraints gone")
		ok(not r:FindFirstChild("BumperBoutAttachment"), "attachment gone")
		ok(not p:GetCharacter():FindFirstChild("BumperBoutCue"), "cue gone")
	end
	ok(not game_.Core.Active, "rules stopped")
	folder:Destroy()
	for _, p in players do
		p:GetCharacter():Destroy()
	end
	eq(#workspace:GetChildren(), before, "nothing left outside the arena")
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
			warn(("[BumperBoutTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[BumperBoutTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
