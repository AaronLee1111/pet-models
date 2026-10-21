--[[
	IntroPlan
	The board-opening introduction's timetable. Pure (no remotes, no clock of its own).

	  local plan = IntroPlan.schedule(count, hasSpec, boardTimes, startsAt)
	    plan.ArriveAt[i]   when seat i appears (seat order), plan.GroupAt (everyone has
	                       arrived: skipping unlocks), plan.EndsAt (turn order may start)

	With no Intro data on the board everyone is already on Start and only a short group shot
	plays. Board Intro.Times override Config.Board.Intro key by key.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local IntroPlan = {}

function IntroPlan.schedule(count: number, hasSpec: boolean, boardTimes, startsAt: number)
	local times = table.clone(Config.Board.Intro)
	for key, value in boardTimes or {} do
		times[key] = value
	end
	local plan = { ArriveAt = {}, Times = times }
	if not hasSpec then
		for i = 1, count do
			plan.ArriveAt[i] = startsAt
		end
		plan.GroupAt = startsAt
		plan.EndsAt = startsAt + times.NoSpec
		return plan
	end
	local at = startsAt + times.Establish
	for i = 1, count do
		plan.ArriveAt[i] = at
		at += times.Each
	end
	plan.GroupAt = at
	plan.EndsAt = at + times.Group + times.Out
	return plan
end

return IntroPlan
