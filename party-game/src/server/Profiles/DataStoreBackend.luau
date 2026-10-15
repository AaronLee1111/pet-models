--[[
	DataStoreBackend
	Real saving through a Roblox DataStore, with:
	  * retries with backoff on every call (DataStores fail now and then)
	  * session locking: a profile is claimed by one server at a time. Each record is
	    { Data = <profile>, Session = { JobId, Time } }. Loading claims the lock; a lock held
	    by another live server is waited on, and only taken over once it is older than
	    LOCK_EXPIRY (that server crashed without releasing). Saves refuse if another server
	    has taken the lock, so a stale server can never overwrite newer data.
	  * every write goes through UpdateAsync (never SetAsync)

	The store is injected, so tests use a fake one: anything with UpdateAsync(key, fn).
	Profiles (init) picks this backend in live servers (see Config.Profile.Backend).
]]

local DataStoreBackend = {}
DataStoreBackend.__index = DataStoreBackend

DataStoreBackend.STORE_NAME = "PartyProfiles_v1"
DataStoreBackend.RETRIES = 4
DataStoreBackend.RETRY_DELAY = 1 -- seconds, doubled after every failed attempt
DataStoreBackend.LOCK_EXPIRY = 30 * 60 -- a lock not refreshed for this long is abandoned
DataStoreBackend.LOCK_WAIT = 6 -- seconds between checks while another server holds the lock
DataStoreBackend.LOCK_CHECKS = 3 -- checks before giving up on loading (player plays unsaved)

-- options: { Store, JobId, Now = function() -> seconds, Wait = function(seconds) }
function DataStoreBackend.new(options)
	options = options or {}
	local store = options.Store
	if not store then
		store = game:GetService("DataStoreService"):GetDataStore(DataStoreBackend.STORE_NAME)
	end
	return setmetatable({
		Store = store,
		JobId = options.JobId or (if game.JobId ~= "" then game.JobId else "studio"),
		Now = options.Now or os.time,
		Wait = options.Wait or task.wait,
	}, DataStoreBackend)
end

-- Runs fn with retries; errors only if every attempt failed.
function DataStoreBackend:retry(what: string, fn)
	local delay = DataStoreBackend.RETRY_DELAY
	local lastError
	for attempt = 1, DataStoreBackend.RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return result
		end
		lastError = result
		if attempt < DataStoreBackend.RETRIES then
			self.Wait(delay)
			delay *= 2
		end
	end
	error(("%s failed after %d tries: %s"):format(what, DataStoreBackend.RETRIES, tostring(lastError)), 0)
end

local function lockedByOther(self, record): boolean
	local session = type(record) == "table" and record.Session
	return type(session) == "table"
		and session.JobId ~= self.JobId
		and self.Now() - (tonumber(session.Time) or 0) < DataStoreBackend.LOCK_EXPIRY
end

-- Loads a profile and claims its session lock. Errors if it can't (the caller then lets the
-- player play without saving rather than risk overwriting their data).
function DataStoreBackend:read(key: string)
	for check = 1, DataStoreBackend.LOCK_CHECKS do
		local blocked = false
		local data = self:retry("load " .. key, function()
			local result
			self.Store:UpdateAsync(key, function(record)
				if lockedByOther(self, record) then
					blocked = true
					return nil -- cancel: leave the record untouched
				end
				blocked = false
				record = if type(record) == "table" then record else {}
				result = record.Data
				record.Session = { JobId = self.JobId, Time = self.Now() }
				return record
			end)
			return result
		end)
		if not blocked then
			return data
		end
		if check < DataStoreBackend.LOCK_CHECKS then
			self.Wait(DataStoreBackend.LOCK_WAIT)
		end
	end
	error(("profile %s is in use on another server"):format(key), 0)
end

-- Saves (and refreshes our lock). release = true also drops the lock (player left).
function DataStoreBackend:write(key: string, data, release: boolean?)
	local refused = false
	self:retry("save " .. key, function()
		self.Store:UpdateAsync(key, function(record)
			if lockedByOther(self, record) then
				refused = true
				return nil
			end
			refused = false
			record = if type(record) == "table" then record else {}
			record.Data = data
			record.Session = if release then nil else { JobId = self.JobId, Time = self.Now() }
			return record
		end)
	end)
	if refused then
		error(("profile %s was taken over by another server; not saving"):format(key), 0)
	end
end

return DataStoreBackend
