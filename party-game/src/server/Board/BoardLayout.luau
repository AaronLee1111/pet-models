--[[
	BoardLayout
	Turns a board data module (Board/Boards/*) into a checked, indexed board.

	  BoardLayout.load(data, spaceTypes)  -> board (errors with a clear message if the data is bad)
	  BoardLayout.validate(data, spaceTypes) -> problem string or nil

	A board:
	  board.Name, board.Start, board.CrownSpaces
	  board.Spaces[id] = { Id, Type, At = {x, z}, Next = {ids}, Paths = {labels}? }
	  board.Order      every space id, in data order
	  board:nextOptions(id) -> { ids }   (ignores gates; Match:nextOptions applies them)
	  board.Gates      { { Id, From, To, Open, Toll } }: a fork edge that can be shut
	                   (Switch spaces flip them) and/or costs Toll coins to take
]]

local RotatingBridge = require(script.Parent.RotatingBridge)
local BoardLayout = {}

local Board = {}
Board.__index = Board

function Board:nextOptions(id: number): { number }
	local space = self.Spaces[id]
	return if space then space.Next else {}
end

function Board:get(id: number)
	return self.Spaces[id]
end

-- Fewest moves from `from` to `to` following Next (math.huge if unreachable). Cached.
function Board:distance(from: number, to: number): number
	self.DistanceCache = self.DistanceCache or {}
	local row = self.DistanceCache[from]
	if not row then
		row = { [from] = 0 }
		local queue, head = { from }, 1
		while queue[head] do
			local id = queue[head]
			head += 1
			for _, nextId in self.Spaces[id].Next do
				if row[nextId] == nil then
					row[nextId] = row[id] + 1
					table.insert(queue, nextId)
				end
			end
		end
		self.DistanceCache[from] = row
	end
	return row[to] or math.huge
end

function BoardLayout.validate(data, spaceTypes): string?
	if type(data) ~= "table" or type(data.Spaces) ~= "table" or #data.Spaces == 0 then
		return "board has no Spaces"
	end
	local byId = {}
	for index, space in data.Spaces do
		if type(space.Id) ~= "number" then
			return ("space #%d has no numeric Id"):format(index)
		end
		if byId[space.Id] then
			return ("duplicate space Id %d"):format(space.Id)
		end
		if not spaceTypes[space.Type] then
			return ("space %d has unknown Type %s"):format(space.Id, tostring(space.Type))
		end
		if type(space.At) ~= "table" or type(space.At[1]) ~= "number" or type(space.At[2]) ~= "number" then
			return ("space %d needs At = { x, z }"):format(space.Id)
		end
		if type(space.Next) ~= "table" or #space.Next == 0 then
			return ("space %d is a dead end (no Next)"):format(space.Id)
		end
		if space.Paths and #space.Paths ~= #space.Next then
			return ("space %d has %d Paths for %d Next"):format(space.Id, #space.Paths, #space.Next)
		end
		byId[space.Id] = space
	end
	for _, space in data.Spaces do
		for _, nextId in space.Next do
			if not byId[nextId] then
				return ("space %d points to missing space %s"):format(space.Id, tostring(nextId))
			end
		end
	end
	if not byId[data.Start] then
		return "Start is not a space"
	end
	for _, gate in data.Gates or {} do
		local from = byId[gate.From]
		if not from or not table.find(from.Next, gate.To) then
			return ("gate %s is not an edge of the board"):format(tostring(gate.Id))
		end
		if #from.Next < 2 then
			return ("gate %s must be on a fork, so there's always another way"):format(tostring(gate.Id))
		end
	end
	if type(data.CrownSpaces) ~= "table" or #data.CrownSpaces < 2 then
		return "need at least 2 CrownSpaces (the collectible moves after each purchase)"
	end
	for _, id in data.CrownSpaces do
		if not byId[id] then
			return ("CrownSpaces lists missing space %s"):format(tostring(id))
		end
	end

	local bridgeProblem = RotatingBridge.validate(data)
	if bridgeProblem then return bridgeProblem end

	-- Every space must be reachable from Start, and Start reachable again from every space
	-- (otherwise someone could get stuck on a branch forever).
	local function reach(from, edges)
		local seen, queue = { [from] = true }, { from }
		while #queue > 0 do
			local id = table.remove(queue)
			for _, nextId in edges[id] or {} do
				if not seen[nextId] then
					seen[nextId] = true
					table.insert(queue, nextId)
				end
			end
		end
		return seen
	end
	local forward, backward = {}, {}
	for _, space in data.Spaces do
		forward[space.Id] = space.Next
		for _, nextId in space.Next do
			backward[nextId] = backward[nextId] or {}
			table.insert(backward[nextId], space.Id)
		end
	end
	local fromStart, toStart = reach(data.Start, forward), reach(data.Start, backward)
	for _, space in data.Spaces do
		if not fromStart[space.Id] then
			return ("space %d can't be reached from Start"):format(space.Id)
		end
		if not toStart[space.Id] then
			return ("space %d never leads back to Start"):format(space.Id)
		end
	end
	return nil
end

function BoardLayout.load(data, spaceTypes)
	local problem = BoardLayout.validate(data, spaceTypes)
	if problem then
		error(("[BoardLayout] board %s: %s"):format(tostring(data and data.Name), problem), 2)
	end
	local board = setmetatable({
		Name = data.Name,
		DisplayName = data.DisplayName or data.Name,
		Start = data.Start,
		CrownSpaces = table.clone(data.CrownSpaces),
		Gates = data.Gates or {},
		Bridge = data.Bridge,
		Zones = data.Zones,
		Spaces = {},
		Order = {},
	}, Board)
	for _, space in data.Spaces do
		board.Spaces[space.Id] = table.clone(space)
		table.insert(board.Order, space.Id)
	end
	return board
end

return BoardLayout
