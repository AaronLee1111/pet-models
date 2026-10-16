--[[
	Bumper Bout (client side)
	  * DASH sends the direction you're steering in (stick / WASD, world space) so the lunge
	    goes where you mean; standing still, the server uses the way you face. The server
	    checks the request and drives the lunge itself.
	  * When the server accepts a dash it says how long the cooldown is; the DASH button
	    gets a dark shade that drains away until you can dash again.

	Main starts and stops this module (Info.ClientModule = "BumperBout").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PartyShared")
local Net = require(Shared:WaitForChild("Net"))

local BumperBoutClient = {}

local player = Players.LocalPlayer
local running = false
local connections = {}
local shade = nil -- the cooldown overlay on the DASH button
local readyAt, cooldown = 0, 1

local function dashButton(): GuiObject?
	local gui = player:FindFirstChild("PlayerGui")
	local ui = gui and gui:FindFirstChild("PartyUI")
	return ui and ui:FindFirstChild("Action_Dash", true) :: GuiObject?
end

local function clearShade()
	if shade then
		shade:Destroy()
		shade = nil
	end
end

local function showCooldown(seconds: number)
	cooldown = math.max(seconds, 0.1)
	readyAt = os.clock() + cooldown
	local button = dashButton()
	if not button then
		return
	end
	clearShade()
	shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.AnchorPoint = Vector2.new(0.5, 1)
	shade.Position = UDim2.fromScale(0.5, 1)
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.ZIndex = (button.ZIndex or 1) + 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = shade
	shade.Parent = button
end

function BumperBoutClient.start()
	BumperBoutClient.stop()
	running = true
	table.insert(
		connections,
		Net.minigameRemote().OnClientEvent:Connect(function(message)
			if type(message) == "table" and message.Type == "Cooldown" and type(message.Seconds) == "number" then
				showCooldown(message.Seconds)
			end
		end)
	)
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			if shade then
				local left = readyAt - os.clock()
				if left <= 0 then
					clearShade()
				else
					shade.Size = UDim2.fromScale(1, left / cooldown)
				end
			end
		end)
	)
end

function BumperBoutClient.stop()
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearShade()
end

-- DASH: send it with the direction I'm steering. Returns true: handled here.
function BumperBoutClient.onAction(action: string): boolean
	if not running or action ~= "Dash" then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local direction = humanoid and humanoid.MoveDirection or Vector3.zero
	Net.minigameRemote():FireServer({ Type = "Dash", X = direction.X, Z = direction.Z })
	return true
end

return BumperBoutClient
