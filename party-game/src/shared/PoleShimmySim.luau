--[[
	PoleShimmySim
	The climbing rules for Pole Shimmy, shared by server and client so both get exactly the
	same answer from the same presses:

	  * the server runs every climber with it (players from their timestamped presses, bots
	    from their own) and its result is the one that counts
	  * your client runs your climber with it too, so a press moves you on the very next frame

	A climber is plain data. Time is "race time" in seconds since that climber's GO.
]]

local Sim = {}

-- Tuning ----------------------------------------------------------------------------------

Sim.POLE_HEIGHT = 60 -- studs from the bottom to the bell
Sim.CLIMB_PER_PRESS = 0.9 -- studs a correctly alternated press is worth, before the rhythm bonus
Sim.RHYTHM_WINDOW = { 0.1, 0.5 } -- seconds between presses that count as climbing in rhythm
Sim.RHYTHM_TOLERANCE = 0.35 -- a beat is "steady" if within 35% of the previous gap
Sim.STREAK_BONUS = 0.08 -- extra multiplier per steady beat in a row ...
Sim.STREAK_MAX = 10 -- ... up to this many beats
Sim.BASE_MULTIPLIER = 0.7 -- multiplier with no streak (first press, or after a pause)
Sim.SPEED_CAP = 5 -- studs/s: nobody climbs faster than this, however fast they tap
Sim.POOL_MAX = 2.5 -- studs of climb that can be banked ahead of the cap
Sim.PAUSE_GRACE = 0.5 -- seconds without a press before the banked climb starts to fade ...
Sim.DECAY = 4 -- ... at this rate (per second, exponential)
-- Presses closer together than the window's lower edge are ignored (anti-autoclicker).
Sim.MIN_PRESS_INTERVAL = Sim.RHYTHM_WINDOW[1]

local STEP = 1 / 60 -- integration step; fixed so server and client agree

-- Climbers -------------------------------------------------------------------------------------

function Sim.newClimber()
	return {
		Time = 0, -- race time this state is at
		Height = 0,
		Pool = 0, -- climb earned but not yet climbed (drained at SPEED_CAP)
		Streak = 0,
		LastKey = nil, -- "Left" | "Right"
		LastPressAt = -math.huge,
		LastInterval = nil,
		Speed = 0, -- studs/s over the last step (for animation)
		FinishedAt = nil, -- race time the bell was reached
	}
end

-- Moves a climber forward in time to `toTime` (never backwards).
function Sim.advance(climber, toTime: number)
	while climber.Time < toTime - 1e-6 do
		local dt = math.min(STEP, toTime - climber.Time)
		if climber.FinishedAt then
			climber.Time += dt
			climber.Speed = 0
			continue
		end
		if climber.Time - climber.LastPressAt > Sim.PAUSE_GRACE then
			climber.Pool *= math.exp(-Sim.DECAY * dt)
		end
		local climb = math.min(climber.Pool, Sim.SPEED_CAP * dt)
		climber.Pool -= climb
		climber.Speed = climb / dt
		if climber.Height + climb >= Sim.POLE_HEIGHT then
			-- Reached the bell part-way through this step.
			local needed = Sim.POLE_HEIGHT - climber.Height
			climber.FinishedAt = climber.Time + (if climb > 0 then dt * needed / climb else 0)
			climber.Height = Sim.POLE_HEIGHT
			climber.Pool = 0
		else
			climber.Height += climb
		end
		climber.Time += dt
	end
end

--[[
	A press of `key` ("Left" or "Right") at race time `t`. Advances the climber to `t` first.
	Returns what happened: "climb", "same" (same hand twice), "fast" (too soon after the last
	press), or "done" (already at the top).
]]
function Sim.press(climber, key: string, t: number): string
	Sim.advance(climber, t)
	if climber.FinishedAt then
		return "done"
	end
	if key == climber.LastKey then
		return "same"
	end
	local interval = t - climber.LastPressAt
	if interval < Sim.MIN_PRESS_INTERVAL then
		return "fast"
	end

	if interval > Sim.RHYTHM_WINDOW[2] then
		climber.Streak = 0 -- lost the rhythm: start over
	elseif
		climber.LastInterval and math.abs(interval - climber.LastInterval) <= Sim.RHYTHM_TOLERANCE * climber.LastInterval
	then
		climber.Streak = math.min(climber.Streak + 1, Sim.STREAK_MAX)
	else
		climber.Streak = math.max(climber.Streak - 1, 0) -- uneven beat
	end
	local multiplier = Sim.BASE_MULTIPLIER + climber.Streak * Sim.STREAK_BONUS
	climber.Pool = math.min(Sim.POOL_MAX, climber.Pool + Sim.CLIMB_PER_PRESS * multiplier)

	climber.LastKey = key
	climber.LastPressAt = t
	climber.LastInterval = if interval <= Sim.RHYTHM_WINDOW[2] then interval else nil
	return "climb"
end

return Sim
