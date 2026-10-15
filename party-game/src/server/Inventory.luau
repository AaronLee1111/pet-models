--[[
	Inventory
	Who owns which cosmetic (PartyShared.Cosmetics) and what each owner has equipped.
	Server-authoritative; owners are participant Ids ("player_123", "bot_4").

	Players' records are their permanent profile tables (Profiles attaches them on join), so
	what they own and wear is saved with the profile. Bots get plain records that are wiped
	at the end of every match (resetBots).

	Inventory.onChanged(fn(ownerId)) fires after anything changes (CosmeticService redraws
	characters and tells the owner's client).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)

local Inventory = {}

local owners: { [string]: { Owned: { [string]: boolean }, Equipped: { [string]: string } } } = {}
local listeners: { (string) -> () } = {}

local function entry(ownerId: string)
	local record = owners[ownerId]
	if not record then
		record = { Owned = {}, Equipped = {} }
		owners[ownerId] = record
	end
	return record
end

local function changed(ownerId: string)
	for _, listener in listeners do
		task.spawn(listener, ownerId)
	end
end

function Inventory.onChanged(fn: (string) -> ())
	table.insert(listeners, fn)
end

-- Uses `owned` / `equipped` (a player's profile tables) as this owner's record, so every
-- change lands straight in the profile.
function Inventory.attach(ownerId: string, owned: { [string]: boolean }, equipped: { [string]: string })
	owners[ownerId] = { Owned = owned, Equipped = equipped }
	changed(ownerId)
end

function Inventory.owns(ownerId: string, itemId: string): boolean
	local record = owners[ownerId]
	return record ~= nil and record.Owned[itemId] == true
end

-- Gives an item. Returns false for unknown items or ones already owned.
function Inventory.grant(ownerId: string, itemId: string): boolean
	if not Cosmetics.get(itemId) or Inventory.owns(ownerId, itemId) then
		return false
	end
	entry(ownerId).Owned[itemId] = true
	changed(ownerId)
	return true
end

-- Equips an owned item into its slot (replacing whatever was there).
function Inventory.equip(ownerId: string, itemId: string): boolean
	local item = Cosmetics.get(itemId)
	if not item or not Inventory.owns(ownerId, itemId) then
		return false
	end
	entry(ownerId).Equipped[item.Slot] = itemId
	changed(ownerId)
	return true
end

function Inventory.unequip(ownerId: string, slot: string)
	local record = owners[ownerId]
	if record and record.Equipped[slot] then
		record.Equipped[slot] = nil
		changed(ownerId)
	end
end

function Inventory.getEquipped(ownerId: string): { [string]: string }
	local record = owners[ownerId]
	return if record then table.clone(record.Equipped) else {}
end

function Inventory.getOwned(ownerId: string): { string }
	local list = {}
	local record = owners[ownerId]
	if record then
		for itemId in record.Owned do
			table.insert(list, itemId)
		end
	end
	table.sort(list)
	return list
end

-- Catalog items this owner doesn't have yet.
function Inventory.unowned(ownerId: string)
	local list = {}
	for _, item in Cosmetics.Items do
		if not Inventory.owns(ownerId, item.Id) then
			table.insert(list, item)
		end
	end
	return list
end

function Inventory.forget(ownerId: string)
	owners[ownerId] = nil
end

function Inventory.resetBots()
	for ownerId in owners do
		if string.sub(ownerId, 1, 4) == "bot_" then
			owners[ownerId] = nil
			changed(ownerId)
		end
	end
end

return Inventory
