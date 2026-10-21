--[[
	ReadyState
	Who is ready on the pre-minigame tutorial screen. Pure (no remotes, no clock of its own).

	  local ready = ReadyState.new(participants, readyAt)
	  ready:mark(participant, phase, time) -> true if it counted
	      only in the Instructions phase, only for one of this round's participants, only once
	      READY has unlocked (readyAt, with half a second of slack for clock drift)
	  ready:everyone() -> true when everyone still in the round is ready (leavers never block)
	  ready:ids() -> { [participantId] = true }   for the TutorialReady message
	  ready:leftIds() -> { [participantId] = true }  participants who left (shown as LEFT)

	The server marks the sender's own participant (the input carries no target), so nobody
	can ready someone else; bots are marked by the server after a short delay.
]]

local ReadyState = {}
ReadyState.__index = ReadyState

ReadyState.SLACK = 0.5

function ReadyState.new(participants, readyAt: number)
	return setmetatable({ Participants = participants, ReadyAt = readyAt, Ready = {} }, ReadyState)
end

function ReadyState:mark(participant, phase: string, time: number): boolean
	if phase ~= "Instructions" or time < self.ReadyAt - ReadyState.SLACK then
		return false
	end
	if self.Ready[participant] or not table.find(self.Participants, participant) then
		return false
	end
	self.Ready[participant] = true
	return true
end

function ReadyState:everyone(): boolean
	for _, participant in self.Participants do
		if not participant.Left and not self.Ready[participant] then
			return false
		end
	end
	return true
end

function ReadyState:ids()
	local ids = {}
	for participant in self.Ready do
		ids[participant.Id] = true
	end
	return ids
end

function ReadyState:leftIds()
	local ids = {}
	for _, participant in self.Participants do
		if participant.Left then
			ids[participant.Id] = true
		end
	end
	return ids
end

return ReadyState
