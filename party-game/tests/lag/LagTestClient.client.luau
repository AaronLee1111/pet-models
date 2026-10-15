--[[
	Lag test (client half). Measures what this client actually draws during an Ice Dash round:
	  fps          frames drawn per second while measuring (Studio throttles background windows)
	  frozen       share of frames in which a racer did not move forward at all
	  speedJitter  frame-to-frame speed wobble around a 15-frame average (studs/s); 0 = glassy
	  maxStep      biggest single-frame move (studs); teleports = respawns/snaps, counted apart
	  inputLatencyMs      time from a scripted steer press to this client's racer moving sideways
	  remoteRoundTripMs   client -> server -> client time for an ordinary remote
	"self" is this client's own racer, "otherPlayer" the other human, "bot" one of the bots.
	Works for Ice Dash (scripted steering) and Pole Shimmy (scripted steady climbing).
]]
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local me = game.Players.LocalPlayer
local remotes = RS:WaitForChild("PartyRemotes")
local state, input = remotes:WaitForChild("PartyState"), remotes:WaitForChild("PartyInput")
local report = RS:WaitForChild("LagReport")
local phase, startedAt, chars = nil, nil, {}
local tracks = {}
local presses = {}
local sent = false
local pingMs = "none"
local minigame = nil -- "Ice Dash" | "Pole Shimmy"
local function clientModule()
	local folder = script.Parent:FindFirstChild("PartyClient")
	local games = folder and folder:FindFirstChild("Minigames")
	local m = games and games:FindFirstChild(if minigame == "Pole Shimmy" then "PoleShimmy" else "IceDash")
	if m then local ok, mod = pcall(require, m) if ok then return mod end end
	return nil
end
local function act(action)
	local mod = clientModule()
	if mod and mod.onAction then mod.onAction(action) else input:FireServer({ Kind = "Action", Action = action }) end
end
local function stats(t)
	local list = t.list
	local n = #list
	if n < 30 then return "n=" .. n end
	local frozen, maxStep = 0, 0
	for i = 1, n do
		if list[i].v < 1 then frozen += 1 end
		maxStep = math.max(maxStep, list[i].d)
	end
	local sum, cnt = 0, 0
	for i = 8, n - 7 do
		local avg = 0
		for j = i - 7, i + 7 do avg += list[j].v end
		avg /= 15
		sum += (list[i].v - avg) ^ 2
		cnt += 1
	end
	return string.format("fps=%.0f frozen=%.0f%% speedJitter=%.1f maxStep=%.2f teleports=%d", n / 18, frozen / n * 100, math.sqrt(sum / math.max(1, cnt)), maxStep, t.teleports or 0)
end
local function finish()
	if sent then return end
	sent = true
	local out = {}
	for label, t in tracks do table.insert(out, label .. "[" .. stats(t) .. "]") end
	local lat = {}
	for _, p in presses do table.insert(lat, p.ms and string.format("%.0f", p.ms) or "miss") end
	table.insert(out, "inputLatencyMs=" .. table.concat(lat, ","))
	table.insert(out, "remoteRoundTripMs=" .. tostring(pingMs))
	report:FireServer(table.concat(out, " "))
end
state.OnClientEvent:Connect(function(m)
	if type(m) ~= "table" then return end
	if m.Type == "Phase" then
		if m.Phase == "Playing" and phase ~= "Playing" then startedAt = os.clock() end
		if m.Minigame then minigame = m.Minigame.Name end
		phase = m.Phase
		if m.Phase == "Finished" then finish() end
	elseif m.Type == "Chips" then
		for _, c in m.Chips do
			if c.Character then
				local label = (c.Id == "player_" .. me.UserId) and "self" or (c.IsBot and "bot" or "otherPlayer")
				chars[label] = c.Character
			end
		end
	end
end)
-- Remote round trip: ask the server for a state snapshot and time the reply.
task.spawn(function()
	while phase ~= "Playing" do task.wait(0.2) end
	task.wait(1.5)
	local t0 = os.clock()
	local conn
	conn = state.OnClientEvent:Connect(function(m)
		if type(m) == "table" and m.Type == "Phase" then
			pingMs = string.format("%.0f", (os.clock() - t0) * 1000)
			conn:Disconnect()
		end
	end)
	input:FireServer({ Kind = "Ready" })
end)
local climb = nil
local schedule = { { 4, "Left" }, { 7, "Right" }, { 10, "Left" }, { 13, "Right" } }
local nextPress = 1
local active
RunService.RenderStepped:Connect(function(dt)
	if phase ~= "Playing" or not startedAt then return end
	local t = os.clock() - startedAt
	for label, model in chars do
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp then
			local tr = tracks[label] or { list = {} }
			tracks[label] = tr
			local p = hrp.Position
			if tr.p and t > 2 and t < 20 and p.Y > 75 then
				local d = (p - tr.p).Magnitude
				if d < 5 then table.insert(tr.list, { v = d / dt, d = d }) else tr.teleports = (tr.teleports or 0) + 1 end
			end
			tr.p = p
		end
	end
	local mine = chars.self and chars.self:FindFirstChild("HumanoidRootPart")
	if mine and minigame == "Pole Shimmy" then
		-- Climb at a steady 4 presses a second; time how long each press takes to show up
		-- as upward movement (only measured after a pause, so the climber is standing still).
		climb = climb or { next = 2, key = "Left", pausedUntil = 0 }
		if t >= climb.next and t > climb.pausedUntil then
			local fresh = t - (climb.lastPress or -10) > 1.5
			act(climb.key)
			climb.lastPress = t
			climb.key = if climb.key == "Left" then "Right" else "Left"
			climb.next = t + 0.25
			if fresh then
				active = { t = os.clock(), y0 = mine.Position.Y }
				table.insert(presses, active)
			end
			-- Pause for 2s every 4s so there are several "first press after a pause" samples.
			if math.floor(t) % 4 == 3 and t - math.floor(t) < 0.25 then climb.pausedUntil = t + 2 end
		end
		if active and not active.ms and mine.Position.Y - active.y0 > 0.1 then
			active.ms = (os.clock() - active.t) * 1000
			active = nil
		end
	elseif mine then
		local s = schedule[nextPress]
		if s and t >= s[1] and not active then
			active = { t = os.clock(), x0 = mine.Position.X, dir = s[2] }
			table.insert(presses, active)
			act(s[2])
			nextPress += 1
		end
		if active then
			local moved = mine.Position.X - active.x0
			-- racers face world +Z, so their left is world +X
			local want = (active.dir == "Left") and moved or -moved
			if not active.ms and want > 0.1 then active.ms = (os.clock() - active.t) * 1000 end
			if os.clock() - active.t > 0.6 then act(active.dir .. "Stop") active = nil end
		end
	end
	if t > 24 then finish() end
end)
