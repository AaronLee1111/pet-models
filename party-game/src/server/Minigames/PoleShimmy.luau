--[[
	Pole Shimmy (FFA, race)
	Four poles side by side. Alternate left and right (A / D, or the two on-screen buttons) to
	shimmy up yours. Only alternating counts, a steady rhythm climbs faster, and pausing lets
	your momentum fade. First to ring the bell wins; everyone else ranks by height.

	Who decides what (so it is fair and smooth on a laggy connection):
	  * The climbing rules live in PartyShared.PoleShimmySim, shared with the client.
	  * Each player's client stamps every press with its own race clock and sends it here
	    (client/Minigames/PoleShimmy). The server replays those presses through the rules and
	    its result is the only one that counts: heights, finish times, placements.
	    Using the client's timestamps means network jitter can't ruin your rhythm; the server
	    still refuses timestamps from the future, out-of-order presses and too-fast tapping.
	  * Bots press on the server's own clock.
	  * ~20 times a second the server broadcasts every climber's height. Clients draw other
	    climbers by interpolating between those, and their own climber from local prediction
	    that is nudged back onto the server's numbers.

	Climbing tuning is at the top of PartyShared.PoleShimmySim. Round, network, anti-cheat
	and bot tuning is below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local Net = require(ReplicatedStorage.PartyShared.Net)
local Sim = require(ReplicatedStorage.PartyShared.PoleShimmySim)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local PoleShimmy = {}

-- Tuning ----------------------------------------------------------------------------------

local ROUND_DURATION = 25
local POLE_SPACING = 7 -- studs between neighbouring poles
local POLE_RADIUS = 0.8
local CLING_OFFSET = 1.6 -- how far in front of the pole (towards the camera) climbers hang

-- Networking
local SNAPSHOT_RATE = 20 -- height snapshots sent to clients per second
local FALLBACK_PLACE_RATE = 2 -- times per second the server itself moves the bodies

-- Anti-cheat
local CLOCK_SLACK = 0.3 -- seconds a client's race clock may run ahead of the server's
local MAX_PRESSES_PER_SECOND = 14 -- presses arriving faster than this (per player) are dropped
local DEFAULT_DELAY = 0.3 -- assumed client delay until its first press tells us better
local DELAY_MARGIN = 0.05 -- extra seconds the server waits so presses arrive before they're due
local MAX_DELAY = 1.0 -- delays above this are treated as this (very laggy clients just lag)

-- Bots: seconds between presses { sloppiest, sharpest }, wobble per press, stumbles
local BOT_GAP = { 0.36, 0.21 }
local BOT_WOBBLE = { 0.3, 0.06 } -- random +/- share of the gap on each press
local BOT_STUMBLE_CHANCE = { 0.07, 0.015 } -- per press
local BOT_STUMBLE_PAUSE = { 0.5, 1.3 } -- seconds a stumble costs (or a wasted same-hand press)

PoleShimmy.Info = {
	Name = "Pole Shimmy",
	Description = "Alternate LEFT and RIGHT to shimmy up your pole! Keep a steady rhythm to climb faster. First to ring the bell wins 🔔",
	Duration = ROUND_DURATION,
	Layout = Config.Layouts.FFA,
	Camera = { Mode = "SideView", Distance = 26, Height = 3, Smooth = 7, FollowY = true },
	Controls = {
		Move = false,
		Jump = false,
		Actions = {
			{ Action = "Left", Label = "LEFT", Key = "A", Gamepad = "ButtonX", Side = "Left" },
			{ Action = "Right", Label = "RIGHT", Key = "D", Gamepad = "ButtonB" },
		},
	},
	ProgressLabel = "Height",
	ClientModule = "PoleShimmy", -- client/Minigames/PoleShimmy: press timing + smooth drawing
}

local function lerp(range, alpha: number): number
	return range[1] + (range[2] - range[1]) * alpha
end

-- Setup -----------------------------------------------------------------------------------

function PoleShimmy:_part(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in properties do
		part[key] = value
	end
	part.Parent = self.Arena.Folder
	return part
end

-- Base CFrame of pole `index` (on the ground, facing the same way as the arena).
function PoleShimmy:_poleBase(index: number): CFrame
	local offset = (index - (#self.Participants + 1) / 2) * POLE_SPACING
	return self.Arena.Origin * CFrame.new(offset, 0, 0)
end

function PoleShimmy:Setup(arena, participants, _round)
	self.Connections = {}
	self.Climbers = {}
	self.Anchored = {}
	self.FinishCount = 0
	local top = Sim.POLE_HEIGHT

	self:_part({
		Name = "Ground",
		Size = Vector3.new(POLE_SPACING * (#participants + 1), 1, 14),
		CFrame = arena.Origin * CFrame.new(0, -0.5, 0),
		Color = Color3.fromRGB(255, 170, 210),
		CanCollide = true,
	})

	local colors = {
		Color3.fromRGB(255, 220, 60),
		Color3.fromRGB(255, 90, 140),
		Color3.fromRGB(90, 220, 255),
		Color3.fromRGB(120, 255, 140),
	}
	local spawns = {}
	for index, participant in participants do
		local base = self:_poleBase(index)
		local color = colors[(index - 1) % #colors + 1]
		self:_part({
			Name = "Pole",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(top + 6, POLE_RADIUS * 2, POLE_RADIUS * 2),
			CFrame = base * CFrame.new(0, (top + 6) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(220, 225, 235),
		})
		-- Height marks every 10 studs, in the pole's colour.
		for mark = 10, top - 1, 10 do
			self:_part({
				Name = "Mark",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, POLE_RADIUS * 2 + 0.3, POLE_RADIUS * 2 + 0.3),
				CFrame = base * CFrame.new(0, mark + 3, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Neon,
				Color = color,
			})
		end
		self:_part({
			Name = "Bell",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 2.6, 2.6),
			CFrame = base * CFrame.new(0, top + 7.5, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 215, 0),
		})

		self.Climbers[participant] = {
			Sim = Sim.newClimber(),
			Index = index,
			IsBot = participant.IsBot,
			RideHeight = 3.5,
			-- Players: how far behind the server their race clock runs (measured from presses).
			Delay = DEFAULT_DELAY,
			DelaySamples = {},
			LastPressT = -math.huge,
			Arrivals = {},
			Rejected = 0,
			-- Bots
			NextPressAt = nil,
			NextKey = "Left",
		}
		spawns[index] = base * CFrame.new(0, 4, CLING_OFFSET)
	end
	return spawns
end

-- Climbing --------------------------------------------------------------------------------------

function PoleShimmy:_heightText(climber): string
	if climber.Sim.FinishedAt then
		return ("🏁 %.1fs"):format(climber.Sim.FinishedAt)
	end
	return ("%d%%"):format(math.clamp(climber.Sim.Height / Sim.POLE_HEIGHT, 0, 0.99) * 100)
end

-- Race time this climber's state should be at right now.
function PoleShimmy:_clockFor(climber): number
	local elapsed = os.clock() - self.StartedAt
	return if climber.IsBot then elapsed else math.max(0, elapsed - climber.Delay)
end

function PoleShimmy:_place(participant, climber)
	local character = participant:GetCharacter()
	if character then
		character:PivotTo(
			self:_poleBase(climber.Index) * CFrame.new(0, climber.RideHeight + climber.Sim.Height, CLING_OFFSET)
		)
	end
end

function PoleShimmy:_checkFinish(participant, climber)
	if climber.Sim.FinishedAt and not climber.Finished then
		climber.Finished = true
		self.FinishCount += 1
		self.Round:Toast(("🔔 %s rang the bell in %.1fs"):format(participant.Name, climber.Sim.FinishedAt))
		self.Round:ReportProgress(participant, self:_heightText(climber))
	end
end

-- A press from a player's client, stamped with that client's race clock.
function PoleShimmy:_playerPress(participant, climber, key, t)
	if (key ~= "Left" and key ~= "Right") or type(t) ~= "number" or t ~= t then
		return
	end
	local elapsed = os.clock() - self.StartedAt
	-- Rate limit by arrival: autoclickers and floods get dropped before anything else.
	local now = os.clock()
	local arrivals = climber.Arrivals
	while arrivals[1] and now - arrivals[1] > 1 do
		table.remove(arrivals, 1)
	end
	if #arrivals >= MAX_PRESSES_PER_SECOND then
		climber.Rejected += 1
		return
	end
	table.insert(arrivals, now)
	-- No pressing in the future, and no rewriting the past.
	if t > elapsed + CLOCK_SLACK or t < climber.LastPressT then
		climber.Rejected += 1
		return
	end
	climber.LastPressT = t

	-- The server works this climber out a little behind real time, far enough back that
	-- presses normally arrive *before* the moment they were pressed comes up (the slowest
	-- recent arrival, plus a margin). Then every press lands at its own timestamp and the
	-- server's numbers match what the player's own client predicted.
	table.insert(climber.DelaySamples, elapsed - t)
	if #climber.DelaySamples > 20 then
		table.remove(climber.DelaySamples, 1)
	end
	local delay = 0
	for _, sample in climber.DelaySamples do
		delay = math.max(delay, sample)
	end
	climber.Delay = math.clamp(delay + DELAY_MARGIN, 0, MAX_DELAY)

	-- A press can't land before the state we have already worked out (a late packet).
	Sim.press(climber.Sim, key, math.max(t, climber.Sim.Time))
	self:_checkFinish(participant, climber)
end

-- Bots: a press every so often, with wobble and the odd stumble.
function PoleShimmy:_updateBot(participant, climber, elapsed: number)
	local bot = participant.Bot
	if climber.Sim.FinishedAt or not bot then
		return
	end
	local skill = bot.Skill
	local gap = lerp(BOT_GAP, skill)
	if not climber.NextPressAt then
		-- Everyone reacts to GO at a slightly different moment.
		climber.NextPressAt = elapsed + 0.15 + math.random() * (0.5 - skill * 0.35)
	end
	if elapsed < climber.NextPressAt then
		return
	end
	local key = climber.NextKey
	if math.random() < lerp(BOT_STUMBLE_CHANCE, skill) then
		-- Stumble: either a fumbled same-hand press, or a moment to regrip.
		if math.random() < 0.5 then
			key = if key == "Left" then "Right" else "Left"
		end
		climber.NextPressAt = elapsed + lerp(BOT_STUMBLE_PAUSE, math.random())
	else
		local wobble = lerp(BOT_WOBBLE, skill)
		climber.NextPressAt = elapsed + gap * (1 + (math.random() * 2 - 1) * wobble)
	end
	climber.NextKey = if key == "Left" then "Right" else "Left"
	bot:Input(key) -- same validated path as player inputs; arrives in OnInput
end

-- Interface -----------------------------------------------------------------------------

function PoleShimmy:Start()
	local round = self.Round
	self.StartedAt = os.clock()
	local nextSnapshot, nextPlace, nextReport = 0, 0, 0

	local describe = {}
	for _, participant in self.Participants do
		local climber = self.Climbers[participant]
		local character = participant:GetCharacter()
		local root = participant:GetRoot()
		if character and root then
			local base = self:_poleBase(climber.Index)
			climber.RideHeight = base:PointToObjectSpace(character:GetPivot().Position).Y
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			table.insert(self.Anchored, root)
		end
		table.insert(describe, {
			Id = participant.Id,
			Character = character,
			Base = self:_poleBase(climber.Index) * CFrame.new(0, 0, CLING_OFFSET),
			RideHeight = climber.RideHeight,
		})
	end
	Net.minigameRemote():FireAllClients({ Type = "Setup", Climbers = describe })
	round:SetStatus("Alternate LEFT + RIGHT!")

	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function()
			if round.Ended then
				return
			end
			local clock = os.clock()
			local elapsed = clock - self.StartedAt
			for _, participant in round:GetAlive() do
				local climber = self.Climbers[participant]
				if climber.IsBot then
					self:_updateBot(participant, climber, elapsed)
				end
				-- A player's climber waits for their first press, so that press (and the
				-- delay it reveals) decides where their timeline starts.
				if climber.IsBot or climber.LastPressT > -math.huge then
					Sim.advance(climber.Sim, self:_clockFor(climber))
				end
				self:_checkFinish(participant, climber)
			end

			if clock >= nextSnapshot then
				nextSnapshot = clock + 1 / SNAPSHOT_RATE
				local list = {}
				for _, participant in self.Participants do
					local state = self.Climbers[participant].Sim
					table.insert(list, { participant.Id, state.Height, state.Time, state.LastKey == "Left" })
				end
				Net.minigameFastRemote():FireAllClients({ T = clock, R = list })
			end
			if clock >= nextPlace then
				nextPlace = clock + 1 / FALLBACK_PLACE_RATE
				for _, participant in round:GetAlive() do
					self:_place(participant, self.Climbers[participant])
				end
			end
			if clock >= nextReport then
				nextReport = clock + 0.1
				for _, participant in self.Participants do
					round:ReportProgress(participant, self:_heightText(self.Climbers[participant]))
				end
			end
			if self.FinishCount >= #round:GetAlive() then
				round:End("Finish")
			end
		end)
	)
end

-- Bot presses (and a player's, if their client code isn't running) arrive here, on server time.
function PoleShimmy:OnInput(participant, action)
	local climber = self.Climbers[participant]
	if not climber or (action ~= "Left" and action ~= "Right") then
		return
	end
	if climber.IsBot then
		Sim.press(climber.Sim, action, os.clock() - self.StartedAt)
		self:_checkFinish(participant, climber)
	else
		self:_playerPress(participant, climber, action, self:_clockFor(climber))
	end
end

-- Timestamped presses from client/Minigames/PoleShimmy.
function PoleShimmy:OnClientMessage(participant, message)
	local climber = self.Climbers[participant]
	if climber and not climber.IsBot and type(message) == "table" and message.Type == "Press" then
		self:_playerPress(participant, climber, message.Key, message.T)
	end
end

function PoleShimmy:OnRoundEnding(_reason)
	for _, participant in self.Participants do
		local climber = self.Climbers[participant]
		self:_place(participant, climber)
		if climber.Rejected > 0 then
			print(("[PoleShimmy] %s: %d press(es) rejected"):format(participant.Name, climber.Rejected))
		end
	end
end

function PoleShimmy:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		local state = self.Climbers[participant].Sim
		-- Bell-ringers beat everyone still climbing; earlier = better.
		return if state.FinishedAt then 1e6 - state.FinishedAt else state.Height
	end)
end

function PoleShimmy:Cleanup()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, root in self.Anchored do
		if root.Parent then
			root.Anchored = false
		end
	end
end

return PoleShimmy
