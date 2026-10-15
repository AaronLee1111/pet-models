--[[
	DataStoreBackend  (NOT ENABLED)
	Where real saving plugs in. Config.Profile.Backend = "DataStore" selects it; until it is
	finished, read/write refuse to run so nothing is ever written by accident.

	To finish it (one place, nothing else in the game needs to change):
	  1. read(key):  DataStoreService:GetDataStore("PartyProfiles_v1"):GetAsync(key)
	                 Retry a few times with backoff; return nil for a new player.
	  2. write(key, data):  store:UpdateAsync(key, function() return data end)
	                 UpdateAsync, not SetAsync, so concurrent servers can't clobber each other.
	  3. Session locking: store the JobId + a timestamp in the record inside UpdateAsync and
	     refuse to load a profile another live server still holds (or use a profile library).
	  4. Autosave every few minutes from Profiles (init.luau), and save everyone in
	     game:BindToClose (already wired there; it calls ProfileStore:save for each player).
	  5. Studio: DataStores need "Enable Studio Access to API Services"; keep using the
	     Memory backend for normal Studio testing.
	Keys are "player_<UserId>". The data shape and migrations live in ProfileStore.reconcile.
]]

local DataStoreBackend = {}
DataStoreBackend.__index = DataStoreBackend

function DataStoreBackend.new()
	return setmetatable({}, DataStoreBackend)
end

function DataStoreBackend:read(_key: string)
	error("DataStore saving is not enabled yet (see DataStoreBackend.luau)")
end

function DataStoreBackend:write(_key: string, _data)
	error("DataStore saving is not enabled yet (see DataStoreBackend.luau)")
end

return DataStoreBackend
