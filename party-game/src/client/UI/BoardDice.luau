--[[
	BoardDice
	The thrown-dice moment on every board (DicePrompt's hovering die is the same die). Purely
	local presentation: the server has already decided the number (state.DiceFaces); this only
	shows it.

	  1. The roller hops (a short crouch-and-jump on their piece).
	  2. One die per rolled die leaves from above their head and tumbles in an arc onto the board
	     beside them, toward the camera so it's in view.
	  3. It bounces once and settles with the rolled face up.
	  4. The number pops above it (the total too, for two or three dice), then it fades as the
	     piece starts hopping.

	  dice:throw(character, count)          start now (the local player pressing ROLL)
	  dice:reveal(character, faces, rollId) the server's result: finish an ongoing throw, or
	                                        play the whole thing (everyone else, bots)
	  dice:clear()

	Timing fits inside Config.Board.DiceReveal (players) / DiceRevealBot (bots): a full throw
	takes ~1.5 s, the short (bot) version ~1.0 s. Reduced motion: no tumble, the dice just
	appear showing their faces.
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local BoardDice = {}
BoardDice.__index = BoardDice

local SIZE = 3.4
local FLIGHT = 0.75 -- seconds in the air (full version)
local FLIGHT_SHORT = 0.5
local MIN_TUMBLE = 0.6 -- the local throw never settles sooner than this, even on a fast server
-- The throw starts where DicePrompt's die hovers (kept in sync with DicePrompt.HOVER).
local HOVER = Vector3.new(0, if game:GetService("UserInputService").TouchEnabled then 5.5 else 8.4, 0)

-- Number n is printed on FACES[n].Face; FACES[n].Up is the rotation that turns that face to
-- point up (+Y). Opposite faces add up to 7, like a real die.
local FACES = {
	{ Face = Enum.NormalId.Top, Up = CFrame.new() },
	{ Face = Enum.NormalId.Front, Up = CFrame.Angles(math.rad(90), 0, 0) },
	{ Face = Enum.NormalId.Right, Up = CFrame.Angles(0, 0, math.rad(90)) },
	{ Face = Enum.NormalId.Left, Up = CFrame.Angles(0, 0, math.rad(-90)) },
	{ Face = Enum.NormalId.Back, Up = CFrame.Angles(math.rad(-90), 0, 0) },
	{ Face = Enum.NormalId.Bottom, Up = CFrame.Angles(math.rad(180), 0, 0) },
}

-- The direction a face's printed number calls "up", in the die's own space (SurfaceGui
-- convention: side faces read along +Y; Top and Bottom measured in Studio).
local TEXT_UP = {
	[Enum.NormalId.Top] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, 0, -1),
}

-- The landed die's rotation: rolled face up, turned (in 90° steps) so its number reads upright
-- from the camera.
local function settleRotation(number: number): CFrame
	local face = FACES[math.clamp(number, 1, 6)]
	local textUp = TEXT_UP[face.Face] or Vector3.yAxis
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local away = Vector3.new(look.X, 0, look.Z)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, -1)
	local best, bestDot = CFrame.new(), -math.huge
	for quarter = 0, 3 do
		local turn = CFrame.Angles(0, quarter * math.pi / 2, 0) * face.Up
		local dot = turn:VectorToWorldSpace(textUp):Dot(away)
		if dot > bestDot then
			best, bestDot = turn, dot
		end
	end
	return best
end

local function reducedMotion(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function makeDie(): Part
	local die = Instance.new("Part")
	die.Name = "BoardDie"
	die.Size = Vector3.one * SIZE
	die.Anchored = true
	die.CanCollide = false
	die.CanQuery = false
	die.CanTouch = false
	die.Material = Enum.Material.SmoothPlastic
	die.Color = Color3.fromRGB(255, 250, 238)
	for number, info in FACES do
		local gui = Instance.new("SurfaceGui")
		gui.Face = info.Face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0.3
		gui.Parent = die
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(255, 250, 238)
		label.BorderSizePixel = 0
		label.Font = Theme.TitleFont
		label.TextScaled = true
		label.TextColor3 = if number == 1 then Color3.fromRGB(226, 72, 70) else Color3.fromRGB(60, 40, 110)
		label.Text = tostring(number)
		label.Parent = gui
		label.Name = "Number"
		-- Dots under 6 and 9 would be ambiguous: underline them, like real number dice.
		if number == 6 then
			label.Text = "<u>6</u>"
			label.RichText = true
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(242, 190, 72)
		stroke.Thickness = 6
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
	end
	return die
end

BoardDice.makeDie = makeDie -- DicePrompt's hovering die is the same die

function BoardDice.new()
	return setmetatable({ Throw = nil }, BoardDice)
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where the dice land: beside the roller, nudged toward the camera so they're in view.
local function landingSpot(root: BasePart, index: number, count: number): Vector3
	local camera = Workspace.CurrentCamera
	local toCamera = camera.CFrame.Position - root.Position
	local flat = Vector3.new(toCamera.X, 0, toCamera.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
	local side = Vector3.new(-flat.Z, 0, flat.X)
	local spread = (index - (count + 1) / 2) * (SIZE + 1.2)
	return root.Position + flat * 5.5 + side * (spread + 2.5) + Vector3.new(0, -3.2 + SIZE / 2 + 1.3, 0)
end

local function hop(root: BasePart)
	local home = root.CFrame
	local up = TweenService:Create(root, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = home + Vector3.new(0, 2.2, 0) })
	up:Play()
	up.Completed:Once(function()
		-- Back down only if the server hasn't moved the piece meanwhile.
		if (root.CFrame.Position - (home.Position + Vector3.new(0, 2.2, 0))).Magnitude < 0.5 then
			TweenService:Create(root, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = home }):Play()
		end
	end)
end

function BoardDice:clear()
	local throw = self.Throw
	self.Throw = nil
	if throw then
		if throw.Connection then
			throw.Connection:Disconnect()
		end
		for _, die in throw.Dice do
			die:Destroy()
		end
		if throw.Tag then
			throw.Tag:Destroy()
		end
	end
end

-- Starts a throw (faces unknown yet unless given). short = the bot version.
function BoardDice:throw(character: Model?, count: number, faces: { number }?, short: boolean?)
	self:clear()
	local root = rootOf(character)
	if not root then
		return
	end
	local camera = Workspace.CurrentCamera
	local throw = {
		Started = os.clock(),
		Flight = if short then FLIGHT_SHORT else FLIGHT,
		Dice = {}, -- the die Parts
		Paths = {}, -- per die: { Part, From, To, Spin, Settled }
		Faces = faces,
		Root = root,
		Short = short,
	}
	self.Throw = throw
	if not reducedMotion() then
		hop(root)
	end
	local still = reducedMotion()
	for i = 1, math.max(1, count) do
		local die = makeDie()
		local from = root.Position + HOVER -- where DicePrompt's die hovers
		local to = landingSpot(root, i, count)
		die.CFrame = CFrame.new(from)
		die.Parent = camera
		table.insert(throw.Dice, die)
		table.insert(throw.Paths, {
			Part = die,
			From = from,
			To = to,
			Spin = Vector3.new(math.random(7, 12), math.random(5, 10), math.random(6, 11)) * (if math.random() < 0.5 then -1 else 1),
		})
	end

	throw.Connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - throw.Started
		local landed = t >= throw.Flight
		for index, path in throw.Paths do
			local die = path.Part
			if not die.Parent then
				continue
			end
			if still then
				die.CFrame = CFrame.new(path.To)
			elseif not landed then
				local u = t / throw.Flight
				local arc = 4 * u * (1 - u) * 5 -- 5-stud high arc
				local position = path.From:Lerp(path.To, u) + Vector3.new(0, arc, 0)
				die.CFrame = CFrame.new(position) * CFrame.fromEulerAnglesXYZ(path.Spin.X * t, path.Spin.Y * t, path.Spin.Z * t)
			elseif not throw.Faces or t < math.max(throw.Flight, MIN_TUMBLE) + 0.05 then
				-- Landed, result not known yet: a small bounce-wobble in place.
				local wobble = math.abs(math.sin((t - throw.Flight) * 9)) * 0.6
				die.CFrame = CFrame.new(path.To + Vector3.new(0, wobble, 0)) * CFrame.fromEulerAnglesXYZ(path.Spin.X * t * 0.3, path.Spin.Y * t * 0.3, 0)
			elseif not path.Settled then
				path.Settled = true
				local target = CFrame.new(path.To) * settleRotation(throw.Faces[index] or 1)
				TweenService:Create(die, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = target }):Play()
			end
		end
		-- Every die settled: pop the number once.
		if throw.Faces and not throw.Tag then
			local allSettled = true
			for _, path in throw.Paths do
				allSettled = allSettled and path.Settled == true
			end
			if allSettled or still then
				self:popNumber(throw)
			end
		end
	end)
end

function BoardDice:popNumber(throw)
	local total = 0
	for _, face in throw.Faces do
		total += face
	end
	local anchor = throw.Dice[1]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DiceResult"
	billboard.Size = UDim2.fromOffset(120, 90)
	-- Above the die and nudged toward the camera, so the roller's YOU tag never covers it.
	local toCamera = (Workspace.CurrentCamera.CFrame.Position - anchor.Position)
	local nudge = Vector3.new(toCamera.X, 0, toCamera.Z)
	nudge = if nudge.Magnitude > 0.01 then nudge.Unit * 2.5 else Vector3.zero
	billboard.StudsOffsetWorldSpace = Vector3.new(0, SIZE + 1.2, 0) + nudge
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.TitleFont
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.Accent
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Theme.Colors.Overlay
	label.Text = if #throw.Faces > 1 then ("= %d"):format(total) else tostring(total)
	label.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	billboard.Parent = Workspace.CurrentCamera
	throw.Tag = billboard
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Leave it up briefly, then fade the dice away (the hops start right after).
	task.delay(if throw.Short then 0.55 else 0.85, function()
		if self.Throw ~= throw then
			return
		end
		for _, die in throw.Dice do
			TweenService:Create(die, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			for _, gui in die:GetChildren() do
				if gui:IsA("SurfaceGui") then
					gui.Enabled = false
				end
			end
		end
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.35, function()
			if self.Throw == throw then
				self:clear()
			end
		end)
	end)
end

-- The server's result for roll `rollId`: settles the local throw, or plays a full one.
function BoardDice:reveal(character: Model?, faces: { number }, rollId: number, short: boolean?)
	if self.LastRollId == rollId then
		return
	end
	self.LastRollId = rollId
	local throw = self.Throw
	if throw and throw.Faces == nil and #throw.Paths == #faces and os.clock() - throw.Started < 3 then
		throw.Faces = faces -- the local player's throw is already in the air
		return
	end
	self:throw(character, #faces, faces, short)
end

return BoardDice
