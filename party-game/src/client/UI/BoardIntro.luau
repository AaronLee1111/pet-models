--[[
	BoardIntro
	The board-opening introduction on this client, from the server's schedule (Message.
	BoardIntro, sent once per match before turn order; ~10 s):

	  1. sky dive-in: from high above the clouds, down through them to the whole map with the
	     board's name, a short drifting hold, then a swoop down to the entrance
	  2. each participant in seat order gets a close-up: they drop in on a sunbeam / moonbeam
	     (or walk in), land with a sparkle-and-confetti burst and a chime, wave once while their
	     name banner (avatar, name, BOT tag) slides in, then run to their slot on Start
	  3. group shot: everyone on Start turns to the camera; once all have appeared the player
	     may CONTINUE
	  4. a short blend into the normal board camera for turn order

	The server decides who arrives when and where they end up, and ends the intro; this module
	only moves cameras and characters locally. Characters are hidden (locally) until their
	arrival. A client that joins late picks up the schedule where it is; Done, a server stage
	past the intro, or leaving the board puts everyone back on their real spots.

	  local intro = BoardIntro.new(screen, send)
	  intro:play(message) / intro:finish()
	  intro:update(dt)                     every frame
	  intro:camera() -> CFrame?, blend     BoardView's camera: the shot, and how far to blend
	                                       into the normal board camera (0..1)
	  intro.Active

	Effects use Roblox's built-in particle textures and sounds only (nothing uploaded).
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ActivePlayerPortrait = require(script.Parent.ActivePlayerPortrait)
local BoardMotion = require(script.Parent.BoardMotion)
local Theme = require(script.Parent.Theme)
local make = Theme.make

local BoardIntro = {}
BoardIntro.__index = BoardIntro

local SKIP_ACTION = "PartyBoardIntroSkip"
-- Phases of one arrival, as fractions of its slot (Each): drop in, wave, run to the slot.
local DROP, WAVE, WALK = 0.28, 0.6, 0.9
-- Phases of the sky dive, as fractions of the opening: fall to the map, hold, swoop down.
local FALL, HOLD = 0.38, 0.62
local SKY = Vector3.new(0, 230, 90) -- where the dive starts, relative to the whole-map shot
local EFFECT_COLORS = {
	Sunbeam = { Color3.fromRGB(255, 214, 92), Color3.fromRGB(255, 160, 70) },
	Moonbeam = { Color3.fromRGB(196, 170, 255), Color3.fromRGB(140, 220, 255) },
	Walk = { Color3.fromRGB(255, 214, 92), Color3.fromRGB(120, 220, 160) },
}
local CONFETTI = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 140)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 214, 92)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 230, 140)),
})
local SOUNDS = {
	Whoosh = { "rbxasset://sounds/action_falling.ogg", 0.35, 1.7, 0.7 }, -- id, volume, speed, seconds
	Land = { "rbxasset://sounds/action_jump_land.mp3", 0.5, 1, 1 },
	Chime = { "rbxasset://sounds/volume_slider.ogg", 0.45, 1.6, 1 },
}

local function play(name: string)
	local entry = SOUNDS[name]
	local sound = Instance.new("Sound")
	sound.SoundId = entry[1]
	sound.Volume = entry[2]
	sound.PlaybackSpeed = entry[3]
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, entry[4])
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10) -- smootherstep
end

local function easeOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

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
	-- Name banner: lower centre (clear of the middle of the screen and Roblox's own UI); the
	-- avatar's head in a gold ring on the left, the name big, a BOT pill for bots.
	self.Banner = Theme.glass(make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(560, 112),
		Visible = false,
		Parent = self.Root,
	}, { make("UIScale", {}) }), 28, 3)
	self.Avatar = make("ViewportFrame", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = Theme.Glass.Deep,
		Parent = self.Banner,
	}, { Theme.corner(46), Theme.stroke(Theme.Glass.Gold, 3) })
	self.Name = make("TextLabel", {
		Position = UDim2.fromOffset(122, 12),
		Size = UDim2.new(1, -230, 0, 58),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 50,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Glass.Cream,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = self.Banner,
	}, { make("UIStroke", { Color = Theme.Glass.Deep, Thickness = 2 }) })
	self.Subtitle = make("TextLabel", {
		Position = UDim2.fromOffset(124, 70),
		Size = UDim2.new(1, -230, 0, 28),
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Glass.Gold,
		Parent = self.Banner,
	})
	self.Tag = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0),
		Size = UDim2.fromOffset(78, 40),
		BackgroundColor3 = Theme.Glass.Gold,
		Font = Theme.TitleFont,
		TextSize = 26,
		TextColor3 = Theme.Glass.Deep,
		Text = "BOT",
		Visible = false,
		Parent = self.Banner,
	}, { Theme.corner(12) })
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
		self:wrapUp()
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
	self.Landed = {}
	self.Waving = {}
	self.Bannered = nil
	self.Skipped = false
	self.Shot = nil
	self.Sounded = {}
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

-- The server has moved on (everyone continued, or it is already rolling for turn order): blend
-- out from wherever this client is, never later than the scheduled end.
function BoardIntro:wrapUp()
	if self.Active then
		local out = self.Message.Out or 0.4
		self.Message.EndsAt = math.min(self.Message.EndsAt, Workspace:GetServerTimeNow() + out)
	end
end

function BoardIntro:skip()
	if self.Skipped then
		return
	end
	self.Skipped = true
	self.Skip.Text = "WAITING…"
	self.Send({ Kind = "IntroSkip" })
end

function BoardIntro:clearScenery()
	for _, item in self.Scenery or {} do
		item:Destroy()
	end
	self.Scenery = nil
end

function BoardIntro:finish()
	if not self.Active then
		return
	end
	self.Active = false
	ContextActionService:UnbindAction(SKIP_ACTION)
	self.Root.Visible = false
	self.Banner.Visible = false
	self.Skip.Visible = false
	self:clearScenery()
	-- Everyone visible, standing where the server put them, no intro animation left playing.
	for _, seat in self.Message.Seats do
		local character = seat.Character
		if character and character.Parent then
			setHidden(character, false)
			for _, name in { "run", "wave" } do
				local track = BoardMotion.track(character, name)
				if track then
					track:Stop(0.15)
				end
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

function BoardIntro:each(): number
	local message = self.Message
	local seats = message.Seats
	local each = if #seats > 1 then seats[2].ArriveAt - seats[1].ArriveAt else message.GroupAt - seats[1].ArriveAt
	return math.max(each, 0.5)
end

-- Where seat's root is at `now` and which animation it should be in.
function BoardIntro:pose(seat, now: number): (CFrame?, string?)
	local message = self.Message
	local spec = message.Spec
	local destination: CFrame = seat.Destination
	if spec and now >= message.GroupAt then
		-- Group shot: everyone turns to the camera (finish() turns them back along the route).
		return lookFlat(destination.Position, spec.Group.Camera), nil
	end
	if not spec or self.Reduced then
		return destination, nil
	end
	local p = (now - seat.ArriveAt) / self:each()
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
	local position = BoardMotion.sample(path, BoardMotion.length(path) * ease((p - WAVE) / (WALK - WAVE)))
	return lookFlat(landing, destination.Position).Rotation + position, "run"
end

-- The landing burst: sparkles in the board's colours, confetti and a flat shockwave ring.
function BoardIntro:burst(at: Vector3)
	if self.Reduced then
		return
	end
	local colors = EFFECT_COLORS[self.Message.Spec.Effect] or EFFECT_COLORS.Walk
	local anchor = make("Part", {
		Name = "IntroBurst",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(at),
		Parent = Workspace,
	})
	local function emitter(props, count)
		local particles = make("ParticleEmitter", props)
		particles.Enabled = false
		particles.Parent = anchor
		particles:Emit(count)
	end
	emitter({
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(colors[1], colors[2]),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	}, 28)
	emitter({
		Texture = "rbxasset://textures/particles/SquareParticle.png",
		Color = CONFETTI,
		Size = NumberSequence.new(0.35),
		Lifetime = NumberRange.new(0.9, 1.4),
		Speed = NumberRange.new(14, 22),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -30, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		Drag = 1.5,
	}, 36)
	emitter({
		Texture = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
		Color = ColorSequence.new(colors[1]),
		LightEmission = 1,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.45),
	}, 1)
	Debris:AddItem(anchor, 2)
end

-- A few local clouds the dive falls through (gone once the camera is below them).
function BoardIntro:buildClouds(from: Vector3, to: Vector3)
	self.Scenery = {}
	local random = Random.new(7)
	local layer = from:Lerp(to, 0.45)
	for _ = 1, 14 do
		local offset = Vector3.new(random:NextNumber(-45, 45), random:NextNumber(-10, 10), random:NextNumber(-45, 45))
		local size = random:NextNumber(18, 34)
		table.insert(self.Scenery, make("Part", {
			Name = "IntroCloud",
			Shape = Enum.PartType.Ball,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(255, 255, 255),
			Transparency = 0.12,
			Size = Vector3.new(size, size * 0.6, size),
			CFrame = CFrame.new(layer + offset),
			Parent = Workspace,
		}))
	end
end

-- The banner for whoever is arriving: slides in from the left, out to the right.
function BoardIntro:showBanner(seat)
	self.Bannered = seat
	local me = Players.LocalPlayer
	local mine = me ~= nil and seat.Id == "player_" .. me.UserId
	self.Name.Text = Theme.shortWords(if mine then me.DisplayName else seat.Name, 14)
	self.Tag.Visible = seat.IsBot == true
	self.Subtitle.Text = if mine then "That's you!" elseif seat.IsBot then "Joins the party" else "Ready to play"
	for _, child in self.Avatar:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	ActivePlayerPortrait.mount(self.Avatar, seat.Character, "Head")
	self.Banner.Visible = true
	local final = self.BannerPosition
	if self.Reduced then
		self.Banner.Position = final
		return
	end
	self.Banner.Position = final - UDim2.fromScale(0.7, 0)
	TweenService:Create(self.Banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = final }):Play()
end

function BoardIntro:hideBanner()
	self.Bannered = nil
	if self.Reduced then
		self.Banner.Visible = false
		return
	end
	local banner = self.Banner
	local tween = TweenService:Create(banner, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = banner.Position + UDim2.fromScale(0.7, 0) })
	tween.Completed:Connect(function()
		if not self.Bannered then
			banner.Visible = false
		end
	end)
	tween:Play()
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
	local each = self:each()
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
		local cframe, animation = self:pose(seat, now)
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
		-- One wave per arrival, stopped when the arrival moves on (the animation itself loops).
		local wave = BoardMotion.track(character, "wave")
		if wave then
			if animation == "wave" and not self.Waving[character] then
				self.Waving[character] = true
				wave:Play(0.1)
			elseif animation ~= "wave" and wave.IsPlaying then
				wave:Stop(0.2)
			end
		end
		-- Landing: burst, thud and chime, once.
		if spec and not self.Landed[character] and (now - seat.ArriveAt) / each >= DROP and now < message.GroupAt then
			self.Landed[character] = true
			local landing = spec.Entry[#spec.Entry]
			self:burst(landing - Vector3.new(0, 2.6, 0))
			play("Land")
			play("Chime")
		end
	end

	-- Arrival effect: a beam down onto the entrance while someone drops in (off as they land).
	local colors = spec and EFFECT_COLORS[spec.Effect]
	local beamOn = spec and index and not self.Reduced and spec.Effect ~= "Walk" and colors
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
			Color = colors[1],
			Transparency = 0.65,
			Size = Vector3.new((top - bottom).Magnitude + 6, 3.2, 3.2),
			CFrame = CFrame.new((top + bottom) / 2 + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Parent = Workspace,
		})
		play("Whoosh")
	elseif not beamOn and self.Beam then
		self.Beam:Destroy()
		self.Beam = nil
	end

	-- Banner for whoever is arriving, from the landing until they reach Start.
	local seat = index and message.Seats[index]
	local bannerSeat = seat and (now - seat.ArriveAt) / each >= DROP - 0.05 and (now - seat.ArriveAt) / each < WALK + 0.05 and seat or nil
	if bannerSeat ~= self.Bannered then
		if bannerSeat then
			self:showBanner(bannerSeat)
		else
			self:hideBanner()
		end
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
	for _, item in { self.Title, self.Banner, self.Skip } do
		item:FindFirstChildOfClass("UIScale").Scale = scale
	end
	self.Title.Position = UDim2.new(0.5, 0, 0, 70 * scale)
	self.BannerPosition = UDim2.new(0.5, 0, 1, -40 * scale)
	if not self.Bannered and self.Banner.Visible == false then
		self.Banner.Position = self.BannerPosition
	end
	self.Skip.Position = UDim2.new(1, -size.X * 0.06, 1, -40 * scale) -- clear of rounded corners
	self:aim(now, index, dt)
end

-- The camera shot for this moment.
function BoardIntro:aim(now: number, index: number?, dt: number)
	local message = self.Message
	local spec = message.Spec
	local goal
	local direct = false -- the dive is already a smooth path; later shots ease into each other
	if not spec then
		local sum = Vector3.zero
		for _, seat in message.Seats do
			sum += seat.Destination.Position
		end
		local centre = sum / math.max(1, #message.Seats)
		goal = CFrame.lookAt(centre + Vector3.new(0, 16, 22), centre)
	elseif now < message.Seats[1].ArriveAt then
		-- Sky dive: fall through the clouds to the whole map, drift, then swoop to the entrance.
		local map, arrival = spec.Establish, spec.Arrival
		local sky = map.Camera + SKY
		local u = math.clamp((now - message.StartsAt) / math.max(0.1, message.Seats[1].ArriveAt - message.StartsAt), 0, 1)
		if self.Reduced then
			goal = CFrame.lookAt(if u < HOLD then map.Camera else arrival.Camera, if u < HOLD then map.Look else arrival.Look)
		elseif u < FALL then
			if not self.Scenery then
				self:buildClouds(sky, map.Camera)
				play("Whoosh")
			end
			goal = CFrame.lookAt(sky:Lerp(map.Camera, easeOut(u / FALL)), map.Look)
		elseif u < HOLD then
			self:clearScenery()
			local drift = CFrame.Angles(0, math.rad(6) * (u - FALL) / (HOLD - FALL), 0)
			goal = CFrame.lookAt(map.Look + drift:VectorToWorldSpace(map.Camera - map.Look), map.Look)
		else
			if not self.Sounded.Swoop then
				self.Sounded.Swoop = true
				play("Whoosh")
			end
			local t = ease((u - HOLD) / (1 - HOLD))
			local start = map.Look + CFrame.Angles(0, math.rad(6), 0):VectorToWorldSpace(map.Camera - map.Look)
			local position = start:Lerp(arrival.Camera, t) + Vector3.new(0, math.sin(t * math.pi) * 14, 0)
			goal = CFrame.lookAt(position, map.Look:Lerp(arrival.Look, t))
		end
		direct = true
	elseif index then
		-- Close-up: push in toward the landing while they wave, then follow the run.
		local seat = message.Seats[index]
		local p = (now - seat.ArriveAt) / self:each()
		local landing = spec.Entry[#spec.Entry]
		local push = if self.Reduced then 0 else 0.32 * ease((p - 0.15) / 0.45)
		local root = rootOf(seat.Character)
		local look = if root then spec.Arrival.Look:Lerp(root.Position, 0.55) else spec.Arrival.Look
		goal = CFrame.lookAt(spec.Arrival.Camera:Lerp(landing, push), look)
	else
		goal = CFrame.lookAt(spec.Group.Camera, spec.Group.Look)
	end
	if self.Reduced or direct or not self.Shot then
		self.Shot = goal
	else
		self.Shot = self.Shot:Lerp(goal, 1 - math.exp(-6 * dt))
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
