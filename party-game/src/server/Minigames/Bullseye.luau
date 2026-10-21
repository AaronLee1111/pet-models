--[[
	Bullseye (1v3, timing + precision)
	Everyone has a gauge with a marker sweeping back and forth. Press STOP to lock the marker
	as close to the centre as you can: 100 points dead centre, 0 at the edge. Three shots,
	each sweep faster than the last. The solo player's total takes on the team's AVERAGE
	total; the higher side wins.

	Server-authoritative: the marker's position is a function of the server clock, and a
	press is scored at the moment the server receives it. Bots aim with skill-based error.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local Bullseye = {}

Bullseye.Info = {
	Name = "Bullseye",
	Description = "Stop the sliding marker as close to the middle as you can. 3 shots, faster each time. 1 vs 3: the solo player's score takes on the team's average!",
	Duration = 40,
	Layout = Config.Layouts.OneVsThree,
	Tutorial = {
		Objective = "Stop the marker in the middle.",
		Rule = "3 shots, each faster. Solo player vs the team's average.",
		Win = "Closest to the middle wins.",
		Preview = {
			Loop = 6,
			Camera = { Position = Vector3.new(0, 11, 23), LookAt = Vector3.new(0, 3, 0) },
			Actors = {
				{ Start = Vector3.new(-6.5, 0, 3), Team = 1 },
				{ Start = Vector3.new(0.5, 0, 3.5), Team = 2 },
				{ Start = Vector3.new(4, 0, 3.5), Team = 2 },
				{ Start = Vector3.new(7.5, 0, 3.5), Team = 2 },
			},
			Props = {
				{ Id = "Floor", Shape = "Block", Size = Vector3.new(20, 1, 12), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(120, 196, 170) },
				{ Id = "Bar", Shape = "Block", Size = Vector3.new(16, 0.6, 1.4), Position = Vector3.new(0, 4.5, -2), Color = Color3.fromRGB(255, 248, 228) },
				{ Id = "Target", Shape = "Block", Size = Vector3.new(1.4, 0.7, 1.5), Position = Vector3.new(0, 4.5, -2), Color = Color3.fromRGB(240, 198, 96) },
				{ Id = "Marker", Shape = "Block", Size = Vector3.new(0.4, 1.6, 1.7), Position = Vector3.new(-7, 4.5, -2), Color = Color3.fromRGB(226, 72, 70), Neon = true },
			},
			Steps = {
				{ At = 0, Prop = "Marker", To = Vector3.new(7, 4.5, -2), Time = 0.7 },
				{ At = 0.7, Prop = "Marker", To = Vector3.new(-7, 4.5, -2), Time = 0.7 },
				{ At = 1.4, Prop = "Marker", To = Vector3.new(7, 4.5, -2), Time = 0.7 },
				{ At = 1.75, Actor = 1, Caption = "STOP!" },
				{ At = 1.75, Prop = "Marker", To = Vector3.new(0.3, 4.5, -2), Time = 0.05 },
				{ At = 1.9, Prop = "Target", Pulse = true },
				{ At = 2.4, Actor = 1, Caption = "NICE!" },
				{ At = 3.1, Prop = "Marker", To = Vector3.new(-7, 4.5, -2), Time = 0.5 },
				{ At = 3.6, Prop = "Marker", To = Vector3.new(7, 4.5, -2), Time = 0.5 },
				{ At = 3.85, Actor = 2, Caption = "STOP!" },
				{ At = 3.85, Prop = "Marker", To = Vector3.new(1.8, 4.5, -2), Time = 0.05 },
				{ At = 4.6, Caption = "1 vs 3" },
			},
		},
	},
	Camera = { Mode = "AngledOverhead", Height = 40, Distance = 30 },
	Controls = {
		Move = false,
		Jump = false,
		Actions = {
			{ Action = "Stop", Label = "STOP!", Key = "Space", Gamepad = "ButtonA" },
		},
	},
	ProgressLabel = "Points",
}

-- Tuning ----------------------------------------------------------------------------------
Bullseye.SHOTS = 3
Bullseye.SPEEDS = { 2.2, 3.0, 3.8 } -- radians/second of the sweep, per shot
Bullseye.SHOT_TIME = 7 -- seconds to take a shot before it counts as a miss (0)
Bullseye.BETWEEN_SHOTS = 1.5
local HALF_WIDTH = 8 -- studs from centre to edge of a gauge
local LANE_SPACING = 7

-- Marker offset (-1..1 of the half width) at `t` seconds into a shot.
function Bullseye.offsetAt(shot: number, t: number): number
	return math.sin(t * Bullseye.SPEEDS[shot] + 0.6)
end

-- Points for stopping at `offset` (-1..1).
function Bullseye.scoreFor(offset: number): number
	return math.floor(math.max(0, 1 - math.abs(offset)) * 100 + 0.5)
end

function Bullseye:Setup(arena, participants, _round)
	self.Now = self.Now or os.clock
	self.Totals, self.Locked, self.Markers = {}, {}, {}
	self.Shot = 0
	self.ShotStart = nil

	-- One floor under every gauge and every player's spot.
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(HALF_WIDTH * 2 + 10, 1, #participants * LANE_SPACING + 12)
	floor.CFrame = arena.Origin * CFrame.new(0, -0.8, 2)
	floor.Color = Color3.fromRGB(70, 70, 90)
	floor.Parent = arena.Folder

	for index, participant in participants do
		self.Totals[participant] = 0
		local z = (index - (#participants + 1) / 2) * LANE_SPACING
		local gauge = Instance.new("Part")
		gauge.Name = "Gauge"
		gauge.Anchored = true
		gauge.Size = Vector3.new(HALF_WIDTH * 2, 0.6, 3)
		gauge.CFrame = arena.Origin * CFrame.new(0, 0, z)
		gauge.Color = if participant.Team == 1 then Color3.fromRGB(255, 120, 120) else Color3.fromRGB(120, 170, 255)
		gauge.Parent = arena.Folder
		local centre = Instance.new("Part")
		centre.Name = "Centre"
		centre.Anchored = true
		centre.CanCollide = false
		centre.Size = Vector3.new(0.6, 0.7, 3.1)
		centre.CFrame = gauge.CFrame
		centre.Color = Color3.fromRGB(255, 230, 80)
		centre.Material = Enum.Material.Neon
		centre.Parent = arena.Folder
		local marker = Instance.new("Part")
		marker.Name = "Marker"
		marker.Anchored = true
		marker.CanCollide = false
		marker.Size = Vector3.new(0.8, 2, 0.8)
		marker.CFrame = gauge.CFrame * CFrame.new(0, 1.3, 0)
		marker.Color = Color3.new(1, 1, 1)
		marker.Parent = arena.Folder
		self.Markers[participant] = { Part = marker, Base = gauge.CFrame }
	end

	local spawns = {}
	for index, participant in participants do
		spawns[index] = self.Markers[participant].Base * CFrame.new(0, 3, 4)
	end
	return spawns
end

function Bullseye:_report()
	for participant, total in self.Totals do
		self.Round:ReportProgress(participant, total)
	end
end

function Bullseye:_startShot()
	self.Shot += 1
	self.ShotStart = self.Now()
	self.Locked = {}
	self.Round:SetStatus(("Shot %d of %d: STOP in the middle!"):format(self.Shot, Bullseye.SHOTS))
	local shot = self.Shot
	task.delay(Bullseye.SHOT_TIME, function()
		if self.Shot == shot and not self.Round.Ended then
			self:_endShot()
		end
	end)
end

function Bullseye:_endShot()
	self.ShotStart = nil
	self:_report()
	if self.Shot >= Bullseye.SHOTS then
		self.Round:End("AllShots")
		return
	end
	task.delay(Bullseye.BETWEEN_SHOTS, function()
		if not self.Round.Ended then
			self:_startShot()
		end
	end)
end

-- A STOP press, scored at the server's clock. One per shot.
function Bullseye:Stop(participant)
	if not self.ShotStart or self.Locked[participant] ~= nil then
		return nil
	end
	local offset = Bullseye.offsetAt(self.Shot, self.Now() - self.ShotStart)
	local points = Bullseye.scoreFor(offset)
	self.Locked[participant] = offset
	self.Totals[participant] += points
	local marker = self.Markers[participant]
	if marker then
		marker.Part.CFrame = marker.Base * CFrame.new(offset * HALF_WIDTH, 1.3, 0)
		marker.Part.Color = Color3.fromRGB(255, 230, 80)
	end
	self:_report()
	local everyone = true
	for _, other in self.Participants do
		if self.Locked[other] == nil and not other.Left then
			everyone = false
		end
	end
	if everyone then
		self:_endShot()
	end
	return points
end

function Bullseye:Start()
	self:_report()
	self.Connection = RunService.Heartbeat:Connect(function()
		if not self.ShotStart then
			return
		end
		local t = self.Now() - self.ShotStart
		for participant, marker in self.Markers do
			if self.Locked[participant] == nil then
				marker.Part.Color = Color3.new(1, 1, 1)
				marker.Part.CFrame = marker.Base * CFrame.new(Bullseye.offsetAt(self.Shot, t) * HALF_WIDTH, 1.3, 0)
			end
		end
	end)
	self:_startShot()
end

function Bullseye:OnInput(participant, action)
	if action == "Stop" then
		self:Stop(participant)
	end
end

-- Bots pick an aim (worse with low skill) and press when the marker gets there.
function Bullseye:UpdateBot(bot, _dt)
	local memory = bot.Memory
	if not self.ShotStart or memory.Shot == self.Shot then
		return
	end
	memory.Shot = self.Shot
	local aim = (math.random() * 2 - 1) * (0.05 + (1 - bot.Skill) * 0.45)
	-- First moment after a short look when the marker passes `aim`.
	local shot, start = self.Shot, self.ShotStart
	local earliest = self.Now() - start + 0.6 + math.random() * 0.8
	local t = earliest
	while t < Bullseye.SHOT_TIME - 0.2 and math.abs(Bullseye.offsetAt(shot, t) - aim) > 0.03 do
		t += 1 / 120
	end
	task.delay(math.max(0, start + t - self.Now()), function()
		if self.Shot == shot and self.ShotStart == start then
			bot:Input("Stop")
		end
	end)
end

-- 1v3: solo (team 1) total vs the team's average total.
function Bullseye:TeamScores()
	local solo, teamSum, teamCount = 0, 0, 0
	for _, participant in self.Participants do
		if participant.Team == 1 then
			solo += self.Totals[participant]
		else
			teamSum += self.Totals[participant]
			teamCount += 1
		end
	end
	return solo, if teamCount > 0 then teamSum / teamCount else 0
end

function Bullseye:GetResults()
	local solo, team = self:TeamScores()
	if solo == team then
		return ResultsUtil.fromScores(self.Participants, function()
			return 0
		end)
	end
	return ResultsUtil.fromTeams(self.Participants, if solo > team then 1 else 2)
end

function Bullseye:Cleanup()
	if self.Connection then
		self.Connection:Disconnect()
	end
	self.Shot = math.huge
end

return Bullseye
