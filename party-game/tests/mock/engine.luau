--[[
	A tiny headless stand-in for the Roblox engine, good enough to run the party framework
	end to end under Lune (https://lune-org.github.io/docs):

	  * virtual-time scheduler (task.wait / delay / spawn / defer), so a 90 s round runs in ms
	  * Instances with property/class validation against Lune's Roblox reflection database
	    (a typo'd property or wrong value type raises an error, like Studio would)
	  * signals, RemoteEvents with Roblox-style argument serialization checks
	  * crude character physics: walking (Humanoid:MoveTo), gravity, standing on parts, dying
	    below FallenPartsDestroyHeight and respawning
	  * separate server / client module caches (client sees RunService:IsServer() == false)

	It is a smoke test, not a replacement for a Studio playtest.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
local db = roblox.getReflectionDatabase()

local Engine = {}
Engine.errors = {} -- uncaught errors in any thread
Engine.warnings = {} -- warn() calls
Engine.logs = {} -- print() calls

-- Scheduler ------------------------------------------------------------------------------

local now = 0
local timers = {}
local sequence = 0
local cancelled = setmetatable({}, { __mode = "k" })

function Engine.now()
	return now
end

local function resume(thread, ...)
	if cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(Engine.errors, debug.traceback(thread, tostring(err)))
	end
end

local function schedule(at, thread, ...)
	sequence += 1
	table.insert(timers, { At = at, Seq = sequence, Thread = thread, Args = table.pack(...) })
end

local task = {}
function task.spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(now, thread, ...)
	return thread
end
function task.delay(seconds, fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(now + (seconds or 0), thread, ...)
	return thread
end
function task.wait(seconds)
	local start = now
	schedule(now + math.max(seconds or 0, 1 / 60), coroutine.running())
	coroutine.yield()
	return now - start
end
function task.cancel(thread)
	cancelled[thread] = true
end
Engine.task = task

local function runDueTimers()
	for _ = 1, 10000 do
		local bestIndex = nil
		for index, timer in timers do
			if timer.At <= now then
				local best = bestIndex and timers[bestIndex]
				if not best or timer.At < best.At or (timer.At == best.At and timer.Seq < best.Seq) then
					bestIndex = index
				end
			end
		end
		if not bestIndex then
			return
		end
		local timer = table.remove(timers, bestIndex)
		resume(timer.Thread, table.unpack(timer.Args, 1, timer.Args.n))
	end
	error("scheduler livelock")
end

-- Signals ------------------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection
function Connection:Disconnect()
	self.Connected = false
end

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _connections = {}, _waiting = {} }, Signal)
end
function Signal:Connect(fn)
	local connection = setmetatable({ Connected = true, _fn = fn }, Connection)
	table.insert(self._connections, connection)
	return connection
end
function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end
function Signal:Wait()
	table.insert(self._waiting, coroutine.running())
	return coroutine.yield()
end
function Signal:Fire(...)
	local live = {}
	for _, connection in self._connections do
		if connection.Connected then
			table.insert(live, connection)
		end
	end
	self._connections = live
	for _, connection in table.clone(live) do
		if connection.Connected then
			task.spawn(connection._fn, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, thread in waiting do
		resume(thread, ...)
	end
end
Engine.Signal = Signal

-- Instances ------------------------------------------------------------------------------

local state = setmetatable({}, { __mode = "k" }) -- instance -> internal state
local InstanceMT = {}

local function isInstance(value)
	return type(value) == "table" and state[value] ~= nil
end
Engine.isInstance = isInstance

local classCache = {}
local function classInfo(className)
	local cached = classCache[className]
	if cached then
		return cached
	end
	local properties, ancestry = {}, {}
	local current = db:GetClass(className)
	assert(current, "Unknown class " .. tostring(className))
	while current do
		ancestry[current.Name] = true
		for name, property in current.Properties do
			if properties[name] == nil then
				properties[name] = property.Datatype
			end
		end
		current = current.Superclass and db:GetClass(current.Superclass)
	end
	cached = { Properties = properties, Ancestry = ancestry }
	classCache[className] = cached
	return cached
end

local EVENTS = {
	Died = true,
	Activated = true,
	OnServerEvent = true,
	OnClientEvent = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	ChildAdded = true,
	ChildRemoved = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	RenderStepped = true,
	Stepped = true,
	Touched = true,
	Destroying = true,
	MouseButton1Click = true,
}

local DEFAULTS = {
	Health = 100,
	MaxHealth = 100,
	WalkSpeed = 16,
	JumpPower = 50,
	JumpHeight = 7.2,
	Transparency = 0,
	BackgroundTransparency = 0,
	TextTransparency = 0,
	Anchored = false,
	CanCollide = true,
	Visible = true,
	Enabled = true,
	Text = "",
	LayoutOrder = 0,
	Value = 0,
	UserId = 0,
	FallenPartsDestroyHeight = -500,
	TouchEnabled = false,
	KeyboardEnabled = true,
	Scale = 1,
	Jump = false,
}

local function defaultFor(self, key)
	local s = state[self]
	if key == "Size" and s.Info.Ancestry.BasePart then
		return Vector3.new(4, 1, 2)
	elseif key == "CFrame" then
		return CFrame.new()
	elseif key == "AssemblyLinearVelocity" or key == "AssemblyAngularVelocity" then
		return Vector3.zero
	elseif key == "Name" then
		return s.ClassName
	end
	return DEFAULTS[key]
end

local function checkType(className, key, datatype, value)
	local kind = typeof(value)
	local ok = true
	if datatype == "Bool" then
		ok = kind == "boolean"
	elseif datatype == "Float32" or datatype == "Float64" or datatype == "Int32" or datatype == "Int64" then
		ok = kind == "number"
	elseif datatype == "String" or datatype == "Content" then
		ok = kind == "string"
	elseif datatype == "Enum" then
		ok = kind == "EnumItem"
	elseif datatype == "Ref" then
		ok = value == nil or isInstance(value)
	elseif table.find({ "Vector3", "CFrame", "Color3", "UDim2", "UDim", "Vector2" }, datatype) then
		ok = kind == datatype
	end
	if not ok then
		error(("bad value for %s.%s: expected %s, got %s"):format(className, key, datatype, kind), 3)
	end
end

local Methods = {}

local function newInstance(className, parent)
	local self = setmetatable({}, InstanceMT)
	state[self] = {
		ClassName = className,
		Info = classInfo(className),
		Props = {},
		Children = {},
		Parent = nil,
		Signals = {},
		Destroyed = false,
	}
	if parent then
		self.Parent = parent
	end
	return self
end
Engine.newInstance = newInstance

local function isA(self, className)
	return state[self].Info.Ancestry[className] == true
end

local function setParent(self, parent)
	local s = state[self]
	if s.Destroyed and parent ~= nil then
		error("The Parent property of " .. s.Props.Name .. " is locked (destroyed)", 3)
	end
	if s.Parent then
		local siblings = state[s.Parent].Children
		local index = table.find(siblings, self)
		if index then
			table.remove(siblings, index)
		end
	end
	s.Parent = parent
	if parent then
		assert(isInstance(parent), "Parent must be an Instance")
		table.insert(state[parent].Children, self)
		local added = state[parent].Signals.ChildAdded
		if added then
			added:Fire(self)
		end
	end
end

InstanceMT.__index = function(self, key)
	local s = state[self]
	if key == "ClassName" then
		return s.ClassName
	elseif key == "Parent" then
		return s.Parent
	end
	local method = Methods[key]
	if method then
		return method
	end
	if EVENTS[key] then
		local signal = s.Signals[key]
		if not signal then
			signal = Signal.new()
			s.Signals[key] = signal
		end
		return signal
	end
	if key == "Position" and s.Info.Ancestry.BasePart then
		return self.CFrame.Position
	end
	if s.Info.Properties[key] ~= nil or s.Props[key] ~= nil then
		local value = s.Props[key]
		if value == nil then
			value = defaultFor(self, key)
		end
		return value
	end
	for _, child in s.Children do
		if state[child].Props.Name == key or (state[child].Props.Name == nil and state[child].ClassName == key) then
			return child
		end
	end
	error(("%s is not a valid member of %s %q"):format(tostring(key), s.ClassName, tostring(self.Name)), 2)
end

InstanceMT.__newindex = function(self, key, value)
	local s = state[self]
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local datatype = s.Info.Properties[key]
	if datatype == nil then
		error(("%s is not a valid property of %s"):format(tostring(key), s.ClassName), 2)
	end
	checkType(s.ClassName, key, datatype, value)
	if key == "Position" and s.Info.Ancestry.BasePart then
		s.Props.CFrame = CFrame.new(value) * self.CFrame.Rotation
		return
	end
	s.Props[key] = value
	if key == "Health" and s.ClassName == "Humanoid" and value <= 0 then
		Engine.kill(self)
	end
end

InstanceMT.__tostring = function(self)
	return state[self].Props.Name or state[self].ClassName
end

-- Generic methods
function Methods.IsA(self, className)
	return isA(self, className)
end
function Methods.GetChildren(self)
	return table.clone(state[self].Children)
end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(instance)
		for _, child in state[instance].Children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function Methods.FindFirstChild(self, name, recursive)
	local list = if recursive then self:GetDescendants() else state[self].Children
	for _, child in list do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function Methods.FindFirstChildOfClass(self, className)
	for _, child in state[self].Children do
		if state[child].ClassName == className then
			return child
		end
	end
	return nil
end
function Methods.FindFirstChildWhichIsA(self, className, recursive)
	local list = if recursive then self:GetDescendants() else state[self].Children
	for _, child in list do
		if isA(child, className) then
			return child
		end
	end
	return nil
end
function Methods.WaitForChild(self, name, timeout)
	local deadline = now + (timeout or 10)
	while true do
		local child = self:FindFirstChild(name)
		if child then
			return child
		end
		if now >= deadline then
			error(("WaitForChild(%q) timed out on %s"):format(name, tostring(self)), 2)
		end
		task.wait(0.05)
	end
end
function Methods.IsDescendantOf(self, ancestor)
	local current = state[self].Parent
	while current do
		if current == ancestor then
			return true
		end
		current = state[current].Parent
	end
	return false
end
function Methods.Destroy(self)
	local s = state[self]
	if s.Destroyed then
		return
	end
	for _, child in table.clone(s.Children) do
		child:Destroy()
	end
	setParent(self, nil)
	s.Destroyed = true
	for _, signal in s.Signals do
		for _, connection in signal._connections do
			connection.Connected = false
		end
	end
end
function Methods.ClearAllChildren(self)
	for _, child in table.clone(state[self].Children) do
		child:Destroy()
	end
end
function Methods.GetFullName(self)
	local parts = {}
	local current = self
	while current and state[current].ClassName ~= "DataModel" do
		table.insert(parts, 1, current.Name)
		current = state[current].Parent
	end
	return table.concat(parts, ".")
end

-- Model / BasePart
local function pivotPart(model)
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
end
function Methods.GetPivot(self)
	if isA(self, "BasePart") then
		return self.CFrame
	end
	local part = pivotPart(self)
	return if part then part.CFrame else CFrame.new()
end
function Methods.PivotTo(self, cframe)
	assert(typeof(cframe) == "CFrame", "PivotTo expects a CFrame")
	if isA(self, "BasePart") then
		self.CFrame = cframe
		return
	end
	local pivot = self:GetPivot()
	for _, part in self:GetDescendants() do
		if isA(part, "BasePart") then
			part.CFrame = cframe * pivot:ToObjectSpace(part.CFrame)
		end
	end
end
function Methods.SetNetworkOwner(self, _owner)
	assert(self:IsDescendantOf(Engine.Workspace), "SetNetworkOwner: part must be in Workspace")
	assert(not self.Anchored, "SetNetworkOwner: part is anchored")
end

-- Humanoid
function Methods.MoveTo(self, position)
	assert(typeof(position) == "Vector3", "MoveTo expects a Vector3")
	state[self].MoveTarget = position
end
function Methods.Move(self, direction)
	state[self].MoveTarget = nil
	state[self].MoveDirection = direction
end

-- RemoteEvent
local function serialize(value, path)
	local kind = type(value)
	if kind == "function" or kind == "thread" then
		error("cannot send a " .. kind .. " over a remote (" .. path .. ")", 0)
	end
	if kind ~= "table" or isInstance(value) then
		return value
	end
	if getmetatable(value) ~= nil then
		error("cannot send a table with a metatable over a remote (" .. path .. ")", 0)
	end
	local stringKeys, numberKeys = 0, 0
	local copy = {}
	for key, item in value do
		if type(key) == "string" then
			stringKeys += 1
		elseif type(key) == "number" then
			numberKeys += 1
		else
			error("non string/number key over a remote (" .. path .. ")", 0)
		end
		copy[key] = serialize(item, path .. "." .. tostring(key))
	end
	if stringKeys > 0 and numberKeys > 0 then
		error("mixed table sent over a remote (" .. path .. ")", 0)
	end
	return copy
end
local function sendToClient(remote, player, ...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = serialize(args[i], "arg" .. i)
	end
	task.defer(function()
		if player.Parent then
			remote.OnClientEvent:Fire(table.unpack(args, 1, args.n))
		end
	end)
end
function Methods.FireAllClients(self, ...)
	for _, player in Engine.Players:GetPlayers() do
		sendToClient(self, player, ...)
	end
end
function Methods.FireClient(self, player, ...)
	assert(isInstance(player) and isA(player, "Player"), "FireClient needs a Player")
	sendToClient(self, player, ...)
end
function Methods.FireServer(self, ...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = serialize(args[i], "arg" .. i)
	end
	local player = Engine.localPlayer
	task.defer(function()
		self.OnServerEvent:Fire(player, table.unpack(args, 1, args.n))
	end)
end
-- Raw access for fuzzing: lets the sim send things a real client could send.
function Engine.fireServerRaw(remote, player, ...)
	local args = table.pack(...)
	task.defer(function()
		remote.OnServerEvent:Fire(player, table.unpack(args, 1, args.n))
	end)
end

-- Services
function Methods.GetService(self, name)
	local service = self:FindFirstChild(name)
	assert(service, "unknown service " .. name)
	return service
end
function Methods.GetPlayers(_self)
	local list = {}
	for _, child in state[Engine.Players].Children do
		if isA(child, "Player") then
			table.insert(list, child)
		end
	end
	return list
end
function Methods.IsServer(_self)
	return true
end
function Methods.IsClient(_self)
	return false
end
function Methods.IsStudio(_self)
	return true
end
function Methods.GetServerTimeNow(_self)
	return now
end

-- Characters ------------------------------------------------------------------------------

local function buildRig(name)
	local model = newInstance("Model")
	model.Name = name
	local root = newInstance("Part", model)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	local head = newInstance("Part", model)
	head.Name = "Head"
	head.CFrame = CFrame.new(0, 1.5, 0)
	local humanoid = newInstance("Humanoid", model)
	humanoid.Name = "Humanoid"
	model.PrimaryPart = root
	return model
end

function Methods.CreateHumanoidModelFromDescription(_self, description, rigType)
	assert(isInstance(description) and isA(description, "HumanoidDescription"), "needs a HumanoidDescription")
	assert(typeof(rigType) == "EnumItem", "needs a HumanoidRigType")
	task.wait(0.1) -- it yields in Roblox too
	return buildRig("Rig")
end

function Methods.LoadCharacter(self)
	if self.Character then
		self.Character:Destroy()
	end
	local character = buildRig(self.Name)
	local spawn = Engine.Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	character:PivotTo(CFrame.new((if spawn then spawn.Position else Vector3.zero) + Vector3.new(0, 4, 0)))
	self.Character = character
	character.Parent = Engine.Workspace
	self.CharacterAdded:Fire(character)
end

function Engine.kill(humanoid)
	local s = state[humanoid]
	if s.Dead then
		return
	end
	s.Dead = true
	s.Props.Health = 0
	humanoid.Died:Fire()
	local model = humanoid.Parent
	for _, player in Engine.Players:GetPlayers() do
		if player.Character == model then
			task.delay(5, function()
				if player.Parent and player.Character == model then
					player:LoadCharacter()
				end
			end)
		end
	end
end

-- Physics ---------------------------------------------------------------------------------

local GRAVITY = 196.2
local HIP = 3 -- root centre height above the floor

local function aabb(part)
	local cf, size = part.CFrame, part.Size
	local function absv(v)
		return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
	end
	local extents = absv(cf.RightVector) * size.X / 2 + absv(cf.UpVector) * size.Y / 2 + absv(cf.LookVector) * size.Z / 2
	return cf.Position, extents
end

local function stepPhysics(dt)
	local floors, humanoids = {}, {}
	for _, instance in Engine.Workspace:GetDescendants() do
		local s = state[instance]
		if s.ClassName == "Humanoid" then
			table.insert(humanoids, instance)
		elseif s.Info.Ancestry.BasePart and instance.CanCollide then
			local model = instance.Parent
			if not (model and model:FindFirstChildOfClass("Humanoid")) then
				table.insert(floors, instance)
			end
		end
	end

	for _, humanoid in humanoids do
		local s = state[humanoid]
		local model = humanoid.Parent
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if s.Dead or not root then
			continue
		end
		local position = root.Position
		local delta = Vector3.zero

		-- Walk
		local target = s.MoveTarget
		if target and humanoid.WalkSpeed > 0 then
			local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
			local distance = flat.Magnitude
			if distance > 0.05 then
				delta += flat.Unit * math.min(distance, humanoid.WalkSpeed * dt)
			end
		end

		-- Find the highest floor under the feet
		local feet = position.Y - HIP
		local groundTop = nil
		for _, part in floors do
			local center, extents = aabb(part)
			if math.abs(position.X - center.X) <= extents.X and math.abs(position.Z - center.Z) <= extents.Z then
				local top = center.Y + extents.Y
				if top <= feet + 0.6 and (groundTop == nil or top > groundTop) then
					groundTop = top
				end
			end
		end

		local velocity = root.AssemblyLinearVelocity
		local vy = velocity.Y
		local grounded = groundTop ~= nil and feet <= groundTop + 0.05 and vy <= 0
		if grounded then
			vy = 0
			delta += Vector3.new(0, groundTop - feet, 0)
			if humanoid.Jump and humanoid.JumpPower > 0 then
				vy = 50
			end
			humanoid.Jump = false
		end
		if not grounded or vy > 0 then
			vy -= GRAVITY * dt
			local dy = vy * dt
			if groundTop and feet + dy < groundTop then
				dy = groundTop - feet
				vy = 0
			end
			delta += Vector3.new(0, dy, 0)
		end
		root.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
		if delta.Magnitude > 0 then
			model:PivotTo(model:GetPivot() + delta)
		end

		if root.Position.Y < Engine.Workspace.FallenPartsDestroyHeight then
			Engine.kill(humanoid)
			model:Destroy()
		end
	end
end

-- World / loading ---------------------------------------------------------------------------

local game = newInstance("DataModel")
Engine.game = game
local function service(className)
	local instance = newInstance(className, game)
	state[instance].Props.Name = className
	return instance
end
Engine.Workspace = service("Workspace")
Engine.Players = service("Players")
Engine.ReplicatedStorage = service("ReplicatedStorage")
Engine.ServerScriptService = service("ServerScriptService")
Engine.StarterPlayer = service("StarterPlayer")
Engine.RunService = service("RunService")
Engine.TweenService = service("TweenService")
Engine.ContextActionService = service("ContextActionService")
Engine.UserInputService = service("UserInputService")
local starterPlayerScripts = newInstance("StarterPlayerScripts", Engine.StarterPlayer)
starterPlayerScripts.Name = "StarterPlayerScripts"

-- TweenService:Create applies the goal when the tween finishes.
function Methods.Create(_self, instance, info, goals)
	assert(isInstance(instance), "Tween target must be an Instance")
	for key, value in goals do
		instance[key] = instance[key] -- validates the property exists
		checkType(instance.ClassName, key, state[instance].Info.Properties[key], value)
	end
	local tween = { Completed = Signal.new() }
	function tween.Play(t)
		task.delay(info.Time, function()
			if not state[instance].Destroyed then
				for key, value in goals do
					instance[key] = value
				end
			end
			t.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween.Cancel(_t) end
	return tween
end

-- ContextActionService: remember bindings so the sim can "press" them.
Engine.boundActions = {}
function Methods.BindAction(_self, name, handler, _createTouchButton, ...)
	assert(type(handler) == "function", "BindAction handler")
	for _, input in { ... } do
		assert(typeof(input) == "EnumItem", "BindAction inputs must be EnumItems")
	end
	Engine.boundActions[name] = handler
end
function Methods.UnbindAction(_self, name)
	Engine.boundActions[name] = nil
end
function Methods.SetTitle(_self, name, title)
	assert(type(title) == "string", "SetTitle")
	assert(Engine.boundActions[name], "SetTitle on unbound action " .. name)
end

local TweenInfo = {
	new = function(time, ...)
		return { Time = time or 1, Args = { ... } }
	end,
}

local RandomClass = {}
RandomClass.__index = RandomClass
function RandomClass:NextNumber(min, max)
	min, max = min or 0, max or 1
	return min + math.random() * (max - min)
end
function RandomClass:NextInteger(min, max)
	assert(min <= max, ("NextInteger(%d, %d): empty range"):format(min, max))
	return math.random(min, max)
end
local Random = {
	new = function()
		return setmetatable({}, RandomClass)
	end,
}

local mockOs = setmetatable({
	clock = function()
		return now
	end,
	time = function()
		return now
	end,
}, { __index = os })

local function makeGlobals(side)
	local clientRunService = {
		IsServer = function()
			return false
		end,
		IsClient = function()
			return true
		end,
		Heartbeat = Engine.RunService.Heartbeat,
		RenderStepped = Engine.RunService.RenderStepped,
	}
	local sideGame = if side == "server"
		then game
		else setmetatable({
			GetService = function(_, name)
				if name == "RunService" then
					return clientRunService
				end
				return game:GetService(name)
			end,
		}, {
			__index = function(_, key)
				error("client sim: use game:GetService, not game." .. tostring(key))
			end,
		})

	return {
		game = sideGame,
		workspace = Engine.Workspace,
		Instance = {
			new = function(className, parent)
				return newInstance(className, parent)
			end,
		},
		task = task,
		os = mockOs,
		print = function(...)
			table.insert(Engine.logs, table.concat(table.pack(...) :: any, " "))
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(Engine.warnings, table.concat(parts, " "))
		end,
		Vector3 = Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = Enum,
		TweenInfo = TweenInfo,
		Random = Random,
		typeof = function(value)
			if isInstance(value) then
				return "Instance"
			end
			return typeof(value)
		end,
		math = math,
		table = table,
		string = string,
		utf8 = utf8,
		coroutine = coroutine,
		debug = debug,
		bit32 = bit32,
		buffer = buffer,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		select = select,
		pcall = pcall,
		xpcall = xpcall,
		error = error,
		assert = assert,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		unpack = table.unpack,
	}
end

local sides = {
	server = { Globals = makeGlobals("server"), Cache = {} },
	client = { Globals = makeGlobals("client"), Cache = {} },
}

local loadChunk

local function sideRequire(module, sideName)
	assert(isInstance(module) and isA(module, "ModuleScript"), "require expects a ModuleScript")
	local cache = sides[sideName].Cache
	local cached = cache[module]
	if cached then
		return cached.Value
	end
	local value = loadChunk(module, sideName)()
	cache[module] = { Value = value }
	return value
end

function loadChunk(scriptInstance, sideName)
	local path = state[scriptInstance].SourcePath
	local env = setmetatable({ script = scriptInstance }, { __index = sides[sideName].Globals })
	env.require = function(module)
		return sideRequire(module, sideName)
	end
	return luau.load(state[scriptInstance].Source, { debugName = path, environment = env, injectGlobals = false })
end

-- Mounts a folder of .luau files like Rojo does (init files are not supported/needed here).
function Engine.mount(directory, parent, name)
	local folder = newInstance("Folder", parent)
	folder.Name = name
	for _, entry in fs.readDir(directory) do
		local full = directory .. "/" .. entry
		if fs.isDir(full) then
			Engine.mount(full, folder, entry)
		elseif string.sub(entry, -5) == ".luau" then
			local base = string.sub(entry, 1, -6)
			local className = "ModuleScript"
			if string.sub(base, -7) == ".server" then
				className, base = "Script", string.sub(base, 1, -8)
			elseif string.sub(base, -7) == ".client" then
				className, base = "LocalScript", string.sub(base, 1, -8)
			end
			local scriptInstance = newInstance(className, folder)
			scriptInstance.Name = base
			state[scriptInstance].SourcePath = full
			-- Read now: Lune's fs calls yield, which would confuse the virtual scheduler later.
			state[scriptInstance].Source = fs.readFile(full)
		end
	end
	return folder
end

function Engine.runScript(scriptInstance, sideName)
	task.spawn(loadChunk(scriptInstance, sideName))
end

function Engine.requireAs(module, sideName)
	return sideRequire(module, sideName)
end

-- Players ------------------------------------------------------------------------------------

function Engine.addPlayer(name, userId)
	local player = newInstance("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	local gui = newInstance("PlayerGui", player)
	gui.Name = "PlayerGui"
	player.Parent = Engine.Players
	Engine.Players.PlayerAdded:Fire(player)
	player:LoadCharacter()
	return player
end

function Engine.removePlayer(player)
	Engine.Players.PlayerRemoving:Fire(player)
	if player.Character then
		player.Character:Destroy()
	end
	player.Parent = nil
end

-- Main loop ------------------------------------------------------------------------------------

local FRAME = 1 / 30
function Engine.run(seconds, onFrame)
	local stopAt = now + seconds
	while now < stopAt do
		now += FRAME
		Engine.RunService.Heartbeat:Fire(FRAME)
		Engine.RunService.RenderStepped:Fire(FRAME)
		stepPhysics(FRAME)
		runDueTimers()
		if onFrame and onFrame() then
			return true
		end
	end
	return false
end

function Engine.state(instance)
	return state[instance]
end

return Engine
