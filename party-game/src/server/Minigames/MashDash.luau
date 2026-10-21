--[[
	Mash Dash (2v2, side view)
	Everyone is locked in their lane (no walking, no jumping). Every Mash press scoots you
	forward. First runner across the line wins it for their team; if time runs out, the
	team that covered the most total distance wins.

	Exercises: SideView camera, movement locking, an action button (keyboard + mobile),
	ReportProgress chips, and the 2v2 team layout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local MashDash = {}

MashDash.Info = {
	Name = "Mash Dash",
	Description = "Mash to run! First one over the finish line wins it for their team. Tap as fast as you can!",
	Duration = 30,
	Layout = Config.Layouts.TwoVsTwo,
	Tutorial = {
		Objective = "Mash to run to the finish line.",
		Win = "First across the line wins it for their team.",
		Preview = {
			Loop = 5.5,
			Camera = { Position = Vector3.new(0, 12, 17.5), LookAt = Vector3.new(0, 1, 0) },
			Actors = {
				{ Start = Vector3.new(-7, 0, -3.3), Team = 1 },
				{ Start = Vector3.new(-7, 0, -1.1), Team = 1 },
				{ Start = Vector3.new(-7, 0, 1.1), Team = 2 },
				{ Start = Vector3.new(-7, 0, 3.3), Team = 2 },
			},
			Props = {
				{ Id = "Lane1", Shape = "Block", Size = Vector3.new(18, 1, 2), Position = Vector3.new(0, -0.5, -3.3), Color = Color3.fromRGB(232, 116, 116) },
				{ Id = "Lane2", Shape = "Block", Size = Vector3.new(18, 1, 2), Position = Vector3.new(0, -0.5, -1.1), Color = Color3.fromRGB(240, 140, 140) },
				{ Id = "Lane3", Shape = "Block", Size = Vector3.new(18, 1, 2), Position = Vector3.new(0, -0.5, 1.1), Color = Color3.fromRGB(110, 160, 235) },
				{ Id = "Lane4", Shape = "Block", Size = Vector3.new(18, 1, 2), Position = Vector3.new(0, -0.5, 3.3), Color = Color3.fromRGB(135, 180, 245) },
				{ Id = "Finish", Shape = "Block", Size = Vector3.new(0.6, 0.2, 9), Position = Vector3.new(7, 0.1, 0), Color = Color3.fromRGB(255, 248, 228) },
			},
			Steps = {
				{ At = 0.3, Actor = 1, Caption = "MASH!" },
				{ At = 0.3, Actor = 1, To = Vector3.new(-3, 0, -3.3), Time = 0.9 },
				{ At = 0.3, Actor = 2, To = Vector3.new(-4, 0, -1.1), Time = 0.9 },
				{ At = 0.3, Actor = 3, To = Vector3.new(-5, 0, 1.1), Time = 0.9 },
				{ At = 0.3, Actor = 4, To = Vector3.new(-4.5, 0, 3.3), Time = 0.9 },
				{ At = 1.3, Actor = 1, Caption = "MASH!" },
				{ At = 1.3, Actor = 1, To = Vector3.new(1.5, 0, -3.3), Time = 0.9 },
				{ At = 1.3, Actor = 2, To = Vector3.new(-1, 0, -1.1), Time = 0.9 },
				{ At = 1.3, Actor = 3, To = Vector3.new(-2, 0, 1.1), Time = 0.9 },
				{ At = 1.3, Actor = 4, To = Vector3.new(-1.5, 0, 3.3), Time = 0.9 },
				{ At = 2.3, Actor = 1, Caption = "MASH!" },
				{ At = 2.3, Actor = 1, To = Vector3.new(7.5, 0, -3.3), Time = 1.1 },
				{ At = 2.3, Actor = 2, To = Vector3.new(4, 0, -1.1), Time = 1.1 },
				{ At = 2.3, Actor = 3, To = Vector3.new(2.5, 0, 1.1), Time = 1.1 },
				{ At = 2.3, Actor = 4, To = Vector3.new(3.5, 0, 3.3), Time = 1.1 },
				{ At = 3.4, Prop = "Finish", Pulse = true },
				{ At = 3.5, Caption = "TEAM WINS!" },
			},
		},
	},
	Camera = { Mode = "SideView", Distance = 55, Height = 10 },
	Controls = {
		Move = false, -- lane-locked: the server moves you
		Jump = false,
		Actions = {
			{ Action = "Mash", Label = "MASH!", Key = "Space", Gamepad = "ButtonA" },
		},
	},
	ProgressLabel = "Progress",
}

local TRACK_LENGTH = 80
local STEP = 1.2 -- studs per press
local PRESS_COOLDOWN = 0.08 -- caps mashing at ~12 presses/s, so autoclickers don't win outright
local LANE_SPACING = 5
local TEAM_COLORS = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 160, 255) }

function MashDash:Setup(arena, participants, _round)
	self.Distance = {}
	self.LastPress = {}
	self.Lanes = {}
	self.Finished = nil

	-- Lanes sorted by team so teammates run next to each other.
	local ordered = table.clone(participants)
	table.sort(ordered, function(a, b)
		return (a.Team or 0) < (b.Team or 0)
	end)

	local startX = -TRACK_LENGTH / 2
	for laneIndex, participant in ordered do
		local z = (laneIndex - (#ordered + 1) / 2) * LANE_SPACING
		local lane = Instance.new("Part")
		lane.Name = "Lane_" .. participant.Name
		lane.Anchored = true
		lane.Size = Vector3.new(TRACK_LENGTH + 10, 1, LANE_SPACING - 0.5)
		lane.CFrame = arena.Origin * CFrame.new(0, 0, z)
		lane.Color = TEAM_COLORS[participant.Team or 1]
		lane.Material = Enum.Material.SmoothPlastic
		lane.Parent = arena.Folder

		self.Lanes[participant] = arena.Origin * CFrame.new(startX, 4, z)
		self.Distance[participant] = 0
		self.LastPress[participant] = 0
	end

	local finish = Instance.new("Part")
	finish.Name = "FinishLine"
	finish.Anchored = true
	finish.CanCollide = false
	finish.Size = Vector3.new(1, 0.2, LANE_SPACING * #ordered)
	finish.CFrame = arena.Origin * CFrame.new(TRACK_LENGTH / 2, 0.6, 0)
	finish.Material = Enum.Material.Neon
	finish.Color = Color3.fromRGB(255, 255, 255)
	finish.Parent = arena.Folder

	local spawns = {}
	for index, participant in participants do
		spawns[index] = self:_laneCFrame(participant)
	end
	return spawns
end

-- Where a participant should stand right now, facing down the track (+X).
function MashDash:_laneCFrame(participant): CFrame
	local base = self.Lanes[participant] * CFrame.new(self.Distance[participant], 0, 0)
	return CFrame.lookAt(base.Position, base.Position + self.Arena.Origin.RightVector)
end

function MashDash:Start()
	for _, participant in self.Participants do
		self.Round:ReportProgress(participant, "0%")
	end
	self.Round:SetStatus("MASH! 🏃💨")
end

function MashDash:OnInput(participant, action)
	if action ~= "Mash" or self.Finished then
		return
	end
	local clock = os.clock()
	if clock - self.LastPress[participant] < PRESS_COOLDOWN then
		return
	end
	self.LastPress[participant] = clock

	local distance = math.min(TRACK_LENGTH, self.Distance[participant] + STEP)
	self.Distance[participant] = distance
	participant:Teleport(self:_laneCFrame(participant))
	self.Round:ReportProgress(participant, ("%d%%"):format(distance / TRACK_LENGTH * 100))

	if distance >= TRACK_LENGTH then
		self.Finished = participant
		self.Round:Toast(("🏁 %s crossed the line for team %d!"):format(participant.Name, participant.Team or 1))
		self.Round:End("Finish")
	end
end

function MashDash:UpdateBot(bot, _dt)
	-- Bots mash 3-5 times a second depending on skill.
	if math.random() < 0.55 + bot.Skill * 0.4 then
		bot:Input("Mash")
	end
end

function MashDash:_teamTotals()
	local totals = {}
	for _, participant in self.Participants do
		local team = participant.Team or 1
		totals[team] = (totals[team] or 0) + self.Distance[participant]
	end
	return totals
end

function MashDash:GetResults()
	local totals = self:_teamTotals()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		local team = participant.Team or 1
		-- Crossing the line beats any distance total.
		local bonus = if self.Finished and self.Finished.Team == participant.Team then 1e6 else 0
		return totals[team] + bonus
	end)
end

function MashDash:Cleanup()
	-- Everything lives in arena.Folder; nothing else to undo.
end

return MashDash
