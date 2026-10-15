--[[
	Pole Shimmy (client side)
	  * Stamps each LEFT / RIGHT press with this client's race clock and sends it to the server,
	    which replays it through the shared rules (PartyShared.PoleShimmySim) and decides
	    everything that counts.
	  * Meanwhile runs the same rules locally so your climber moves on the very next frame,
	    and nudges it back onto the server's heights whenever they disagree (a dropped press,
	    say).
	  * Draws everyone else a moment in the past, gliding between the server's snapshots.

	Main starts and stops this module (Info.ClientModule = "PoleShimmy").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PartyShared")
local Net = require(Shared:WaitForChild("Net"))
local Sim = require(Shared:WaitForChild("PoleShimmySim"))

local PoleShimmyClient = {}

-- Tuning ----------------------------------------------------------------------------------

local INTERPOLATION_DELAY = 0.15 -- seconds in the past other climbers are drawn
local MAX_EXTRAPOLATION = 0.25 -- seconds to keep a climber moving when snapshots stop
local CORRECTION_RATE = 0.5 -- share of a disagreement with the server fixed per snapshot ...
local MAX_CORRECTION = 0.25 -- ... but never more than this many studs at once, so it can't jump
local SWAY = 0.12 -- radians of side-to-side lean per hand
local SNAPSHOT_HISTORY = 40
local BIND_NAME = "PartyPoleShimmyClient"

local myId = "player_" .. Players.LocalPlayer.UserId

local running = false
local connections = {}
local bodies = {} -- [id] = { Character, Base, RideHeight }
local mine = nil -- my climber (local prediction), nil if I'm only watching
local raceTime = 0
local history = {} -- my predicted { T = race time, H = height }, oldest first
local snapshots = {} -- { T = server clock, R = { [id] = { H, Time, Left } } }
local playback = nil
local lastStepAt = 0

local function place(body, height: number, leftHand: boolean?)
	local character = body.Character
	if character and character.Parent then
		local sway = if leftHand == nil then 0 elseif leftHand then SWAY else -SWAY
		character:PivotTo(body.Base * CFrame.new(0, body.RideHeight + height, 0) * CFrame.Angles(0, 0, sway))
	end
end

-- Height of climber `id` at server time `t`, blending the snapshots around it.
local function sample(id: string, t: number)
	local before, after
	for index = #snapshots, 1, -1 do
		local snapshot = snapshots[index]
		if snapshot.R[id] then
			if snapshot.T <= t then
				before = snapshot
				break
			end
			after = snapshot
		end
	end
	if before and after then
		local a, b = before.R[id], after.R[id]
		local alpha = (t - before.T) / math.max(after.T - before.T, 1e-3)
		return a.H + (b.H - a.H) * alpha, if alpha < 0.5 then a.Left else b.Left
	end
	if before then
		-- No newer news: keep going at the last known climbing speed for a moment.
		local previous
		for index = #snapshots, 1, -1 do
			if snapshots[index] ~= before and snapshots[index].T < before.T and snapshots[index].R[id] then
				previous = snapshots[index]
				break
			end
		end
		local state = before.R[id]
		if previous then
			local speed = (state.H - previous.R[id].H) / math.max(before.T - previous.T, 1e-3)
			return math.min(Sim.POLE_HEIGHT, state.H + speed * math.min(t - before.T, MAX_EXTRAPOLATION)), state.Left
		end
		return state.H, state.Left
	end
	if after then
		return after.R[id].H, after.R[id].Left
	end
	return nil
end

-- My predicted height at race time `t` (from the recent history).
local function predictedAt(t: number): number?
	for index = #history, 2, -1 do
		local a, b = history[index - 1], history[index]
		if a.T <= t and t <= b.T then
			return a.H + (b.H - a.H) * (t - a.T) / math.max(b.T - a.T, 1e-4)
		end
	end
	return nil
end

local function step(dt: number)
	if not running or not next(bodies) then
		return
	end
	dt = math.min(dt, 0.1)
	lastStepAt = os.clock()

	-- Everyone else: a steady clock trailing the newest snapshot.
	local newest = snapshots[#snapshots]
	if newest then
		local target = newest.T - INTERPOLATION_DELAY
		if not playback or math.abs(target - playback) > 0.5 then
			playback = target
		else
			playback += dt
			playback += (target - playback) * math.min(1, dt * 2)
		end
		for id, body in bodies do
			if not (mine and id == myId) then
				local height, leftHand = sample(id, playback)
				if height then
					place(body, height, leftHand)
				end
			end
		end
	end

	-- Me: predicted right here.
	if mine then
		raceTime += dt
		Sim.advance(mine, raceTime)
		table.insert(history, { T = raceTime, H = mine.Height })
		while history[1] and raceTime - history[1].T > 3 do
			table.remove(history, 1)
		end
		local body = bodies[myId]
		if body then
			place(body, mine.Height, if mine.LastKey then mine.LastKey == "Left" else nil)
		end
	end
end

local function onSetup(message)
	bodies = {}
	mine = nil
	for _, climber in message.Climbers do
		bodies[climber.Id] = { Character = climber.Character, Base = climber.Base, RideHeight = climber.RideHeight }
		if climber.Id == myId then
			mine = Sim.newClimber()
		end
	end
	raceTime = 0
	history = {}
end

local function onSnapshot(message)
	if type(message) ~= "table" or type(message.T) ~= "number" or type(message.R) ~= "table" then
		return
	end
	local newest = snapshots[#snapshots]
	if newest and message.T <= newest.T then
		return -- out of order
	end
	local climbers = {}
	for _, entry in message.R do
		climbers[entry[1]] = { H = entry[2], Time = entry[3], Left = entry[4] }
	end
	table.insert(snapshots, { T = message.T, R = climbers })
	if #snapshots > SNAPSHOT_HISTORY then
		table.remove(snapshots, 1)
	end

	-- Keep my prediction honest: compare with what the server had for the same race time.
	local official = mine and climbers[myId]
	if official and not mine.FinishedAt then
		local predicted = predictedAt(official.Time)
		if predicted then
			local error = official.H - predicted
			if math.abs(error) > 0.05 then
				local nudge = math.clamp(error * CORRECTION_RATE, -MAX_CORRECTION, MAX_CORRECTION)
				mine.Height = math.clamp(mine.Height + nudge, 0, Sim.POLE_HEIGHT)
			end
		end
	end
end

-- Interface (called by Main) -------------------------------------------------------------------

function PoleShimmyClient.start()
	PoleShimmyClient.stop()
	running = true
	bodies = {}
	mine = nil
	snapshots = {}
	playback = nil
	table.insert(
		connections,
		Net.minigameRemote().OnClientEvent:Connect(function(message)
			if type(message) == "table" and message.Type == "Setup" then
				onSetup(message)
			end
		end)
	)
	table.insert(connections, Net.minigameFastRemote().OnClientEvent:Connect(onSnapshot))
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 5, step)
	-- Keep the clock running even while the window isn't being drawn.
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			if os.clock() - lastStepAt > 0.25 then
				step(dt)
			end
		end)
	)
end

function PoleShimmyClient.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	bodies = {}
	mine = nil
	snapshots = {}
	history = {}
end

-- LEFT / RIGHT pressed. Returns true: handled here (sent with a timestamp below).
function PoleShimmyClient.onAction(action: string): boolean
	if action ~= "Left" and action ~= "Right" then
		return false
	end
	if mine then
		Sim.press(mine, action, raceTime)
		Net.minigameRemote():FireServer({ Type = "Press", Key = action, T = raceTime })
	end
	return true
end

return PoleShimmyClient
