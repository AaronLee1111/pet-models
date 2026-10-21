--[[
	TutorialPreview
	Plays a minigame's tutorial preview (Info.Tutorial.Preview, validated by the server's
	MinigameInfo) in a ViewportFrame: a tiny staged loop of the round's real avatars and
	simple props. Purely local and isolated: nothing here touches live gameplay.

	  local preview = TutorialPreview.new(parent)    fills `parent`
	  preview:play(spec, participants)                spec nil = the generic preview
	  preview:stop()
	  preview.Loops                                   loops completed since play()

	Step vocabulary (all data): Actor/Prop + To (+Time) move, Jump, Visible, Attach (prop rides
	on an actor's head; 0 lets go), Color, Pulse, Caption. Props may be Upright (cylinders
	stand up) or Hidden at the start; actors may Face a point. Everything resets each loop.
]]

local RunService = game:GetService("RunService")

local ActivePlayerPortrait = require(script.Parent.ActivePlayerPortrait)
local Theme = require(script.Parent.Theme)
local make = Theme.make

local TutorialPreview = {}
TutorialPreview.__index = TutorialPreview

local JUMP_TIME, JUMP_HEIGHT = 0.5, 2.6
local PULSE_TIME = 0.35
local CAPTION_TIME = 0.9
local TEAM_RING = { Color3.fromRGB(232, 96, 96), Color3.fromRGB(90, 150, 240) }

-- Shown when a minigame has no (valid) preview: everyone on a stage, hopping, "GET READY!".
local function genericSpec(count: number)
	local actors, steps = {}, {}
	for i = 1, math.max(1, count) do
		local x = (i - (count + 1) / 2) * 3.4
		table.insert(actors, { Start = Vector3.new(x, 0, 0) })
		table.insert(steps, { At = 0.6 + i * 0.45, Actor = i, Jump = true })
	end
	table.insert(steps, { At = 0.3, Caption = "GET READY!" })
	return {
		Loop = 4,
		Camera = { Position = Vector3.new(0, 7, 15), LookAt = Vector3.new(0, 2.2, 0) },
		Actors = actors,
		Props = {
			{ Id = "Stage", Shape = "Cylinder", Upright = true, Size = Vector3.new(1, 18, 18), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(120, 196, 170) },
		},
		Steps = steps,
	}
end
TutorialPreview.genericSpec = genericSpec

-- A simple block figure for actors without an avatar to copy.
local function dummy(colour: Color3): Model
	local model = Instance.new("Model")
	local function part(name, size, offset, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Shape = shape or Enum.PartType.Block
		p.Color = colour
		p.Anchored = true
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		return p
	end
	local torso = part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	part("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 4.7, 0), Enum.PartType.Ball).Color = Color3.fromRGB(255, 226, 190)
	part("LeftLeg", Vector3.new(0.9, 2, 1), Vector3.new(-0.5, 1, 0))
	part("RightLeg", Vector3.new(0.9, 2, 1), Vector3.new(0.5, 1, 0))
	part("LeftArm", Vector3.new(0.8, 1.9, 0.9), Vector3.new(-1.45, 3, 0))
	part("RightArm", Vector3.new(0.8, 1.9, 0.9), Vector3.new(1.45, 3, 0))
	model.PrimaryPart = torso
	return model
end

function TutorialPreview.new(parent: GuiObject)
	local self = setmetatable({ Loops = 0 }, TutorialPreview)
	self.Frame = make("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(176, 222, 236),
		Ambient = Color3.fromRGB(190, 190, 190),
		LightColor = Color3.fromRGB(255, 244, 222),
		LightDirection = Vector3.new(-0.6, -1, -0.4),
		Parent = parent,
	}, { Theme.corner(18) })
	self.Captions = make("Frame", { Name = "Captions", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = parent })
	return self
end

local function lerpEase(a, b, u: number)
	local e = 1 - (1 - u) * (1 - u)
	return a:Lerp(b, e)
end

-- World point -> position inside the ViewportFrame (Camera.FieldOfView is vertical).
local function project(camera: Camera, point: Vector3, size: Vector2): UDim2?
	local rel = camera.CFrame:PointToObjectSpace(point)
	if rel.Z >= -0.1 then
		return nil
	end
	local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
	local aspect = size.X / math.max(1, size.Y)
	local x = (rel.X / -rel.Z) / (tanY * aspect)
	local y = (rel.Y / -rel.Z) / tanY
	return UDim2.fromScale(0.5 + x / 2, 0.5 - y / 2)
end

function TutorialPreview:stop()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	for _, child in self.Frame:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	for _, child in self.Captions:GetChildren() do
		child:Destroy()
	end
end

function TutorialPreview:play(spec, participants)
	self:stop()
	participants = participants or {}
	spec = spec or genericSpec(#participants)
	self.Loops = 0
	local world = make("WorldModel", { Parent = self.Frame })
	local camera = make("Camera", { FieldOfView = 42, CFrame = CFrame.lookAt(spec.Camera.Position, spec.Camera.LookAt), Parent = self.Frame })
	self.Frame.CurrentCamera = camera

	-- Props
	local props = {}
	for _, info in spec.Props or {} do
		local part = Instance.new("Part")
		part.Shape = if info.Shape == "Ball" then Enum.PartType.Ball elseif info.Shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		part.Size = info.Size
		part.Color = info.Color
		part.Material = if info.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Parent = world
		props[info.Id] = { Part = part, Info = info, Turn = if info.Upright then CFrame.Angles(0, 0, math.rad(90)) else CFrame.new() }
	end

	-- Actors: the round's avatars (copies), block figures for the rest.
	local actors = {}
	for index, info in spec.Actors do
		local participant = participants[index]
		local model = participant and ActivePlayerPortrait.copy(participant.Character)
		if not model then
			model = dummy(if info.Team then TEAM_RING[info.Team] else Color3.fromRGB(200, 200, 210))
		end
		model.Parent = world
		local box, size = model:GetBoundingBox()
		local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2) -- pivot above the feet
		local ring
		if info.Team then
			ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.12, 3.2, 3.2)
			ring.Color = TEAM_RING[info.Team]
			ring.Material = Enum.Material.Neon
			ring.Anchored = true
			ring.Parent = world
		end
		actors[index] = { Model = model, Info = info, Lift = lift, Height = size.Y, Ring = ring }
	end

	local function caption(text: string, actorIndex: number?)
		local label = make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(220, 44),
			BackgroundTransparency = 1,
			Font = Theme.TitleFont,
			TextSize = 34,
			TextColor3 = Theme.Glass.Cream,
			Text = text,
			Parent = self.Captions,
		}, { make("UIStroke", { Color = Theme.Glass.Deep, Thickness = 3 }) })
		return { Label = label, Actor = actorIndex, Start = 0 }
	end

	local run -- per-loop state
	local function reset()
		run = { Applied = {}, Moves = {}, Jumps = {}, Pulses = {}, Attach = {}, Captions = {}, Pos = {}, PropPos = {} }
		for _, child in self.Captions:GetChildren() do
			child:Destroy()
		end
		for id, prop in props do
			prop.Part.Color = prop.Info.Color
			prop.Part.Size = prop.Info.Size
			prop.Part.Transparency = if prop.Info.Hidden then 1 else (prop.Info.Transparency or 0)
			run.PropPos[id] = prop.Info.Position
		end
		for index, actor in actors do
			run.Pos[index] = actor.Info.Start
		end
	end

	local function apply(step, t: number)
		if step.Actor and step.To then
			run.Moves["a" .. step.Actor] = { From = run.Pos[step.Actor], To = step.To, Start = t, Time = step.Time or 0.6 }
		elseif step.Prop and step.To then
			run.Moves["p" .. step.Prop] = { From = run.PropPos[step.Prop], To = step.To, Start = t, Time = step.Time or 0.6 }
			run.Attach[step.Prop] = nil
		end
		if step.Actor and step.Jump then
			run.Jumps[step.Actor] = t
		end
		if step.Prop then
			local prop = props[step.Prop]
			if step.Visible ~= nil then
				prop.Part.Transparency = if step.Visible then (prop.Info.Transparency or 0) else 1
			end
			if step.Color then
				prop.Part.Color = step.Color
			end
			if step.Pulse then
				run.Pulses[step.Prop] = t
			end
			if step.Attach ~= nil then
				run.Attach[step.Prop] = if step.Attach == 0 then nil else step.Attach
			end
		end
		if step.Caption then
			local c = caption(step.Caption, step.Actor)
			c.Start = t
			table.insert(run.Captions, c)
		end
	end

	reset()
	local started = os.clock()
	local lastLoop = 0
	self.Connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local loop = math.floor(elapsed / spec.Loop)
		if loop ~= lastLoop then
			lastLoop = loop
			self.Loops = loop
			reset()
		end
		local t = elapsed - loop * spec.Loop
		for index, step in spec.Steps or {} do
			if not run.Applied[index] and step.At <= t then
				run.Applied[index] = true
				apply(step, t)
			end
		end
		-- moves
		for key, move in run.Moves do
			local u = math.clamp((t - move.Start) / math.max(0.01, move.Time), 0, 1)
			local position = lerpEase(move.From, move.To, u)
			local kind, id = string.sub(key, 1, 1), string.sub(key, 2)
			if kind == "a" then
				run.Pos[tonumber(id)] = position
			else
				run.PropPos[id] = position
			end
			if u >= 1 then
				run.Moves[key] = nil
			end
		end
		-- actors
		for index, actor in actors do
			local position = run.Pos[index]
			local jumpAt = run.Jumps[index]
			local hop = 0
			if jumpAt then
				local u = (t - jumpAt) / JUMP_TIME
				hop = if u < 1 then 4 * JUMP_HEIGHT * u * (1 - u) else 0
			end
			local bob = math.sin(elapsed * 3 + index) * 0.05
			local face = actor.Info.Face or Vector3.new(spec.Camera.Position.X, position.Y, spec.Camera.Position.Z)
			local move = run.Moves["a" .. index]
			if move and not actor.Info.Face then
				face = position + (move.To - move.From) * Vector3.new(1, 0, 1)
			end
			local from = position + Vector3.new(0, actor.Lift + hop + bob, 0)
			local look = Vector3.new(face.X, from.Y, face.Z)
			actor.Model:PivotTo(if (look - from).Magnitude > 0.05 then CFrame.lookAt(from, look) else CFrame.new(from))
			if actor.Ring then
				actor.Ring.CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		-- props
		for id, prop in props do
			local position = run.PropPos[id]
			local rider = run.Attach[id]
			if rider and actors[rider] then
				position = run.Pos[rider] + Vector3.new(0, actors[rider].Height + 0.9, 0)
				run.PropPos[id] = position
			end
			local pulseAt = run.Pulses[id]
			local grow = 1
			if pulseAt then
				local u = (t - pulseAt) / PULSE_TIME
				grow = if u < 1 then 1 + 0.35 * math.sin(math.pi * u) else 1
			end
			prop.Part.Size = prop.Info.Size * grow
			prop.Part.CFrame = CFrame.new(position) * prop.Turn
		end
		-- captions: over their actor's head, or high in the middle
		local size = self.Frame.AbsoluteSize
		for _, c in run.Captions do
			local u = (t - c.Start) / CAPTION_TIME
			if u >= 1 then
				c.Label.Visible = false
				continue
			end
			local at = if c.Actor and actors[c.Actor] then project(camera, run.Pos[c.Actor] + Vector3.new(0, actors[c.Actor].Height + 1.6, 0), size) else UDim2.fromScale(0.5, 0.22)
			c.Label.Visible = at ~= nil
			if at then
				-- keep it inside the preview (heads near the top edge would push it out)
				at = UDim2.fromScale(math.clamp(at.X.Scale, 0.15, 0.85), math.clamp(at.Y.Scale, 0.16, 0.95))
				c.Label.Position = at - UDim2.fromOffset(0, u * 14)
				c.Label.TextTransparency = math.max(0, (u - 0.6) / 0.4)
			end
		end
	end)
end

return TutorialPreview
