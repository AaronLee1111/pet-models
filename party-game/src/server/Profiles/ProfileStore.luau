--[[
	ProfileStore
	Permanent per-player data, behind a swappable storage backend. Only things that should
	survive between matches and sessions live here:

	  Version    schema version (bump + handle in reconcile when the shape changes)
	  Coins      permanent "bank" coins (NOT match coins: those live in CoinService and reset)
	  Owned      { [cosmeticId] = true }
	  Equipped   { [slot] = cosmeticId }

	Match coins, Crowns, board items and stats are never written here.

	A backend is any table with:
	  read(key)        -> data table or nil (may yield; may error)
	  write(key, data) -> () (may yield; may error)
	MemoryBackend is used in Studio and tests; DataStoreBackend is where real saving goes.
]]

local ProfileStore = {}
ProfileStore.__index = ProfileStore

ProfileStore.Version = 1

function ProfileStore.template()
	return { Version = ProfileStore.Version, Coins = 0, Owned = {}, Equipped = {} }
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end
ProfileStore.deepCopy = deepCopy

-- Fills in missing fields and drops anything malformed, so old or damaged saves still load.
function ProfileStore.reconcile(data)
	local profile = ProfileStore.template()
	if type(data) ~= "table" then
		return profile
	end
	if type(data.Coins) == "number" and data.Coins >= 0 then
		profile.Coins = math.floor(data.Coins)
	end
	if type(data.Owned) == "table" then
		for id, owned in data.Owned do
			if type(id) == "string" and owned == true then
				profile.Owned[id] = true
			end
		end
	end
	if type(data.Equipped) == "table" then
		for slot, id in data.Equipped do
			if type(slot) == "string" and type(id) == "string" and profile.Owned[id] then
				profile.Equipped[slot] = id
			end
		end
	end
	-- Future: if (data.Version or 0) < 2 then migrate ... end
	return profile
end

function ProfileStore.new(backend)
	return setmetatable({ Backend = backend, Loaded = {} }, ProfileStore)
end

-- Loads (or creates) a profile. On a backend error the player gets a fresh profile that is
-- marked so it's never saved over their real data.
function ProfileStore:load(key: string)
	local ok, data = pcall(self.Backend.read, self.Backend, key)
	local profile = ProfileStore.reconcile(if ok then data else nil)
	local entry = { Data = profile, CanSave = ok }
	if not ok then
		warn(("[Profiles] Could not load %s, playing without saving: %s"):format(key, tostring(data)))
	end
	self.Loaded[key] = entry
	return profile
end

function ProfileStore:get(key: string)
	local entry = self.Loaded[key]
	return entry and entry.Data
end

function ProfileStore:save(key: string): boolean
	local entry = self.Loaded[key]
	if not entry or not entry.CanSave then
		return false
	end
	local ok, err = pcall(self.Backend.write, self.Backend, key, deepCopy(entry.Data))
	if not ok then
		warn(("[Profiles] Could not save %s: %s"):format(key, tostring(err)))
	end
	return ok
end

-- Saves and forgets a profile (player left).
function ProfileStore:release(key: string): boolean
	local saved = self:save(key)
	self.Loaded[key] = nil
	return saved
end

-- Permanent bank coins (never negative).
function ProfileStore:addCoins(key: string, amount: number): number
	local profile = self:get(key)
	if not profile then
		return 0
	end
	profile.Coins = math.max(0, profile.Coins + math.floor(amount))
	return profile.Coins
end

return ProfileStore
