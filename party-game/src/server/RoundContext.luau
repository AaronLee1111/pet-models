--[[
	RoundContext
	The toolbox the framework hands to a minigame for one round (third argument of Setup,
	and stored on the minigame instance as self.Round). Minigames use it instead of
	touching framework internals:

	  round.Participants        all four participants (real players + bots)
	  round.Arena               the arena object (Folder / Origin / SpectatorCFrame)
	  round.Rng                 a Random for this round
	  round.EliminationOrder    participants in the order they were eliminated
	  round.EliminatedAt        participant -> server time they were eliminated

	  round:Eliminate(p)        mark p out and send them to the spectator box
	  round:IsEliminated(p)
	  round:GetAlive()          participants still in play
	  round:GetTeam(n)          participants on team n (1v3 / 2v2)
	  round:End()               finish the round early (e.g. one player left)
	  round:TimeLeft()
	  round:Toast(text)         short feed message on every client
	  round:SetStatus(text)     persistent HUD line on every client
	  round:ReportProgress(p, value, label?)
	                            update p's player chip (score / progress / lives / any short text)
]]

local Workspace = game:GetService("Workspace")

local RoundContext = {}
RoundContext.__index = RoundContext

function RoundContext.new(params)
	return setmetatable({
		Participants = params.Participants,
		Arena = params.Arena,
		Rng = Random.new(),
		EliminationOrder = {},
		EliminatedAt = {},
		Ended = false,
		EndReason = nil,
		EndsAt = math.huge,
		_eliminated = {},
		_broadcast = params.Broadcast,
		_setStatus = params.SetStatus,
		_onProgress = params.OnProgress,
		_onEliminated = params.OnEliminated,
	}, RoundContext)
end

function RoundContext:Eliminate(participant, silent: boolean?)
	if self._eliminated[participant] then
		return
	end
	self._eliminated[participant] = true
	table.insert(self.EliminationOrder, participant)
	self.EliminatedAt[participant] = Workspace:GetServerTimeNow()

	if participant:IsAlive() then
		local jitter = Vector3.new(self.Rng:NextNumber(-6, 6), 0, self.Rng:NextNumber(-6, 6))
		participant:Teleport(self.Arena.SpectatorCFrame + jitter)
		participant:ResetMovement() -- spectators may walk around the glass box
	end
	if not silent then
		self:Toast(("❌ %s is out!"):format(participant.Name))
	end
	self._onEliminated(participant)
end

function RoundContext:IsEliminated(participant): boolean
	return self._eliminated[participant] == true
end

function RoundContext:GetAlive()
	local alive = {}
	for _, participant in self.Participants do
		if not self._eliminated[participant] and not participant.Left then
			table.insert(alive, participant)
		end
	end
	return alive
end

function RoundContext:GetTeam(team: number)
	local members = {}
	for _, participant in self.Participants do
		if participant.Team == team then
			table.insert(members, participant)
		end
	end
	return members
end

function RoundContext:End(reason: string?)
	if not self.Ended then
		self.Ended = true
		self.EndReason = reason or "Ended"
	end
end

function RoundContext:TimeLeft(): number
	return math.max(0, self.EndsAt - Workspace:GetServerTimeNow())
end

function RoundContext:Toast(text: string)
	self._broadcast({ Type = "Toast", Text = text })
end

function RoundContext:SetStatus(text: string?)
	self._setStatus(text)
end

-- value: number or short string ("3 ❤️", "45%"). label: optional caption, defaults to
-- Info.ProgressLabel. Cheap to call every frame; updates are batched.
function RoundContext:ReportProgress(participant, value: number | string, label: string?)
	if type(value) == "number" then
		value = math.floor(value * 10 + 0.5) / 10 -- keep chips tidy
	end
	self._onProgress(participant, value, label)
end

return RoundContext
