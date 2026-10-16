--[[
	Trail Tangle (client side)
	Presentation only. The server decides every move; it sends one small "Tick" message per
	grid step with each rider's cell, heading and whether they're still in. Here the riders
	glide from their previous cell to the new one over that step's length, so nobody visibly
	hops cell to cell. Bodies are anchored by the server; this module positions them every
	frame just before the camera updates.

	Main starts and stops this module (Info.ClientModule = "TrailTangle"). Turn buttons go
	straight to the server (onAction returns false).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PartyShared")
local Net = require(Shared:WaitForChild("Net"))

local TrailTangleClient = {}

local BIND_NAME = "PartyTrailTangleClient"
local YAW = { 0, -math.pi / 2, math.pi, math.pi / 2 } -- by direction: north, east, south, west

local running = false
local connections = {}
local grid = nil -- { Origin, Cell, Width, Height }
local riders = {} -- [index] = { Character, Height, From, To, FromYaw, ToYaw, Alive }
local stepStart, stepLength = 0, 0.3
local lastDrawAt = 0

local function cellPosition(x: number, y: number): Vector3
	return Vector3.new((x - (grid.Width - 1) / 2) * grid.Cell, 0, (y - (grid.Height - 1) / 2) * grid.Cell)
end

-- Shortest way round from one heading to another.
local function lerpAngle(a: number, b: number, t: number): number
	local delta = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + delta * t
end

local function draw()
	if not running or not grid then
		return
	end
	lastDrawAt = os.clock()
	local t = math.clamp((os.clock() - stepStart) / math.max(stepLength, 0.05), 0, 1)
	for _, rider in riders do
		local character = rider.Character
		if rider.Alive and rider.To and character and character.Parent then
			local position = rider.From:Lerp(rider.To, t)
			-- Turn quickly at the start of the step rather than drifting round the whole way.
			local yaw = lerpAngle(rider.FromYaw, rider.ToYaw, math.min(1, t * 3))
			character:PivotTo(grid.Origin * CFrame.new(position + Vector3.new(0, rider.Height, 0)) * CFrame.Angles(0, yaw, 0))
		end
	end
end

local function onSetup(message)
	grid = { Origin = message.Origin, Cell = message.Cell, Width = message.Width, Height = message.Height }
	riders = {}
	for index, entry in message.Riders do
		riders[index] = { Character = entry.Character, Height = entry.Height, Alive = true }
	end
end

local function onTick(message)
	if not grid or type(message.R) ~= "table" then
		return
	end
	-- Finish the previous glide first, so a late message never jumps backwards.
	for index, entry in message.R do
		local rider = riders[index]
		if rider then
			local to = cellPosition(entry[1], entry[2])
			rider.From = rider.To or to
			rider.FromYaw = rider.ToYaw or YAW[entry[3]]
			rider.To = to
			rider.ToYaw = YAW[entry[3]]
			rider.Alive = entry[4] == true
		end
	end
	stepStart = os.clock()
	stepLength = if type(message.I) == "number" then message.I else stepLength
end

function TrailTangleClient.start()
	TrailTangleClient.stop()
	running = true
	grid = nil
	riders = {}
	table.insert(
		connections,
		Net.minigameRemote().OnClientEvent:Connect(function(message)
			if type(message) ~= "table" then
				return
			end
			if message.Type == "Setup" then
				onSetup(message)
			elseif message.Type == "Tick" then
				onTick(message)
			end
		end)
	)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 5, draw)
	-- Render steps pause while the window isn't drawn; keep bodies roughly right anyway.
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			if os.clock() - lastDrawAt > 0.25 then
				draw()
			end
		end)
	)
end

function TrailTangleClient.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	grid = nil
	riders = {}
end

-- Turns are decided on the server: let Main send them.
function TrailTangleClient.onAction(_action: string): boolean
	return false
end

return TrailTangleClient
