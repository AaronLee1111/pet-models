--[[
	CosmeticShop
	The permanent cosmetics shop in the lobby. Players spend permanent bank coins (their
	profile's Coins), never match coins, and what they buy is owned for good through the
	profile layer (Inventory's record for a player IS their profile's Owned/Equipped tables).

	Every request is checked here on the server:
	  * the item id must be a string naming a real catalog item
	  * the price always comes from the catalog (Cosmetics.bankPrice); anything a client
	    sends about prices is ignored
	  * the buyer must have a loaded profile, must not own it yet, and must afford it
	  * one purchase at a time per player, and at most one every MIN_INTERVAL seconds

	  local shop = CosmeticShop.new(store, inventory, clock?)   (tests build their own)
	  shop:buy(key, itemId) -> ok, code, message
	      codes: "ok" | "bad_request" | "unknown_item" | "owned" | "too_fast" | "no_profile"
	             | "insufficient"
	  CosmeticShop.start(send, onChanged)   live wiring (Main): handles Input.BuyCosmetic
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local Net = require(ReplicatedStorage.PartyShared.Net)

local CosmeticShop = {}
CosmeticShop.__index = CosmeticShop

CosmeticShop.MIN_INTERVAL = 0.75 -- seconds between purchase attempts per player

function CosmeticShop.new(store, inventory, clock)
	return setmetatable({
		Store = store,
		Inventory = inventory,
		Clock = clock or os.clock,
		LastAttempt = {},
		Busy = {},
	}, CosmeticShop)
end

function CosmeticShop:buy(key: string, itemId): (boolean, string, string)
	if type(itemId) ~= "string" or #itemId > 64 then
		return false, "bad_request", "That isn't a shop item."
	end
	local item = Cosmetics.get(itemId)
	if not item then
		return false, "unknown_item", "That item isn't in the shop."
	end
	local now = self.Clock()
	if self.Busy[key] or (self.LastAttempt[key] and now - self.LastAttempt[key] < CosmeticShop.MIN_INTERVAL) then
		return false, "too_fast", "One moment..."
	end
	self.LastAttempt[key] = now
	local profile = self.Store:get(key)
	if not profile then
		return false, "no_profile", "Your profile hasn't loaded yet. Try again in a moment."
	end
	if self.Inventory.owns(key, itemId) then
		return false, "owned", ("You already own the %s."):format(item.Name)
	end
	local price = Cosmetics.bankPrice(item)
	if profile.Coins < price then
		return false, "insufficient", ("The %s costs %d bank coins. You have %d."):format(item.Name, price, profile.Coins)
	end

	self.Busy[key] = true
	self.Store:addCoins(key, -price)
	local granted = self.Inventory.grant(key, itemId)
	if not granted then
		self.Store:addCoins(key, price) -- refund; shouldn't happen after the checks above
		self.Busy[key] = nil
		return false, "owned", ("You already own the %s."):format(item.Name)
	end
	if not self.Inventory.getEquipped(key)[item.Slot] then
		self.Inventory.equip(key, itemId) -- first item in a slot goes straight on
	end
	self.Busy[key] = nil
	task.spawn(self.Store.save, self.Store, key) -- save a purchase right away, not just at the next autosave
	return true, "ok", ("Bought the %s for %d bank coins!"):format(item.Name, price)
end

-- Live wiring --------------------------------------------------------------------------------

local live = nil

--[[
	send(player, message) delivers to one client; onChanged(player) refreshes their inventory
	(owned, equipped, bank coins). store/inventory are the game's Profiles store and Inventory.
]]
function CosmeticShop.start(store, inventory, send, onChanged)
	live = { Shop = CosmeticShop.new(store, inventory), Send = send, OnChanged = onChanged }
	Players.PlayerRemoving:Connect(function(player)
		local key = "player_" .. player.UserId
		live.Shop.LastAttempt[key] = nil
		live.Shop.Busy[key] = nil
	end)
end

function CosmeticShop.handleInput(player: Player, payload): boolean
	if payload.Kind ~= Net.Input.BuyCosmetic then
		return false
	end
	if not live then
		return true
	end
	local itemId = payload.ItemId -- payload.Price or anything else from the client is ignored
	local ok, code, text = live.Shop:buy("player_" .. player.UserId, itemId)
	live.Send(player, {
		Type = Net.Message.ShopResult,
		Ok = ok,
		Code = code,
		ItemId = if type(itemId) == "string" and #itemId <= 64 then itemId else nil,
		Text = text,
	})
	if ok then
		live.OnChanged(player)
	end
	return true
end

return CosmeticShop
