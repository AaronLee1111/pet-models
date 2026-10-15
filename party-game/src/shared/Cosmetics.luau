--[[
	Cosmetics
	The catalog of cosmetic items. Pure data, readable by server and client.

	Each item:
	  Id      unique, never reuse or rename once players own it
	  Name    shown to players
	  Slot    one equipped item per slot (Cosmetics.Slots)
	  Price   coins at a shop space
	  Rarity  "Common" | "Rare" | "Epic" (for the later visual pass)
	  Visual  placeholder look, drawn by PartyServer.CosmeticService:
	            { Kind = "Hat", Shape = "Block"|"Ball"|"Cylinder", Size = {x, y, z}, Color = {r, g, b} }
	            { Kind = "Trail", Colors = { {r, g, b}, {r, g, b} } }
	            { Kind = "Sparkles", Color = {r, g, b} }   (emotes: an aura until real emotes exist)

	To add one, append an entry; shops and reward spaces pick it up automatically.
]]

local Cosmetics = {}

Cosmetics.Slots = { "Hat", "Trail", "Emote" }

Cosmetics.Items = {
	{
		Id = "hat_party", Name = "Party Hat", Slot = "Hat", Price = 6, Rarity = "Common",
		Visual = { Kind = "Hat", Shape = "Cylinder", Size = { 1.4, 1.1, 1.1 }, Color = { 255, 90, 160 } },
	},
	{
		Id = "hat_crown_paper", Name = "Paper Crown", Slot = "Hat", Price = 10, Rarity = "Rare",
		Visual = { Kind = "Hat", Shape = "Block", Size = { 1.5, 0.5, 1.5 }, Color = { 255, 210, 60 } },
	},
	{
		Id = "hat_propeller", Name = "Propeller Cap", Slot = "Hat", Price = 14, Rarity = "Epic",
		Visual = { Kind = "Hat", Shape = "Ball", Size = { 1.5, 1.5, 1.5 }, Color = { 80, 160, 255 } },
	},
	{
		Id = "trail_confetti", Name = "Confetti Trail", Slot = "Trail", Price = 8, Rarity = "Common",
		Visual = { Kind = "Trail", Colors = { { 255, 220, 60 }, { 255, 90, 160 } } },
	},
	{
		Id = "trail_rainbow", Name = "Rainbow Trail", Slot = "Trail", Price = 14, Rarity = "Epic",
		Visual = { Kind = "Trail", Colors = { { 255, 80, 80 }, { 80, 140, 255 } } },
	},
	{
		Id = "emote_wave", Name = "Big Wave", Slot = "Emote", Price = 5, Rarity = "Common",
		Visual = { Kind = "Sparkles", Color = { 120, 255, 140 } },
	},
	{
		Id = "emote_spin", Name = "Victory Spin", Slot = "Emote", Price = 9, Rarity = "Rare",
		Visual = { Kind = "Sparkles", Color = { 255, 215, 0 } },
	},
}

local byId = {}
for _, item in Cosmetics.Items do
	assert(not byId[item.Id], "duplicate cosmetic id " .. item.Id)
	assert(table.find(Cosmetics.Slots, item.Slot), "unknown slot for " .. item.Id)
	byId[item.Id] = item
end

function Cosmetics.get(id: string)
	return byId[id]
end

return Cosmetics
