--[[
	SeatClaims
	Seat reservations for players who leave a match and come back. When a real player
	leaves, their seat is reserved for their numeric UserId until the match ends; a bot keeps
	playing it meanwhile. If the same UserId rejoins, their claim is queued here and the
	running mode hands the seat back at a safe moment (see SeatClaims.timing).

	Pure bookkeeping, no networking or world, so it can be tested on its own. A `key` is
	whatever the mode uses to name a seat: the Match seat table (board) or a seat index
	(Minigames mode). Every check is by UserId, never by name.

	  local claims = SeatClaims.new()
	  claims:reserve(key, userId)    -> true if the seat is (now) reserved for that user
	  claims:keyFor(userId)          -> the seat reserved for them, or nil
	  claims:reservedFor(key)        -> the UserId a seat is reserved for, or nil
	  claims:request(player)         -> key?, code: a returning player asks for their seat
	      codes: "queued" | "bad_user" | "none" | "duplicate"
	  claims:pendingFor(key)         -> the player waiting to take that seat back, or nil
	  claims:consume(key)            forget the pending claim on that seat (done or refused)
	  claims:cancel(player)          that player left again before getting their seat
	  claims:clear()                 -> players still waiting (match over); forgets everything

	  SeatClaims.timing(stage, isTurnSeat) -> "now" | "after_turn" | "after_minigame" | "later"
]]

local SeatClaims = {}
SeatClaims.__index = SeatClaims

-- Board stages where no dice, movement, prompt, event or bridge rotation is in progress for
-- a seat that isn't taking its turn, so a seat can change hands right away.
SeatClaims.SAFE_STAGES = { Start = true, Roll = true, Landed = true, OrderDone = true, Standings = true }

-- Text the returning player sees for each timing.
SeatClaims.Messages = {
	now = "Welcome back! You're in your seat again.",
	after_turn = "Rejoining your seat when this turn ends.",
	after_minigame = "Rejoining your seat after this minigame.",
	later = "Rejoining your seat in a moment.",
	ended = "The match ended before you could rejoin your seat.",
}

local function validUserId(id): boolean
	return type(id) == "number" and id > 0 and id % 1 == 0
end

function SeatClaims.new()
	return setmetatable({
		ByUser = {}, -- [userId] = key
		ByKey = {}, -- [key] = userId
		Pending = {}, -- [userId] = Player waiting to take the seat back
	}, SeatClaims)
end

-- Reserving the same seat for the same user again is fine (they left a second time).
function SeatClaims:reserve(key, userId): boolean
	if key == nil or not validUserId(userId) then
		return false
	end
	local holder = self.ByKey[key]
	if holder ~= nil and holder ~= userId then
		return false -- one user per seat
	end
	local held = self.ByUser[userId]
	if held ~= nil and held ~= key then
		return false -- one seat per user
	end
	self.ByUser[userId] = key
	self.ByKey[key] = userId
	return true
end

function SeatClaims:keyFor(userId)
	return self.ByUser[userId]
end

function SeatClaims:reservedFor(key): number?
	return self.ByKey[key]
end

function SeatClaims:request(player)
	local userId = player and player.UserId
	if not validUserId(userId) then
		return nil, "bad_user"
	end
	local key = self.ByUser[userId]
	if key == nil then
		return nil, "none" -- a genuinely new late joiner: they watch until the next match
	end
	local queued = self.Pending[userId]
	if queued ~= nil and queued ~= player and queued.Parent ~= nil then
		return nil, "duplicate" -- an earlier session of the same user is still waiting
	end
	self.Pending[userId] = player
	return key, "queued"
end

-- Only a player whose UserId owns the reservation (and who is still in the game) counts.
function SeatClaims:pendingFor(key)
	local userId = self.ByKey[key]
	local player = userId and self.Pending[userId]
	if not player then
		return nil
	end
	if player.Parent == nil or player.UserId ~= userId then
		self.Pending[userId] = nil
		return nil
	end
	return player
end

function SeatClaims:consume(key)
	local userId = self.ByKey[key]
	if userId then
		self.Pending[userId] = nil
	end
end

function SeatClaims:cancel(player)
	local userId = player and player.UserId
	if userId and self.Pending[userId] == player then
		self.Pending[userId] = nil
	end
end

function SeatClaims:clear()
	local waiting = {}
	for _, player in self.Pending do
		table.insert(waiting, player)
	end
	table.clear(self.ByUser)
	table.clear(self.ByKey)
	table.clear(self.Pending)
	return waiting
end

--[[
	When a returning player may take their seat back on the board:
	  during a minigame (or a duel)        after it, before the next board turn
	  while it's their seat's turn         when that turn ends
	  any other seat's dice/move/prompt,
	  board event or bridge rotation       at the next safe stage
	  otherwise                            now
]]
function SeatClaims.timing(stage: string?, isTurnSeat: boolean): string
	if stage == "Minigame" then
		return "after_minigame"
	end
	if isTurnSeat then
		return "after_turn"
	end
	if stage and SeatClaims.SAFE_STAGES[stage] then
		return "now"
	end
	return "later"
end

return SeatClaims
