--[[
	MemoryBackend
	Keeps profiles in a Lua table: survives players leaving and rejoining the same server,
	gone when the server shuts down. Used in Studio and the unit tests.
]]

local ProfileStore = require(script.Parent.ProfileStore)

local MemoryBackend = {}
MemoryBackend.__index = MemoryBackend

function MemoryBackend.new()
	return setmetatable({ Data = {}, Writes = 0 }, MemoryBackend)
end

function MemoryBackend:read(key: string)
	return ProfileStore.deepCopy(self.Data[key])
end

function MemoryBackend:write(key: string, data)
	self.Writes += 1
	self.Data[key] = ProfileStore.deepCopy(data)
end

return MemoryBackend
