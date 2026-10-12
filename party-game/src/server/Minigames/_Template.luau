--[[
	_Template — copy this file to start a new minigame.
	Files whose names start with "_" are ignored by the MinigameManager, so rename the copy
	(e.g. "CoinRush") and it will show up in the vote automatically.

	Lifecycle (all called by the MinigameManager on a fresh instance each round, so keep
	per-round state on `self`):

	  Setup(arena, participants, round) -> { CFrame }   REQUIRED
	      Build your map inside arena.Folder (around arena.Origin). Return one spawn CFrame
	      per participant, same order as `participants`. Players are teleported there and
	      frozen while the instructions card + 3-2-1 countdown play.
	  Start()                                           REQUIRED
	      GO! Connect your loops here. Movement is already unfrozen.
	  GetResults() -> results                           REQUIRED
	      Ranked array { { Participant = p, Placement = 1 }, ... }. Use ResultsUtil
	      (fromElimination(self.Participants, self.Round) / fromScores / fromTeams) - ties share a placement.
	  Cleanup()                                         REQUIRED
	      Disconnect everything and remove anything you put outside arena.Folder
	      (e.g. Highlights on characters). arena.Folder itself is destroyed for you.

	  OnInput(participant, action)          optional - a player or bot pressed one of Info.Controls
	  UpdateBot(bot, dt)                    optional - bot brain, runs every Config.BotThinkInterval
	  OnParticipantLost(participant, why)   optional - why = "Died" | "Left" (already eliminated)
	  OnRoundEnding(reason)                 optional - reason = "TimeUp" or whatever you passed to round:End()

	Available on self: self.Round (RoundContext), self.Arena, self.Participants, self.Info.
	Each participant has a .Team (1 or 2) in 1v3 / 2v2 layouts; team 1 is the solo side in 1v3.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local Template = {}

Template.Info = {
	Name = "My Minigame",
	Description = "One or two sentences shown on the vote card and instructions screen.",
	Duration = 60, -- seconds; the round ends automatically when this runs out
	Layout = Config.Layouts.FFA, -- FFA | OneVsThree ("1v3") | TwoVsTwo ("2v2")
	Controls = {
		-- Each control becomes a key bind + mobile button on the client and an OnInput call here.
		{ Action = "Smack", Label = "Smack!", Key = "E" },
	},
}

function Template:Setup(arena, participants, _round)
	self.Connections = {}
	self.Score = {}

	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(60, 2, 60)
	floor.CFrame = arena.Origin
	floor.Parent = arena.Folder

	local spawns = {}
	for index, participant in participants do
		self.Score[participant] = 0
		spawns[index] = arena.Origin * CFrame.new((index - 2.5) * 8, 4, 0)
	end
	return spawns
end

function Template:Start()
	table.insert(
		self.Connections,
		RunService.Heartbeat:Connect(function()
			-- game logic; call self.Round:End() to finish early
		end)
	)
end

function Template:OnInput(participant, action)
	if action == "Smack" then
		self.Score[participant] += 1
	end
end

function Template:UpdateBot(bot, _dt)
	bot:MoveTo(self.Arena.Origin.Position)
	if math.random() < 0.2 then
		bot:Input("Smack")
	end
end

function Template:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		return self.Score[participant]
	end)
end

function Template:Cleanup()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Template
