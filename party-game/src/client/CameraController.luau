--[[
	CameraController
	Per-player scripted camera for minigames. Every client runs its own, so each player
	gets their own view of the one shared world.

	  start(cameraConfig, arenaOrigin)   CameraType -> Scriptable, mode from Info.Camera
	  setSpectating(on)                  switch to the spectator orbit cam (eliminated / spectators)
	  setTargets(chips)                  who can be spectated (alive participants)
	  cycle(direction)                   next / previous spectate target
	  stop()                             restore the normal Roblox camera

	Modes (numbers come from Config.CameraModes, overridable per minigame):
	  AngledOverhead  fixed angle over the arena centre, drifting toward you by `Follow`
	  FollowBehind    chase cam behind your character
	  SideView        side-scroller; tracks you along the arena's RightVector
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("PartyShared"):WaitForChild("Config"))

local CameraController = {}

local player = Players.LocalPlayer
local active = false
local params = nil
local arenaOrigin = CFrame.new()
local spectating = false
local targets = {} -- { { Id, Name, Character } }
local targetId = nil
local focus: Vector3? = nil
local heading: Vector3? = nil
local orbit = 0

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function currentTarget()
	for _, target in targets do
		if target.Id == targetId then
			return target
		end
	end
	return targets[1]
end

function CameraController.start(cameraConfig, origin: CFrame)
	params = cameraConfig
	arenaOrigin = origin
	active = true
	focus = nil
	heading = nil
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
end

function CameraController.isActive(): boolean
	return active
end

function CameraController.setSpectating(on: boolean)
	if on and not spectating then
		focus = nil
	end
	spectating = on
end

function CameraController.isSpectating(): boolean
	return spectating
end

-- chips: the server's player-chip list; anyone not eliminated with a body can be watched.
function CameraController.setTargets(chips)
	targets = {}
	for _, chip in chips do
		if not chip.Eliminated and chip.Character and chip.Character.Parent then
			table.insert(targets, { Id = chip.Id, Name = chip.Name, Character = chip.Character })
		end
	end
	if not currentTarget() or currentTarget().Id ~= targetId then
		local first = targets[1]
		targetId = first and first.Id
	end
end

function CameraController.cycle(direction: number)
	if #targets == 0 then
		return
	end
	local index = 1
	for i, target in targets do
		if target.Id == targetId then
			index = i
		end
	end
	index = (index - 1 + direction) % #targets + 1
	targetId = targets[index].Id
	focus = nil
end

function CameraController.getTargetName(): string?
	local target = currentTarget()
	return target and target.Name
end

function CameraController.stop()
	if not active then
		return
	end
	active = false
	spectating = false
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Per-frame camera placement ------------------------------------------------------------------

local function smoothTowards(goal: Vector3, rate: number, dt: number): Vector3
	if not focus then
		focus = goal
		return goal
	end
	local alpha = 1 - math.exp(-rate * dt)
	focus = (focus :: Vector3):Lerp(goal, alpha)
	return focus :: Vector3
end

local function spectatorCFrame(dt: number): CFrame
	local settings = Config.Spectator
	local target = currentTarget()
	local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local center = if root then root.Position else arenaOrigin.Position
	local point = smoothTowards(center, 5, dt)
	orbit += dt * settings.OrbitSpeed
	local offset = Vector3.new(math.sin(orbit) * settings.Distance, settings.Height, math.cos(orbit) * settings.Distance)
	return CFrame.lookAt(point + offset, point)
end

local function angledOverhead(dt: number): CFrame
	local center = arenaOrigin.Position
	local root = myRoot()
	local goal = if root then center:Lerp(root.Position, params.Follow) else center
	local point = smoothTowards(goal, params.Smooth, dt)
	local offset = arenaOrigin:VectorToWorldSpace(Vector3.new(0, params.Height, params.Distance))
	return CFrame.lookAt(point + offset, point)
end

local function followBehind(dt: number): CFrame
	local root = myRoot()
	if not root then
		return Workspace.CurrentCamera.CFrame
	end
	local point = smoothTowards(root.Position, params.Smooth, dt)
	-- Heading turns slower than the character so quick spins don't whip the camera.
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	heading = if heading then (heading :: Vector3):Lerp(look.Unit, 1 - math.exp(-3 * dt)) else look.Unit
	local back = (heading :: Vector3).Unit * -params.Distance + Vector3.new(0, params.Height, 0)
	return CFrame.lookAt(point + back, point + Vector3.new(0, 2, 0) + (heading :: Vector3).Unit * 6)
end

local function sideView(dt: number): CFrame
	local center = arenaOrigin.Position
	local right = arenaOrigin.RightVector
	local root = myRoot()
	local along = if root then (root.Position - center):Dot(right) else 0
	local point = smoothTowards(center + right * along, params.Smooth, dt)
	-- Stand on the side the arena faces away from, so the arena's +RightVector is screen-right.
	local eye = point - arenaOrigin.LookVector * params.Distance + Vector3.new(0, params.Height, 0)
	return CFrame.lookAt(eye, point + Vector3.new(0, 2, 0))
end

local MODES = {
	AngledOverhead = angledOverhead,
	FollowBehind = followBehind,
	SideView = sideView,
}

RunService.RenderStepped:Connect(function(dt)
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable -- respawns reset it
	end
	if spectating then
		camera.CFrame = spectatorCFrame(dt)
	else
		local mode = MODES[params.Mode] or angledOverhead
		camera.CFrame = mode(dt)
	end
end)

return CameraController
