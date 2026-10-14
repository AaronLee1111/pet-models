--[[
	Ice Dash (client side)
	Keeps the race smooth whatever the connection is like:

	  * Your own racer is simulated right here with the shared rules (PartyShared.IceDashSim),
	    so steering responds on the very next frame. Your state is reported to the server
	    ~20 times a second; the server checks it and can snap you back ("Correct").
	  * Every other racer is drawn a moment in the past, gliding between the snapshots the
	    server broadcasts, so they move every frame even though news of them arrives in bursts.

	The server anchors every body for the race; this module places them each frame, just
	before the camera updates. Nothing here decides who wins: the server does.

	Main starts and stops this module (Info.ClientModule = "IceDash").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PartyShared")
local Net = require(Shared:WaitForChild("Net"))
local Sim = require(Shared:WaitForChild("IceDashSim"))

local IceDashClient = {}

-- Tuning ----------------------------------------------------------------------------------

local REPORT_RATE = 20 -- state reports sent to the server per second
local INTERPOLATION_DELAY = 0.15 -- seconds in the past other racers are drawn (3 snapshots' worth)
local MAX_EXTRAPOLATION = 0.25 -- seconds to keep a racer coasting when snapshots stop arriving
local SNAPSHOT_HISTORY = 40
local BIND_NAME = "PartyIceDashClient"

local player = Players.LocalPlayer
local myId = "player_" .. player.UserId

local running = false
local connections = {}
local layout = nil
local frame = CFrame.new()
local bodies = {} -- [id] = { Character, RideHeight, Lane }
local mine = nil -- my racer (IceDashSim state), nil if I'm only watching
local left, right = false, false
local raceTime = 0 -- seconds my racer has been simulated; sent with every report
local reportTimer = 0
local snapshots = {} -- oldest first: { T = server clock, R = { [id] = { X, S, VX, VS, Fall } } }
local playback = nil -- server-clock time currently being drawn for other racers
local lastStepAt = 0 -- os.clock() of the last simulation step

local function trackCFrame(x: number, y: number, s: number): CFrame
	return frame * CFrame.new(x, y, -s)
end

local function place(body, x: number, s: number, vx: number, drop: number)
	local character = body.Character
	if character and character.Parent then
		local lean = math.clamp(vx / Sim.MAX_SIDE_SPEED, -1, 1) * 0.3
		character:PivotTo(trackCFrame(x, body.RideHeight - drop, s) * CFrame.Angles(0, 0, -lean))
	end
end

-- Where a racer was at server time `t`, blending the two snapshots around it.
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
		-- A respawn is a teleport, not something to glide through.
		if math.abs(b.S - a.S) > 25 then
			return b
		end
		local alpha = (t - before.T) / math.max(after.T - before.T, 1e-3)
		return {
			X = a.X + (b.X - a.X) * alpha,
			S = a.S + (b.S - a.S) * alpha,
			VX = a.VX + (b.VX - a.VX) * alpha,
			VS = b.VS,
			Fall = if a.Fall >= 0 and b.Fall >= 0 then a.Fall + (b.Fall - a.Fall) * alpha else b.Fall,
		}
	end
	if before then
		-- Ran out of news: coast on the last known velocity for a moment.
		local state = before.R[id]
		local ahead = math.min(t - before.T, MAX_EXTRAPOLATION)
		if state.Fall >= 0 then
			return state
		end
		return { X = state.X + state.VX * ahead, S = state.S + state.VS * ahead, VX = state.VX, VS = state.VS, Fall = -1 }
	end
	return after and after.R[id]
end

local function fallDrop(fallTime: number): number
	return if fallTime >= 0 then math.min(18, 40 * fallTime * fallTime) else 0
end

local function step(dt: number)
	if not running or not layout then
		return
	end
	dt = math.min(dt, 0.1)
	lastStepAt = os.clock()

	-- Other racers: a steady clock that trails the newest snapshot by INTERPOLATION_DELAY.
	local newest = snapshots[#snapshots]
	local others = {}
	if newest then
		local target = newest.T - INTERPOLATION_DELAY
		if not playback or math.abs(target - playback) > 0.5 then
			playback = target
		else
			playback += dt
			playback += (target - playback) * math.min(1, dt * 2) -- ease out any drift
		end
		for id, body in bodies do
			if not (mine and id == myId) then
				local state = sample(id, playback)
				if state then
					place(body, state.X, state.S, state.VX, fallDrop(state.Fall))
					if state.Fall < 0 then
						table.insert(others, { X = state.X, S = state.S, VX = state.VX, VS = state.VS, State = "Racing" })
					end
				end
			end
		end
	end

	-- My racer: simulated here, right now.
	if mine then
		local steer = (if right then 1 else 0) - (if left then 1 else 0)
		-- Small fixed-size steps keep fast frames and slow frames behaving the same.
		local remaining = dt
		while remaining > 1e-4 do
			local slice = math.min(remaining, 1 / 60)
			Sim.step(layout, mine, steer, slice)
			remaining -= slice
		end
		for _, other in others do
			Sim.collide(mine, other, true, false)
		end
		raceTime += dt
		local body = bodies[myId]
		if body then
			place(body, mine.X, mine.S, mine.VX, Sim.fallDrop(mine))
		end

		reportTimer += dt
		if reportTimer >= 1 / REPORT_RATE then
			reportTimer = 0
			Net.minigameFastRemote():FireServer({ T = raceTime, X = mine.X, S = mine.S, VX = mine.VX, VS = mine.VS })
		end
	end
end

local function onSetup(message)
	layout = message.Layout
	frame = message.Frame
	bodies = {}
	mine = nil
	for _, racer in message.Racers do
		bodies[racer.Id] = { Character = racer.Character, RideHeight = racer.RideHeight, Lane = racer.Lane }
		if racer.Id == myId then
			mine = Sim.newRacer(racer.Lane)
		end
	end
	raceTime = 0
	reportTimer = 0
end

local function onCorrect(message)
	if not mine then
		return
	end
	mine.X, mine.S, mine.VX, mine.VS = message.X, message.S, message.VX, message.VS
	mine.Checkpoint = message.Checkpoint
	if message.State == "Racing" and mine.State == "Falling" then
		mine.State = "Racing"
		mine.FallTime = 0
	end
end

local function onSnapshot(message)
	if type(message) ~= "table" or type(message.T) ~= "number" or type(message.R) ~= "table" then
		return
	end
	-- The fast channel can deliver out of order: ignore anything older than what we have.
	local newest = snapshots[#snapshots]
	if newest and message.T <= newest.T then
		return
	end
	local racers = {}
	for _, entry in message.R do
		racers[entry[1]] = { X = entry[2], S = entry[3], VX = entry[4], VS = entry[5], Fall = entry[6] }
	end
	table.insert(snapshots, { T = message.T, R = racers })
	if #snapshots > SNAPSHOT_HISTORY then
		table.remove(snapshots, 1)
	end
end

-- Interface (called by Main) -------------------------------------------------------------------

function IceDashClient.start()
	IceDashClient.stop()
	running = true
	layout = nil
	mine = nil
	left, right = false, false
	snapshots = {}
	playback = nil
	table.insert(
		connections,
		Net.minigameRemote().OnClientEvent:Connect(function(message)
			if type(message) ~= "table" then
				return
			end
			if message.Type == "Setup" then
				onSetup(message)
			elseif message.Type == "Correct" then
				onCorrect(message)
			end
		end)
	)
	table.insert(connections, Net.minigameFastRemote().OnClientEvent:Connect(onSnapshot))
	-- Just before the camera, so the chase cam follows this frame's position.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 5, step)
	-- Render steps stop when the window isn't being drawn (minimised, display asleep). Keep
	-- the racer going from Heartbeat in that case, or it would sit still until you came back.
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			if os.clock() - lastStepAt > 0.25 then
				step(dt)
			end
		end)
	)
end

function IceDashClient.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	layout = nil
	mine = nil
	bodies = {}
	snapshots = {}
end

-- A steer button went down or up. Returns true: handled here, nothing to send to the server.
function IceDashClient.onAction(action: string): boolean
	if action == "Left" then
		left = true
	elseif action == "LeftStop" then
		left = false
	elseif action == "Right" then
		right = true
	elseif action == "RightStop" then
		right = false
	end
	return true
end

return IceDashClient
