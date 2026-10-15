--[[
	CosmeticService
	Makes equipped cosmetics (Inventory) visible on characters, players and bots alike, and
	handles equip / unequip requests from clients.

	Drawing is self-healing: every REFRESH_INTERVAL it compares each character's drawn
	cosmetics with what its owner has equipped and redraws on any difference. That covers
	respawns, resets, board <-> minigame teleports, bot respawns and bot takeovers without
	hooking each one. Placeholder looks come from Cosmetics.Items[].Visual.

	Clients can only ask; requestEquip checks ownership through Inventory.equip.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Cosmetics = require(ReplicatedStorage.PartyShared.Cosmetics)
local Net = require(ReplicatedStorage.PartyShared.Net)
local Inventory = require(script.Parent.Inventory)

local CosmeticService = {}

local REFRESH_INTERVAL = 0.5
local TAG = "PartyCosmetic" -- name prefix of everything we add to a character
local KEY_ATTRIBUTE = "PartyCosmeticKey"

local sendToPlayer: ((Player, any) -> ())? = nil
local bankCoinsOf: ((Player) -> number)? = nil

local function color(rgb): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Stable text describing an equipped set, e.g. "Hat=hat_party;Trail=trail_rainbow".
function CosmeticService.keyOf(equipped): string
	local parts = {}
	for _, slot in Cosmetics.Slots do
		if equipped[slot] then
			table.insert(parts, slot .. "=" .. equipped[slot])
		end
	end
	return table.concat(parts, ";")
end

local function clear(character: Model)
	for _, descendant in character:GetDescendants() do
		if string.sub(descendant.Name, 1, #TAG) == TAG then
			descendant:Destroy()
		end
	end
end

local function drawHat(character: Model, visual)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local size = Vector3.new(visual.Size[1], visual.Size[2], visual.Size[3])
	local hat = Instance.new("Part")
	hat.Name = TAG .. "_Hat"
	hat.Shape = Enum.PartType[visual.Shape] or Enum.PartType.Block
	hat.Size = size
	hat.Color = color(visual.Color)
	hat.Material = Enum.Material.SmoothPlastic
	hat.CanCollide = false
	hat.CanQuery = false
	hat.CanTouch = false
	hat.Massless = true
	-- Cylinders run along X: stand them up.
	local height = if hat.Shape == Enum.PartType.Cylinder then size.X else size.Y
	local tilt = if hat.Shape == Enum.PartType.Cylinder then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity
	hat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + height / 2 - 0.1, 0) * tilt
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = hat
	weld.Parent = hat
	hat.Parent = character
end

local function drawTrail(character: Model, visual)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = TAG .. "_TrailTop"
	top.Position = Vector3.new(0, 0.8, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = TAG .. "_TrailBottom"
	bottom.Position = Vector3.new(0, -0.8, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = TAG .. "_Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.45
	trail.Color = ColorSequence.new(color(visual.Colors[1]), color(visual.Colors[2]))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = root
end

local function drawSparkles(character: Model, visual)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local sparkles = Instance.new("Sparkles")
	sparkles.Name = TAG .. "_Sparkles"
	sparkles.SparkleColor = color(visual.Color)
	sparkles.Parent = root
end

local drawers = { Hat = drawHat, Trail = drawTrail, Sparkles = drawSparkles }

-- Redraws a character's cosmetics to match `equipped` ({ [slot] = itemId }).
function CosmeticService.apply(character: Model, equipped)
	clear(character)
	for _, slot in Cosmetics.Slots do
		local item = equipped[slot] and Cosmetics.get(equipped[slot])
		local draw = item and item.Visual and drawers[item.Visual.Kind]
		if draw then
			draw(character, item.Visual)
		end
	end
	character:SetAttribute(KEY_ATTRIBUTE, CosmeticService.keyOf(equipped))
end

local function refresh(character: Model?, ownerId: string)
	if not character or not character.Parent or not character:FindFirstChild("Head") then
		return
	end
	local equipped = Inventory.getEquipped(ownerId)
	if character:GetAttribute(KEY_ATTRIBUTE) ~= CosmeticService.keyOf(equipped) then
		CosmeticService.apply(character, equipped)
	end
end

function CosmeticService.refreshAll()
	for _, player in Players:GetPlayers() do
		refresh(player.Character, "player_" .. player.UserId)
	end
	local bots = Workspace:FindFirstChild("PartyBots")
	for _, model in if bots then bots:GetChildren() else {} do
		local id = model:GetAttribute("PartyId")
		if model:IsA("Model") and type(id) == "string" then
			refresh(model, id)
		end
	end
end

-- Equip requests -----------------------------------------------------------------------------

-- Equip an owned cosmetic. Anything unowned or unknown is refused (returns false).
function CosmeticService.requestEquip(ownerId: string, itemId): boolean
	if type(itemId) ~= "string" then
		return false
	end
	return Inventory.equip(ownerId, itemId)
end

function CosmeticService.requestUnequip(ownerId: string, slot): boolean
	if type(slot) ~= "string" or not table.find(Cosmetics.Slots, slot) then
		return false
	end
	Inventory.unequip(ownerId, slot)
	return true
end

-- What a player's client needs for the wardrobe.
function CosmeticService.inventoryMessage(player: Player)
	local ownerId = "player_" .. player.UserId
	local owned = {}
	for _, itemId in Inventory.getOwned(ownerId) do
		local item = Cosmetics.get(itemId)
		if item then
			table.insert(owned, { Id = item.Id, Name = item.Name, Slot = item.Slot })
		end
	end
	return {
		Type = Net.Message.Inventory,
		Owned = owned,
		Equipped = Inventory.getEquipped(ownerId),
		BankCoins = if bankCoinsOf then bankCoinsOf(player) else 0,
	}
end

function CosmeticService.sendInventory(player: Player)
	if sendToPlayer and player.Parent then
		sendToPlayer(player, CosmeticService.inventoryMessage(player))
	end
end

function CosmeticService.handleInput(player: Player, payload): boolean
	local ownerId = "player_" .. player.UserId
	if payload.Kind == Net.Input.Equip then
		CosmeticService.requestEquip(ownerId, payload.ItemId)
	elseif payload.Kind == Net.Input.Unequip then
		CosmeticService.requestUnequip(ownerId, payload.Slot)
	else
		return false
	end
	CosmeticService.sendInventory(player) -- also corrects a client that guessed wrong
	return true
end

--[[
	Starts the redraw loop and wires messages. send(player, message) delivers to one client;
	getBankCoins(player) -> number shows permanent coins in the wardrobe (Profiles).
]]
function CosmeticService.start(send: (Player, any) -> (), getBankCoins: ((Player) -> number)?)
	sendToPlayer = send
	bankCoinsOf = getBankCoins
	Inventory.onChanged(function(ownerId)
		local userId = tonumber(string.match(ownerId, "^player_(%d+)$"))
		local player = userId and Players:GetPlayerByUserId(userId)
		if player then
			CosmeticService.sendInventory(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		Inventory.forget("player_" .. player.UserId)
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(CosmeticService.refreshAll)
			if not ok then
				warn("[CosmeticService] " .. tostring(err))
			end
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return CosmeticService
