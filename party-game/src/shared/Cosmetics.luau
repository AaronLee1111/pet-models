--[[
	Cosmetics
	The catalog of cosmetic items. Pure data, readable by server and client.

	Each item:
	  Id      unique, never reuse or rename once players own it
	  Name    shown to players
	  Slot    one equipped item per slot (Cosmetics.Slots)
	  Price   coins at a shop space
	  Rarity  "Common" | "Rare" | "Epic" (for the later visual pass)

	Placeholders: nothing is drawn on the character yet (see BACKLOG.md).
	To add one, append an entry; shops and reward spaces pick it up automatically.
]]

local Cosmetics = {}

Cosmetics.Slots = { "Hat", "Trail", "Emote" }

Cosmetics.Items = {
	{ Id = "hat_party", Name = "Party Hat", Slot = "Hat", Price = 6, Rarity = "Common" },
	{ Id = "hat_crown_paper", Name = "Paper Crown", Slot = "Hat", Price = 10, Rarity = "Rare" },
	{ Id = "hat_propeller", Name = "Propeller Cap", Slot = "Hat", Price = 14, Rarity = "Epic" },
	{ Id = "trail_confetti", Name = "Confetti Trail", Slot = "Trail", Price = 8, Rarity = "Common" },
	{ Id = "trail_rainbow", Name = "Rainbow Trail", Slot = "Trail", Price = 14, Rarity = "Epic" },
	{ Id = "emote_wave", Name = "Big Wave", Slot = "Emote", Price = 5, Rarity = "Common" },
	{ Id = "emote_spin", Name = "Victory Spin", Slot = "Emote", Price = 9, Rarity = "Rare" },
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
