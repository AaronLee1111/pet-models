--[[
	BoardIntro
	The board-opening introduction on this client, from the server's schedule (Message.
	BoardIntro, sent once per match before turn order):

	  1. establishing shot of the board's landmark (a slow push-in)
	  2. the camera moves to the entrance; each participant in seat order arrives (sunbeam /
	     moonbeam drop, or walking in), their name card shows with a BOT tag for bots, they wave,
	     then run onto their slot on Start
	  3. group shot of everyone on Start; once all have appeared the player may CONTINUE
	  4. a short blend into the normal board camera for turn order

	The server decides who arrives when and where they end up, and ends the intro; this module
	only moves cameras and characters locally. Characters are hidden (locally) until their
	arrival. A client that joins late picks up the schedule where it is; Done (or leaving the
	board) puts everyone back on their real spots.

	  local intro = BoardIntro.new(screen, send)
	  intro:play(message) / intro:finish()
	  intro:update(dt)                     every frame
	  intro:camera() -> CFrame?, blend     BoardView's camera: the shot, and how far to blend
	                                       into the normal board camera (0..1)
	  intro.Active
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BoardMotion = require(script.Parent.BoardMotion)
local Theme = require(script.Parent.Theme)
local make = Theme.make

local BoardIntro = {}
BoardIntro.__index = BoardIntro

local SKIP_ACTION = "PartyBoardIntroSkip"
-- Phases of one arrival, as fractions of its slot (Each): drop in, wave, run to the slot.
local DROP, WAVE, WALK = 0.3, 0.62, 0.95
local BEAM_COLORS = { Sunbeam = Color3.fromRGB(255, 214, 92), Moonbeam = Color3.fromRGB(196, 170, 255) }
local myId = "player_" .. Players.LocalPlayer.UserId

function BoardIntro.new(screen: ScreenGui, send: (any) -> ())
	local self = setmetatable({ Send = send, Active = false }, BoardIntro)
	self.Root = make("Frame", {
		Name = "BoardIntro",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = screen,
	})
	self.Title = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(900, 64),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 54,
		TextColor3 = Theme.Glass.Gold,
		Parent = self.Root,
	}, { make("UIStroke", { Color = Theme.Glass.Deep, Thickness = 3 }), make("UIScale", {}) })
	-- Name card: lower centre, clear of the centre of the screen and of Roblox's own UI.
	self.Card = Theme.glass(make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(420, 76),
		Visible = false,
		Parent = self.Root,
	}, { make("UIScale", {}) }), 20, 3)
	self.Name = make("TextLabel", {
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -44, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 40,
		TextColor3 = Theme.Glass.Cream,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = self.Card,
	}, { make("UIStroke", { Color = Theme.Glass.Deep, Thickness = 2 }) })
	self.Tag = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(64, 32),
		BackgroundColor3 = Theme.Glass.Gold,
		Font = Theme.TitleFont,
		TextSize = 22,
		TextColor3 = Theme.Glass.Deep,
		Text = "BOT",
		Visible = false,
		Parent = self.Card,
	}, { Theme.corner(10) })
	self.Skip = make("TextButton", {
		Name = "IntroContinue",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(220, 60),
		Font = Theme.TitleFont,
		TextSize = 28,
		TextColor3 = Theme.Glass.Cream,
		Text = "CONTINUE",
		AutoButtonColor = true,
		Visible = false,
		Parent = self.Root,
	})
	Theme.glass(self.Skip, 16, 2)
	make("UIScale", { Parent = self.Skip })
	self.Skip.Activated:Connect(function()
		self:skip()
	end)
	return self
end

local function rootOf(character: Model?): BasePart?
	return character and character.Parent and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Local-only hide / show of a whole character (accessories and layered clothing included).
local function setHidden(character: Model, hidden: boolean)
	local value = if hidden then 1 else 0
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = value
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if hidden then Enum.HumanoidDisplayDistanceType.None else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

local function lookFlat(from: Vector3, to: Vector3): CFrame
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return if flat.Magnitude > 0.05 then CFrame.lookAt(from, from + flat) else CFrame.new(from)
end

function BoardIntro:play(message)
	local now = Workspace:GetServerTimeNow()
	if message.Done then
		-- The server moved on (everyone continued): blend out from here.
		if self.Active then
			local out = self.Message.Out or 0.4
			self.Message.EndsAt = math.min(self.Message.EndsAt, now + out)
		end
		return
	end
	if self.Active then
		self:finish()
	end
	if now >= message.EndsAt then
		return
	end
	self.Message = message
	self.Active = true
	self.Reduced = BoardMotion.reducedMotion()
	self.Hidden = {}
	self.Waved = {}
	self.Skipped = false
	self.Shot = nil
	self.Title.Text = string.upper((string.gsub(message.BoardName or "", "%s*%b()", "")))
	self.Root.Visible = true
	for _, seat in message.Seats do
		if seat.Character then
			self.Hidden[seat.Character] = false
		end
	end
	ContextActionService:BindAction(SKIP_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin and self.Skip.Visible then
			self:skip()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	self:update(0)
end

function BoardIntro:skip()
	if self.Skipped then
		return
	end
	self.Skipped = true
	self.Skip.Text = "WAITING…"
	self.Send({ Kind = "IntroSkip" })
end

function BoardIntro:finish()
	if not self.Active then
		return
	end
	self.Active = false
	ContextActionService:UnbindAction(SKIP_ACTION)
	self.Root.Visible = false
	self.Card.Visible = false
	self.Skip.Visible = false
	if self.Beam then
		self.Beam:Destroy()
		self.Beam = nil
	end
	-- Everyone visible, standing where the server put them.
	for _, seat in self.Message.Seats do
		local character = seat.Character
		if character and character.Parent then
			setHidden(character, false)
			local run = BoardMotion.track(character, "run")
			if run then
				run:Stop(0.1)
			end
			local root = rootOf(character)
			if root and seat.Destination then
				root.CFrame = seat.Destination
			end
		end
	end
	self.Message = nil
end

-- The participant arriving now (index), or nil before the first / after the last.
function BoardIntro:arriving(now: number)
	local message = self.Message
	for i = #message.Seats, 1, -1 do
		local seat = message.Seats[i]
		if now >= seat.ArriveAt then
			return if now < message.GroupAt then i else nil
		end
	end
	return nil
end

-- Where seat's root is at `now` and which animation it should be in.
function BoardIntro:pose(seat, now: number, each: number): (CFrame?, string?)
	local spec = self.Message.Spec
	local destination: CFrame = seat.Destination
	if not spec or self.Reduced then
		return destination, nil
	end
	local p = (now - seat.ArriveAt) / each
	if p >= WALK then
		return destination, nil
	end
	local entry = spec.Entry
	local landing = entry[#entry]
	local face = lookFlat(landing, spec.Arrival.Camera)
	if p < DROP then
		local position = BoardMotion.sample(entry, BoardMotion.length(entry) * math.sin(p / DROP * math.pi / 2))
		return face.Rotation + position, nil
	elseif p < WAVE then
		return face.Rotation + landing, "wave"
	end
	local path = { landing, destination.Position }
	local position = BoardMotion.sample(path, BoardMotion.length(path) * (p - WAVE) / (WALK - WAVE))
	return lookFlat(landing, destination.Position).Rotation + position, "run"
end

function BoardIntro:update(dt: number)
	if not self.Active then
		return
	end
	local message = self.Message
	local now = Workspace:GetServerTimeNow()
	if now >= message.EndsAt then
		self:finish()
		return
	end
	local spec = message.Spec
	local each = if #message.Seats > 1 then message.Seats[2].ArriveAt - message.Seats[1].ArriveAt else message.GroupAt - message.Seats[1].ArriveAt
	each = math.max(each, 0.5)
	local index = self:arriving(now)

	for _, seat in message.Seats do
		local character = seat.Character
		local root = rootOf(character)
		if not root then
			continue -- left during the intro, or the body is still loading: never blocks
		end
		local hidden = now < seat.ArriveAt
		if self.Hidden[character] ~= hidden then
			self.Hidden[character] = hidden
			setHidden(character, hidden)
		end
		if hidden then
			continue
		end
		local cframe, animation = self:pose(seat, now, each)
		if cframe then
			root.CFrame = cframe
		end
		local run = BoardMotion.track(character, "run")
		if run and (animation == "run") ~= run.IsPlaying then
			if animation == "run" then
				run:Play(0.1)
			else
				run:Stop(0.15)
			end
		end
		if animation == "wave" and not self.Waved[character] then
			self.Waved[character] = true
			local wave = BoardMotion.track(character, "wave")
			if wave then
				wave:Play(0.1)
			end
		end
	end

	-- Arrival effect: a beam down onto the entrance while someone drops in (off as they land).
	local beamOn = spec and index and not self.Reduced and BEAM_COLORS[spec.Effect]
		and (now - message.Seats[index].ArriveAt) / each < DROP
	if beamOn and not self.Beam then
		local entry = spec.Entry
		local top, bottom = entry[1], entry[#entry] - Vector3.new(0, 3, 0)
		self.Beam = make("Part", {
			Name = "IntroBeam",
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = BEAM_COLORS[spec.Effect],
			Transparency = 0.65,
			Size = Vector3.new((top - bottom).Magnitude + 6, 3.2, 3.2),
			CFrame = CFrame.new((top + bottom) / 2 + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Parent = Workspace,
		})
	elseif not beamOn and self.Beam then
		self.Beam:Destroy()
		self.Beam = nil
	end

	-- Name card for whoever is arriving.
	local seat = index and message.Seats[index]
	self.Card.Visible = seat ~= nil
	if seat then
		self.Name.Text = Theme.shortWords(if seat.Id == myId then Players.LocalPlayer.DisplayName else seat.Name, 14)
		self.Tag.Visible = seat.IsBot == true
	end
	self.Title.Visible = spec ~= nil and now < message.Seats[1].ArriveAt
	local canSkip = now >= message.GroupAt and now < message.EndsAt - (message.Out or 0.4)
	self.Skip.Visible = canSkip
	if not self.Skipped then
		self.Skip.Text = "CONTINUE"
	end

	-- Phones: same layout, scaled to the screen height (names stay readable).
	local size = self.Root.AbsoluteSize
	local scale = math.clamp(size.Y / 720, 0.72, 1.25)
	for _, item in { self.Title, self.Card, self.Skip } do
		item:FindFirstChildOfClass("UIScale").Scale = scale
	end
	self.Title.Position = UDim2.new(0.5, 0, 0, 70 * scale)
	self.Card.Position = UDim2.new(0.5, 0, 1, -56 * scale)
	self.Skip.Position = UDim2.new(1, -size.X * 0.06, 1, -40 * scale) -- clear of rounded corners
	self:aim(now, index, dt)
end

-- The camera shot for this moment (smoothed: shots move into each other unless reduced motion).
function BoardIntro:aim(now: number, index: number?, dt: number)
	local message = self.Message
	local spec = message.Spec
	local goal
	if not spec then
		local sum = Vector3.zero
		for _, seat in message.Seats do
			sum += seat.Destination.Position
		end
		local centre = sum / math.max(1, #message.Seats)
		goal = CFrame.lookAt(centre + Vector3.new(0, 16, 22), centre)
	elseif now < message.Seats[1].ArriveAt then
		local u = math.clamp((now - message.StartsAt) / math.max(0.1, message.Seats[1].ArriveAt - message.StartsAt), 0, 1)
		local camera = spec.Establish.Camera:Lerp(spec.Establish.Look, 0.12 * u) -- slow push-in
		goal = CFrame.lookAt(camera, spec.Establish.Look)
	elseif index then
		local root = rootOf(message.Seats[index].Character)
		local look = if root then spec.Arrival.Look:Lerp(root.Position, 0.4) else spec.Arrival.Look
		goal = CFrame.lookAt(spec.Arrival.Camera, look)
	else
		goal = CFrame.lookAt(spec.Group.Camera, spec.Group.Look)
	end
	if self.Reduced or not self.Shot then
		self.Shot = goal
	else
		self.Shot = self.Shot:Lerp(goal, 1 - math.exp(-5 * dt))
	end
end

function BoardIntro:camera(): (CFrame?, number)
	if not self.Active or not self.Shot then
		return nil, 1
	end
	local message = self.Message
	local out = message.Out or 0.4
	local blend = math.clamp((Workspace:GetServerTimeNow() - (message.EndsAt - out)) / out, 0, 1)
	return self.Shot, blend
end

return BoardIntro
