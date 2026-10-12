--[[
	ResultsUtil
	Helpers for the ranked results table every minigame returns from GetResults().

	A results table is an array sorted best-first:
	    { { Participant = p, Placement = 1 }, { Participant = q, Placement = 2 }, ... }
	Ties share a placement using standard competition ranking (1, 1, 3, 4).
]]

local ResultsUtil = {}

-- Ranks participants by a score. Higher is better unless lowerIsBetter is true.
function ResultsUtil.fromScores(participants, scoreOf: (any) -> number, lowerIsBetter: boolean?)
	local entries = {}
	for index, participant in participants do
		table.insert(entries, { Participant = participant, Score = scoreOf(participant), Index = index })
	end
	table.sort(entries, function(a, b)
		if a.Score == b.Score then
			return a.Index < b.Index -- keep the sort deterministic
		end
		if lowerIsBetter then
			return a.Score < b.Score
		end
		return a.Score > b.Score
	end)

	local results = {}
	for i, entry in entries do
		local placement = i
		if i > 1 and entries[i - 1].Score == entry.Score then
			placement = results[i - 1].Placement
		end
		results[i] = { Participant = entry.Participant, Placement = placement }
	end
	return results
end

-- Survivors tie for 1st; everyone else ranks by how long they lasted (last out = best).
-- Participants knocked out in the same instant (e.g. two falling on one tick) tie.
function ResultsUtil.fromElimination(participants, round)
	return ResultsUtil.fromScores(participants, function(participant)
		return round.EliminatedAt[participant] or math.huge
	end)
end

-- Every member of winningTeam ties for 1st, everyone else ties for the next placement.
function ResultsUtil.fromTeams(participants, winningTeam: number)
	return ResultsUtil.fromScores(participants, function(participant)
		return if participant.Team == winningTeam then 1 else 0
	end)
end

--[[
	Makes whatever a minigame returned safe to use:
	  * drops entries for unknown participants and duplicates
	  * appends anyone missing (and anyone who left mid-round) at the bottom
	  * recomputes placements so they are consistent competition ranks
]]
function ResultsUtil.normalize(rawResults, participants)
	local known = {}
	for _, participant in participants do
		known[participant] = true
	end

	local seen = {}
	local entries = {}
	if type(rawResults) == "table" then
		for _, entry in rawResults do
			local participant = type(entry) == "table" and entry.Participant
			local placement = type(entry) == "table" and tonumber(entry.Placement)
			if participant and known[participant] and not seen[participant] and not participant.Left then
				seen[participant] = true
				table.insert(entries, { Participant = participant, Placement = placement or math.huge })
			end
		end
	end

	-- Missing participants share last place; leavers go below them.
	for _, participant in participants do
		if not seen[participant] then
			table.insert(entries, {
				Participant = participant,
				Placement = if participant.Left then math.huge else 1e6,
			})
		end
	end

	for i, entry in entries do
		entry.Order = i
	end
	table.sort(entries, function(a, b)
		if a.Placement == b.Placement then
			return a.Order < b.Order
		end
		return a.Placement < b.Placement
	end)

	local results = {}
	for i, entry in entries do
		local placement = i
		if i > 1 and entries[i - 1].Placement == entry.Placement then
			placement = results[i - 1].Placement
		end
		results[i] = { Participant = entry.Participant, Placement = placement }
	end
	return results
end

return ResultsUtil
