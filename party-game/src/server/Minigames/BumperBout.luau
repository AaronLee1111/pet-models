--[[
	Bumper Bout (Duel: exactly two players, played from board Duel spaces)
	A shoving match on a small round platform floating in the sky. Walk around freely and
	press DASH to lunge: dash into your opponent and they're knocked back. Fall off and you
	lose. After a few seconds the platform shrinks to a small final circle. At the time limit
	whoever stands closest to the middle wins (then most hits, then a short sudden death).
	It's about positioning and timing: get between your opponent and the middle, read where
	they're going, and don't dash yourself off the edge.

	Server-authoritative:
	  * A DASH is a request ("Dash" action, or a direction from client/Minigames/BumperBout);
	    the server checks cooldown, phase and the direction, then drives the lunge itself.
	  * The server decides hits (one per dash), knockback, ring-outs and the result, from its
	    own view of where everyone is. Lunges and knockback are velocity constraints made
	    here, so they work whoever simulates the body, and implausible movement is snapped back.
	  * The visible platform is resized together with the safe radius; the safe radius (not
	    the parts) decides ring-outs.
	The pure rule functions below the tuning are what the unit tests drive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local BumperBout = {}

-- Tuning ----------------------------------------------------------------------------------

BumperBout.START_RADIUS = 22 -- studs
BumperBout.FINAL_RADIUS = 10 -- still room to walk around and line up a dash
BumperBout.SHRINK_DELAY = 4 -- seconds before shrinking starts
BumperBout.SHRINK_DURATION = 8 -- seconds to go from start to final radius
BumperBout.SHRINK_WARNING = 1.5 -- seconds of "Platform shrinking!" before it starts
BumperBout.ROUND_LIMIT = 18 -- seconds; then closest to the middle wins
BumperBout.SUDDEN_DEATH = 6 -- extra seconds if the time limit can't separate them
BumperBout.WALK_SPEED = 16
BumperBout.DASH_SPEED = 55 -- studs/second during a lunge
BumperBout.DASH_DURATION = 0.22 -- seconds (about 12 studs)
BumperBout.DASH_COOLDOWN = 2.0 -- seconds between dashes (server clock)
BumperBout.HIT_WINDOW_EXTRA = 0.12 -- a lunge can still connect this long after it ends (lag)
BumperBout.HIT_RADIUS = 4.5 -- studs between the two bodies' centres
BumperBout.KNOCKBACK = 62 -- studs/second at the moment of impact
BumperBout.KNOCKBACK_MAX = 90 -- hard cap on any knockback speed
BumperBout.KNOCKBACK_DECAY = 6 -- per second (exponential): ~9.5 studs of push in total
BumperBout.KNOCKBACK_TIME = 0.45 -- seconds the push is applied
BumperBout.CLASH_FACTOR = 0.6 -- both dash into each other: both bounce back this much
BumperBout.EDGE_GRACE = 0.75 -- studs past the safe radius a body's centre may be (feet on the rim)
BumperBout.FALL_DEPTH = 3 -- studs below the platform top that count as fallen
BumperBout.CENTER_TIE = 0.5 -- studs: closer than this to each other's distance is a tie
BumperBout.MAX_PLAUSIBLE_SPEED = 75 -- studs/second a player's body may move before it's snapped back
BumperBout.PLATFORM_HEIGHT = 2
BumperBout.SPAWN_DISTANCE = 7.5 -- studs from the middle: one opening hit can't ring anyone out

-- Bots (skill 0..1 blends from the first number to the second)
BumperBout.BOT = {
	Reaction = { 0.45, 0.12 }, -- seconds between decisions
	Lead = { 0, 0.35 }, -- seconds of opponent movement predicted when aiming
	Mistake = { 0.25, 0.03 }, -- chance a dash is mistimed or badly angled
	MistakeAngle = 35, -- degrees of error on a bad angle
	EdgeMargin = { 3, 5.5 }, -- studs from the (upcoming) edge where they head back in
	Dodge = { 0, 0.8 }, -- chance to sidestep a dash coming at them
	DashReach = 12, -- studs: how far away they'll start a lunge
}

BumperBout.Info = {
	Name = "Bumper Bout",
	Description = "Shove your rival off the platform! Walk around and press DASH to lunge into them. The platform shrinks, so stay near the middle. Don't dash yourself off!",
	Duration = BumperBout.ROUND_LIMIT,
	Layout = Config.Layouts.Duel,
	Camera = { Mode = "AngledOverhead", Height = 50, Distance = 30, Follow = 0, Smooth = 20, TouchZoom = 1, TouchLookAhead = 4 },
	Controls = {
		Move = true,
		Jump = false,
		WalkSpeed = BumperBout.WALK_SPEED,
		Actions = {
			{ Action = "Dash", Label = "DASH", Keys = { "E", "Space" }, Gamepads = { "ButtonX", "ButtonR1" } },
		},
	},
	ProgressLabel = "Hits",
	ClientModule = "BumperBout", -- sends the dash with the stick/keys direction; cooldown on the button
}

-- Rules (pure) ------------------------------------------------------------------------------

local function finite(n): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
BumperBout.finite = finite

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Safe radius `elapsed` seconds into the round: flat, then a smooth shrink, then flat.
function BumperBout.radiusAt(elapsed: number): number
	local t = math.clamp((elapsed - BumperBout.SHRINK_DELAY) / BumperBout.SHRINK_DURATION, 0, 1)
	t = t * t * (3 - 2 * t)
	return BumperBout.START_RADIUS + (BumperBout.FINAL_RADIUS - BumperBout.START_RADIUS) * t
end

--[[
	Per-round rule state. `fighters` = the two participants. Positions handed to the rule
	functions are relative to the platform centre (Y = height above the platform top).
]]
function BumperBout.newCore(fighters)
	local core = { Active = false, Step = 0, Fighters = {} }
	for _, participant in fighters do
		core.Fighters[participant] = {
			LastDashAt = -math.huge,
			Dash = nil, -- { Id, Dir, StartedAt, Until, Hit }
			DashCount = 0,
			Hits = 0,
			HitStep = nil, -- step they were last hit on
			Out = false,
			OutStep = nil,
		}
	end
	return core
end

--[[
	A dash request at server time `now`. `dir` is an optional direction (Vector3 or {X, Z})
	from the player's client; nil or zero falls back to `fallback` (their facing). Returns
	ok, reason, and the normalized flat direction.
]]
function BumperBout.validateDash(core, participant, dir, fallback, now: number)
	local fighter = core.Fighters[participant]
	if not fighter then
		return false, "not_in_duel"
	end
	if not core.Active then
		return false, "not_playing"
	end
	if fighter.Out then
		return false, "out"
	end
	if not finite(now) or now - fighter.LastDashAt < BumperBout.DASH_COOLDOWN then
		return false, "cooldown"
	end
	local x, z
	if typeof(dir) == "Vector3" then
		x, z = dir.X, dir.Z
	elseif type(dir) == "table" then
		x, z = dir.X, dir.Z
	elseif dir ~= nil then
		return false, "malformed"
	end
	if dir ~= nil then
		if not finite(x) or not finite(z) then
			return false, "malformed"
		end
		if x * x + z * z > 1.5 * 1.5 then
			return false, "malformed" -- a direction, not a destination
		end
	end
	local chosen = if x and (x * x + z * z) > 0.01 then Vector3.new(x, 0, z) else nil
	if not chosen and typeof(fallback) == "Vector3" and finite(fallback.X) and finite(fallback.Z) then
		chosen = flat(fallback)
	end
	if not chosen or chosen.Magnitude < 0.01 then
		return false, "no_direction"
	end
	fighter.LastDashAt = now
	fighter.DashCount += 1
	fighter.Dash = {
		Id = fighter.DashCount,
		Dir = chosen.Unit,
		StartedAt = now,
		Until = now + BumperBout.DASH_DURATION,
		Hit = false,
	}
	return true, nil, chosen.Unit
end

local function lunging(fighter, now: number): boolean
	local dash = fighter.Dash
	return dash ~= nil and not dash.Hit and now <= dash.Until + BumperBout.HIT_WINDOW_EXTRA
end

--[[
	Who hit whom this step. positions[p] = Vector3 (relative). Each dash can hit once. Two
	lunges meeting is a clash: both bounce back (weaker) and both count a hit.
	Returns a list of { Attacker, Victim, Dir (flat unit, away from the attacker), Speed }.
]]
function BumperBout.detectHits(core, positions, now: number)
	core.Step += 1
	local list = {}
	local a, b
	for participant in core.Fighters do
		if a then
			b = participant
		else
			a = participant
		end
	end
	if not a or not b then
		return list
	end
	local fa, fb = core.Fighters[a], core.Fighters[b]
	local pa, pb = positions[a], positions[b]
	if fa.Out or fb.Out or not pa or not pb then
		return list
	end
	local gap = flat(pb - pa)
	if gap.Magnitude > BumperBout.HIT_RADIUS then
		return list
	end
	local away = if gap.Magnitude > 0.01 then gap.Unit else Vector3.new(1, 0, 0)
	local la, lb = lunging(fa, now), lunging(fb, now)
	local function hit(attacker, victim, dir, speed)
		local fAttacker, fVictim = core.Fighters[attacker], core.Fighters[victim]
		fAttacker.Dash.Hit = true
		fAttacker.Hits += 1
		fVictim.HitStep = core.Step
		table.insert(list, { Attacker = attacker, Victim = victim, Dir = dir, Speed = math.min(speed, BumperBout.KNOCKBACK_MAX) })
	end
	if la and lb then
		local speed = BumperBout.KNOCKBACK * BumperBout.CLASH_FACTOR
		hit(a, b, away, speed)
		hit(b, a, -away, speed)
	elseif la then
		local dir = (away + fa.Dash.Dir).Unit -- mostly away from the attacker, along the lunge
		hit(a, b, dir, BumperBout.KNOCKBACK)
	elseif lb then
		local dir = (-away + fb.Dash.Dir).Unit
		hit(b, a, dir, BumperBout.KNOCKBACK)
	end
	return list
end

-- Knockback speed `t` seconds after impact (0 once it's over); never above the cap.
function BumperBout.knockbackSpeed(speed: number, t: number): number
	if not finite(speed) or not finite(t) or t < 0 or t > BumperBout.KNOCKBACK_TIME then
		return 0
	end
	return math.min(speed, BumperBout.KNOCKBACK_MAX) * math.exp(-BumperBout.KNOCKBACK_DECAY * t)
end

-- Is a body at `position` (relative) off a platform of `radius`?
function BumperBout.isOut(position: Vector3, radius: number): boolean
	if not finite(position.X) or not finite(position.Y) or not finite(position.Z) then
		return true
	end
	return position.Y < -BumperBout.FALL_DEPTH or flat(position).Magnitude > radius + BumperBout.EDGE_GRACE
end

--[[
	Marks ring-outs this step and decides the loser if both went out together:
	the one hit first loses; hit on the same step (or neither hit): the one farther from the
	middle loses; still equal: nobody (a shared result). Returns { out participants }, loser
	(nil = tie, or nobody out).
]]
function BumperBout.ringOuts(core, positions, radius: number)
	local out = {}
	for participant, fighter in core.Fighters do
		local position = positions[participant]
		if not fighter.Out and position and BumperBout.isOut(position, radius) then
			table.insert(out, participant)
		end
	end
	for _, participant in out do
		local fighter = core.Fighters[participant]
		fighter.Out = true
		fighter.OutStep = core.Step
	end
	if #out == 1 then
		return out, out[1]
	elseif #out == 2 then
		local a, b = out[1], out[2]
		local ha, hb = core.Fighters[a].HitStep or math.huge, core.Fighters[b].HitStep or math.huge
		if ha ~= hb then
			return out, if ha < hb then a else b
		end
		local da, db = flat(positions[a]).Magnitude, flat(positions[b]).Magnitude
		if math.abs(da - db) > BumperBout.CENTER_TIE then
			return out, if da > db then a else b
		end
		return out, nil
	end
	return out, nil
end

--[[
	Time limit: closest to the middle wins; within CENTER_TIE, more hits wins; otherwise nil
	(go to sudden death, or share the result if that's over too).
]]
function BumperBout.timeLimitWinner(core, positions)
	local a, b
	for participant, fighter in core.Fighters do
		if not fighter.Out then
			if a then
				b = participant
			else
				a = participant
			end
		end
	end
	if a and not b then
		return a
	end
	if not a then
		return nil
	end
	local da, db = flat(positions[a]).Magnitude, flat(positions[b]).Magnitude
	if math.abs(da - db) > BumperBout.CENTER_TIE then
		return if da < db then a else b
	end
	local ha, hb = core.Fighters[a].Hits, core.Fighters[b].Hits
	if ha ~= hb then
		return if ha > hb then a else b
	end
	return nil
end

-- Bot planning (pure) ---------------------------------------------------------------------

local function blend(pair, skill: number): number
	return pair[1] + (pair[2] - pair[1]) * skill
end

local function rotate(v: Vector3, degrees: number): Vector3
	local r = math.rad(degrees)
	local c, s = math.cos(r), math.sin(r)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

--[[
	One bot decision. All positions/velocities relative to the platform centre.
	  me, myVel, them, theirVel     where we both are and how we're moving
	  theirDash                     their lunge direction if they're lunging now, else nil
	  radius, radiusSoon            safe radius now and a moment from now (shrink-aware)
	  canDash                       my cooldown is ready
	Returns { MoveTo = Vector3, Dash = Vector3? (flat unit) }.
]]
function BumperBout.botPlan(state, skill: number, rng: Random)
	local bot = BumperBout.BOT
	local me, them = flat(state.Me), flat(state.Them)
	local radius = math.min(state.Radius, state.RadiusSoon or state.Radius)
	local margin = blend(bot.EdgeMargin, skill)
	local plan = { MoveTo = Vector3.zero, Dash = nil }

	-- 1. A lunge coming my way: sidestep (skill permitting), towards the middle side.
	if state.TheirDash then
		local toMe = me - them
		if toMe.Magnitude < bot.DashReach + 3 and toMe.Magnitude > 0.01 and toMe.Unit:Dot(flat(state.TheirDash)) > 0.7 then
			if rng:NextNumber() < blend(bot.Dodge, skill) then
				local side = Vector3.new(-state.TheirDash.Z, 0, state.TheirDash.X)
				if (me + side * 6).Magnitude > (me - side * 6).Magnitude then
					side = -side
				end
				plan.MoveTo = me + side * 8
				return plan
			end
		end
	end

	-- 2. Too close to the (upcoming) edge: head back in.
	if me.Magnitude > radius - margin then
		plan.MoveTo = Vector3.zero
		return plan
	end

	-- 3. Line up: stand on the middle side of the opponent, a dash-length away.
	local predicted = them + flat(state.TheirVel or Vector3.zero) * blend(bot.Lead, skill)
	local inward = if predicted.Magnitude > 0.01 then -predicted.Unit else Vector3.new(1, 0, 0)
	local spot = predicted + inward * 7
	if spot.Magnitude > radius - margin then
		spot = spot.Unit * math.max(0, radius - margin)
	end
	plan.MoveTo = spot

	-- 4. Lunge when they're in reach and the push sends them outward, and only if my own
	-- lunge can't carry me off the edge.
	if state.CanDash then
		local toThem = predicted - me
		local distance = toThem.Magnitude
		if distance > 0.5 and distance <= bot.DashReach then
			local dir = toThem.Unit
			local outward = if predicted.Magnitude > 0.01 then predicted.Unit else dir
			local lined = dir:Dot(outward) > 0.2 or predicted.Magnitude > me.Magnitude
			if rng:NextNumber() < blend(bot.Mistake, skill) then
				dir = rotate(dir, (rng:NextNumber() * 2 - 1) * bot.MistakeAngle) -- a poor angle
				lined = true -- ... or simply too eager
			end
			local landing = me + dir * (BumperBout.DASH_SPEED * BumperBout.DASH_DURATION)
			if lined and landing.Magnitude < radius - 1 then
				plan.Dash = dir
			end
		end
	end
	return plan
end

-- Round ---------------------------------------------------------------------------------------

local function now(): number
	return os.clock()
end

function BumperBout:_relative(participant): Vector3?
	local root = participant:GetRoot()
	if not root or not self.Top then
		return nil
	end
	return root.Position - self.Top
end

function BumperBout:_positions()
	local positions = {}
	for _, participant in self.Participants do
		positions[participant] = self:_relative(participant)
	end
	return positions
end

function BumperBout:_part(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in properties do
		part[key] = value
	end
	part.Parent = self.Arena.Folder
	return part
end

function BumperBout:_setRadius(radius: number)
	self.Radius = radius
	if self.ShownRadius and math.abs(self.ShownRadius - radius) < 0.1 then
		return
	end
	self.ShownRadius = radius
	local height = BumperBout.PLATFORM_HEIGHT
	-- A cylinder's axis is its X: turn it upright.
	local upright = CFrame.Angles(0, 0, math.rad(90))
	self.Platform.Size = Vector3.new(height, radius * 2, radius * 2)
	self.Platform.CFrame = self.Arena.Origin * CFrame.new(0, -height / 2, 0) * upright
	self.Rim.Size = Vector3.new(height * 0.6, radius * 2 + 1.2, radius * 2 + 1.2)
	self.Rim.CFrame = self.Arena.Origin * CFrame.new(0, -height * 0.5, 0) * upright
end

function BumperBout:Setup(arena, participants, round)
	self.Core = BumperBout.newCore(participants)
	self.Connections = {}
	self.Effects = {} -- [participant] = { Attachment, Dash = LinearVelocity, Push = LinearVelocity, Highlight }
	self.Owners = {}
	self.Rng = round.Rng or Random.new()
	self.Top = arena.Origin.Position
	self.Platform = self:_part({
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(235, 225, 200),
	})
	self.Rim = self:_part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 120, 60),
	})
	self:_setRadius(BumperBout.START_RADIUS)
	self:_part({
		Name = "CentreMark",
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		CanQuery = false,
		Size = Vector3.new(0.1, 3, 3),
		CFrame = arena.Origin * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 185, 150),
	})
	-- Invisible catch floor far below, so a ring-out lands somewhere instead of falling forever.
	self:_part({
		Name = "RecoveryFloor",
		Size = Vector3.new(160, 2, 160),
		CFrame = arena.Origin * CFrame.new(0, -30, 0),
		Transparency = 1,
		CanQuery = false,
	})
	local spawns = {}
	local spread = BumperBout.SPAWN_DISTANCE
	for index, participant in participants do
		local side = if index == 1 then -1 else 1
		local position = (arena.Origin * CFrame.new(side * spread, 4, 0)).Position
		spawns[index] = CFrame.lookAt(position, (arena.Origin * CFrame.new(0, 4, 0)).Position)
	end
	return spawns
end

-- Velocity constraint driving a body along the floor (gravity still acts).
function BumperBout:_drive(participant, kind: string, velocity: Vector3)
	local effects = self.Effects[participant]
	local root = participant:GetRoot()
	if not effects or not root or not root.Parent then
		return
	end
	if not effects.Attachment or not effects.Attachment.Parent then
		effects.Attachment = Instance.new("Attachment")
		effects.Attachment.Name = "BumperBoutAttachment"
		effects.Attachment.Parent = root
	end
	local constraint = effects[kind]
	if not constraint or not constraint.Parent then
		constraint = Instance.new("LinearVelocity")
		constraint.Name = "BumperBout" .. kind
		constraint.Attachment0 = effects.Attachment
		constraint.RelativeTo = Enum.ActuatorRelativeTo.World
		constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		constraint.PrimaryTangentAxis = Vector3.new(1, 0, 0)
		constraint.SecondaryTangentAxis = Vector3.new(0, 0, 1)
		constraint.MaxForce = 1e5
		constraint.Parent = root
		effects[kind] = constraint
	end
	constraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	constraint.Enabled = velocity.Magnitude > 0.05
end

function BumperBout:_highlight(participant, color: Color3?, fill: number?)
	local effects = self.Effects[participant]
	local character = participant:GetCharacter()
	if not effects or not character then
		return
	end
	local highlight = effects.Highlight
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "BumperBoutCue"
		highlight.Parent = character
		effects.Highlight = highlight
	end
	highlight.Enabled = color ~= nil
	if color then
		highlight.OutlineColor = color
		highlight.FillColor = color
		highlight.FillTransparency = fill or 1 -- outline only: cosmetics stay visible
	end
end

-- The one way a dash starts, for players and bots alike.
function BumperBout:RequestDash(participant, dir)
	if self.Round.Ended or not participant:IsAlive() then
		return false
	end
	local root = participant:GetRoot()
	local fallback = root and root.CFrame.LookVector
	local humanoid = participant:GetHumanoid()
	if dir == nil and humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		dir = humanoid.MoveDirection -- moving: lunge that way
	end
	local ok, _, chosen = BumperBout.validateDash(self.Core, participant, dir, fallback, now())
	if not ok then
		return false
	end
	self:_drive(participant, "Dash", chosen * BumperBout.DASH_SPEED)
	self:_highlight(participant, Color3.fromRGB(255, 230, 80), 1)
	if participant.Player then
		Net.minigameRemote():FireClient(participant.Player, { Type = "Cooldown", Seconds = BumperBout.DASH_COOLDOWN })
	end
	return true
end

function BumperBout:_knockOut(participant, why: string?)
	local root = participant:GetRoot()
	self:_drive(participant, "Dash", Vector3.zero)
	self:_drive(participant, "Push", Vector3.zero)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	self.Round:Eliminate(participant, true)
	self.Round:Toast(("💥 %s %s"):format(participant.Name, why or "fell off!"))
end

function BumperBout:_finish(winner, reason: string)
	self.Winner = winner
	self.Decided = true
	self.Core.Active = false
	self.Round:End(reason)
end

function BumperBout:_other(participant)
	for _, other in self.Participants do
		if other ~= participant then
			return other
		end
	end
end

-- Snap a player back if their body moved faster than anything in the game allows.
function BumperBout:_checkPlausible(participant, dt: number)
	if participant.IsBot or dt <= 0 then
		return
	end
	local root = participant:GetRoot()
	if not root then
		return
	end
	local last = self.LastGood[participant]
	local position = root.Position
	if last and (flat(position - last.Position)).Magnitude / dt > BumperBout.MAX_PLAUSIBLE_SPEED then
		root.CFrame = last.CFrame
		root.AssemblyLinearVelocity = Vector3.zero
		self.Snaps = (self.Snaps or 0) + 1
		return
	end
	self.LastGood[participant] = { Position = position, CFrame = root.CFrame }
end

function BumperBout:_step(dt: number)
	local round = self.Round
	if round.Ended or not self.Core.Active then
		return
	end
	local clock = now()
	local elapsed = clock - self.StartedAt
	local radius = BumperBout.radiusAt(if self.SuddenDeath then math.huge else elapsed)
	self:_setRadius(radius)

	-- Status warnings before anything changes under anyone.
	if not self.Warned and elapsed >= BumperBout.SHRINK_DELAY - BumperBout.SHRINK_WARNING then
		self.Warned = true
		round:SetStatus("⚠ Platform shrinking!")
	end
	if not self.WarnedFinal and elapsed >= BumperBout.SHRINK_DELAY + BumperBout.SHRINK_DURATION then
		self.WarnedFinal = true
		round:SetStatus("Final circle!")
	end

	-- Lunges and pushes play out.
	for _, participant in self.Participants do
		local fighter = self.Core.Fighters[participant]
		local dash = fighter.Dash
		if dash and clock > dash.Until and not dash.Ended then
			dash.Ended = true
			self:_drive(participant, "Dash", Vector3.zero)
			self:_highlight(participant, nil)
		end
		local push = self.Pushes[participant]
		if push then
			local speed = BumperBout.knockbackSpeed(push.Speed, clock - push.At)
			self:_drive(participant, "Push", push.Dir * speed)
			if speed <= 0 then
				self.Pushes[participant] = nil
				self:_highlight(participant, nil)
			end
		end
		self:_checkPlausible(participant, dt)
	end

	local positions = self:_positions()
	for _, hit in BumperBout.detectHits(self.Core, positions, clock) do
		self.Pushes[hit.Victim] = { Dir = hit.Dir, Speed = hit.Speed, At = clock }
		self:_drive(hit.Victim, "Push", hit.Dir * hit.Speed) -- push starts on the impact frame
		self:_drive(hit.Attacker, "Dash", Vector3.zero) -- the lunge stops on impact
		self:_drive(hit.Victim, "Dash", Vector3.zero) -- and so does any lunge the victim was in
		self:_highlight(hit.Victim, Color3.new(1, 1, 1), 0.7) -- brief impact flash
		round:ReportProgress(hit.Attacker, self.Core.Fighters[hit.Attacker].Hits)
		round:Toast(("💢 %s bumps %s!"):format(hit.Attacker.Name, hit.Victim.Name))
	end

	local out, loser = BumperBout.ringOuts(self.Core, positions, radius)
	if #out > 0 then
		for _, participant in out do
			self:_knockOut(participant)
		end
		if #out == 2 then
			self:_finish(if loser then self:_other(loser) else nil, "RingOut")
		else
			self:_finish(self:_other(out[1]), "RingOut")
		end
		return
	end

	-- Time limit: closest to the middle; then hits; then a short sudden death.
	if not self.SuddenDeath and elapsed >= BumperBout.ROUND_LIMIT then
		local winner = BumperBout.timeLimitWinner(self.Core, positions)
		if winner then
			round:Toast(("⏱ %s is closest to the middle!"):format(winner.Name))
			self:_finish(winner, "TimeLimit")
		else
			self.SuddenDeath = true
			self.SuddenDeathEnds = clock + BumperBout.SUDDEN_DEATH
			round:SetStatus("⚡ Sudden death!")
		end
	elseif self.SuddenDeath and clock >= self.SuddenDeathEnds then
		self:_finish(BumperBout.timeLimitWinner(self.Core, positions), "SuddenDeath")
	end
end

function BumperBout:Start()
	self.StartedAt = now()
	self.Core.Active = true
	self.Pushes = {}
	self.LastGood = {}
	-- The framework ends the round at Duration; we decide at ROUND_LIMIT ourselves and may
	-- need sudden death, so its hard stop is pushed back by that much.
	if self.Round.EndsAt then
		self.Round.EndsAt += BumperBout.SUDDEN_DEATH + 1
	end
	for _, participant in self.Participants do
		self.Effects[participant] = {}
		self.Round:ReportProgress(participant, 0)
		-- Pin who simulates each body for the whole bout: the player for their own, the server
		-- for bots, so ownership can't flip back and forth when they get close.
		local root = participant:GetRoot()
		if root and not root.Anchored then
			pcall(function()
				root:SetNetworkOwner(participant.Player)
			end)
			table.insert(self.Owners, root)
		end
	end
	self.Round:SetStatus("Bump your rival off! DASH to lunge")
	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	)
end

function BumperBout:OnInput(participant, action)
	if action == "Dash" then
		local memory = participant.IsBot and participant.Bot and participant.Bot.Memory
		self:RequestDash(participant, memory and memory.Aim or nil)
	end
end

-- From client/Minigames/BumperBout: { Type = "Dash", X, Z } (the stick/keys direction).
function BumperBout:OnClientMessage(participant, message)
	if participant.IsBot or type(message) ~= "table" or message.Type ~= "Dash" then
		return
	end
	if not finite(message.X) or not finite(message.Z) then
		return
	end
	self:RequestDash(participant, { X = message.X, Z = message.Z })
end

function BumperBout:OnParticipantLost(participant, reason)
	local fighter = self.Core.Fighters[participant]
	if not fighter or self.Decided then
		return
	end
	fighter.Out = true
	fighter.OutStep = self.Core.Step
	self.Round:Toast(("💥 %s %s"):format(participant.Name, if reason == "Left" then "left the duel" else "is out!"))
	self:_finish(self:_other(participant), "Lost")
end

function BumperBout:UpdateBot(bot, _dt)
	local me = bot.Participant
	local fighter = self.Core.Fighters[me]
	if not fighter or fighter.Out or not self.Core.Active then
		return
	end
	local memory = bot.Memory
	local clock = now()
	if clock < (memory.NextThink or 0) then
		return
	end
	memory.NextThink = clock + blend(BumperBout.BOT.Reaction, bot.Skill or 0.5) * self.Rng:NextNumber(0.8, 1.2)
	local them = self:_other(me)
	local myPos, theirPos = self:_relative(me), them and self:_relative(them)
	if not myPos or not theirPos then
		return
	end
	local theirFighter = self.Core.Fighters[them]
	local theirDash = theirFighter.Dash
	local myRoot, theirRoot = me:GetRoot(), them:GetRoot()
	local elapsed = clock - self.StartedAt
	local plan = BumperBout.botPlan({
		Me = myPos,
		MyVel = myRoot and myRoot.AssemblyLinearVelocity or Vector3.zero,
		Them = theirPos,
		TheirVel = theirRoot and theirRoot.AssemblyLinearVelocity or Vector3.zero,
		TheirDash = if theirDash and clock <= theirDash.Until then theirDash.Dir else nil,
		Radius = self.Radius,
		RadiusSoon = BumperBout.radiusAt(if self.SuddenDeath then math.huge else elapsed + 1.5),
		CanDash = clock - fighter.LastDashAt >= BumperBout.DASH_COOLDOWN,
	}, bot.Skill or 0.5, self.Rng)
	bot:MoveTo(self.Top + plan.MoveTo)
	if plan.Dash then
		memory.Aim = plan.Dash
		bot:Input("Dash")
		memory.Aim = nil
	end
end

function BumperBout:GetResults()
	if self.Decided and self.Winner then
		return ResultsUtil.fromScores(self.Participants, function(participant)
			return if participant == self.Winner then 1 else 0
		end)
	end
	-- Undecided (shared result): everyone ties.
	return ResultsUtil.fromScores(self.Participants, function()
		return 0
	end)
end

function BumperBout:Cleanup()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	if self.Core then
		self.Core.Active = false
	end
	for _, effects in self.Effects or {} do
		for _, key in { "Dash", "Push", "Attachment", "Highlight" } do
			if effects[key] then
				effects[key]:Destroy()
			end
		end
	end
	self.Effects = {}
	for _, root in self.Owners or {} do
		if root.Parent then
			pcall(function()
				root:SetNetworkOwnershipAuto()
			end)
		end
	end
	self.Owners = {}
	-- Platform, rim and catch floor live in arena.Folder, which the framework destroys.
end

BumperBout.blend = blend

return BumperBout
