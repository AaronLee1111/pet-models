--[[
	CoinService
	Session coin totals. Real players get a "Coins" leaderstat; bots are tracked in memory.
	(Swap this for DataStore persistence once the board game exists.)
]]

local Players = game:GetService("Players")

local CoinService = {}

local botCoins: { [string]: number } = {}

local function setupPlayer(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

local function getValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Coins") :: IntValue?
end

function CoinService.get(participant): number
	if participant.IsBot then
		return botCoins[participant.Id] or 0
	end
	local value = getValue(participant.Player)
	return if value then value.Value else 0
end

-- Adds coins and returns the new total.
function CoinService.add(participant, amount: number): number
	if participant.IsBot then
		botCoins[participant.Id] = (botCoins[participant.Id] or 0) + amount
		return botCoins[participant.Id]
	end
	local value = getValue(participant.Player)
	if value then
		value.Value += amount
		return value.Value
	end
	return 0
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	if not player:FindFirstChild("leaderstats") then
		setupPlayer(player)
	end
end

return CoinService
