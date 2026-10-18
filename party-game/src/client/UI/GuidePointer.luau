--[[
	GuidePointer
	Leads the player to one exact button: a gently bouncing hand, a pulsing ring around the
	button and a short label ("TAP HERE" + one line of help) next to it.

	  guide:show(key, target, { Title, Note?, Sides?, Extra? }) -> true if something changed
	  guide:show(key, nil, { Title, Note? })   no button to point at (desktop movement keys):
	                                           just the label, low on the screen
	  guide:clear(key?)       remove it (only if it's still `key`, when given)
	  guide:update()          every frame: follow the target, bounce, hide/clear when it's gone

	  * One pointer at a time: show() replaces whatever was there; showing the same key on the
	    same target again does nothing, so repeated messages can't stack pointers.
	  * Lives in its own ScreenGui above the party UI (DisplayOrder 11) but inside Roblox's
	    safe area (top bar, notch, home indicator), and is clamped to it.
	  * Never takes input: nothing in it is Active or Interactable, so the button underneath
	    still gets every tap and click. The ring is an outline, so the button's text shows.
	  * Follows the target every frame, so it stays on it when the HUD rescales or moves.
	  * Clears itself when the target is destroyed; hides while the target is hidden.
	  * Extra = more buttons that get a thinner ring (e.g. every route at a fork).
	  * Round = true: a circular ring for round images with no UICorner (the thumbstick).
	  * Outside = a panel the target sits in (the board prompt): the hand and label go above
	    that whole panel instead of over its title text.
	  * Reduced motion (if Roblox reports it): no bounce and no pulse.
]]

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local GuidePointer = {}
GuidePointer.__index = GuidePointer

local GAP = 6 -- between the ring and the hand
local RING_PAD = 6 -- ring sits this far outside the button
local BOUNCE = 9 -- pixels at full scale
local BOUNCE_HZ = 0.9 -- gentle: under once a second
local HANDS = { Above = "👇", Below = "👆", Left = "👉", Right = "👈" }
local DEFAULT_SIDES = { "Left", "Above", "Right", "Below" }

local function reducedMotion(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function noInput(instance: GuiObject)
	instance.Active = false
	pcall(function()
		(instance :: any).Interactable = false
	end)
	return instance
end

-- Outline-only ring (yellow, with a dark edge so it reads on yellow buttons too).
local function ring(parent: Instance, name: string, thickness: number)
	local frame = noInput(make("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 16) }) }))
	make("UIStroke", { Name = "Glow", Color = Theme.Colors.Accent, Thickness = thickness, Parent = frame })
	local edge = noInput(make("Frame", {
		Name = "Edge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, thickness * 2 + 2, 1, thickness * 2 + 2),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 18) }) }))
	make("UIStroke", { Color = Theme.Colors.Overlay, Thickness = 2, Transparency = 0.2, Parent = edge })
	return frame
end

-- parent: PlayerGui (a ScreenGui is made there) or any Instance (tests).
function GuidePointer.new(parent: Instance)
	local self = setmetatable({}, GuidePointer)
	self.Gui = make("ScreenGui", {
		Name = "PartyGuide",
		ResetOnSpawn = false,
		IgnoreGuiInset = false, -- stay below Roblox's top bar
		DisplayOrder = 11, -- over the party UI (10); modal cards hide the pointer instead
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
	pcall(function()
		self.Gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- notch + home indicator
	end)
	self.Root = noInput(make("Frame", {
		Name = "Guide",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = self.Gui,
	}))
	self.Ring = ring(self.Root, "Ring", 4)
	self.Hand = noInput(make("TextLabel", {
		Name = "Hand",
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextScaled = true,
		Text = HANDS.Left,
		Visible = false,
		ZIndex = 3,
		Parent = self.Root,
	}))
	self.Bubble = noInput(make("Frame", {
		Name = "Bubble",
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 0.05,
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 3,
		Parent = self.Root,
	}, {
		Theme.corner(12),
		Theme.stroke(Theme.Colors.Accent, 3),
		Theme.padding(8),
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}))
	self.Title = noInput(make("TextLabel", {
		Name = "Title",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Text,
		TextWrapped = true,
		ZIndex = 4,
		Parent = self.Bubble,
	}))
	self.Note = noInput(make("TextLabel", {
		Name = "Note",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.Accent,
		TextWrapped = true,
		ZIndex = 4,
		Parent = self.Bubble,
	}))
	self.ExtraRings = {}
	self.Key = nil
	self.Target = nil
	self.Options = nil
	self.Started = os.clock()
	return self
end

local function sameList(a, b): boolean
	a, b = a or {}, b or {}
	if #a ~= #b then
		return false
	end
	for i, value in a do
		if b[i] ~= value then
			return false
		end
	end
	return true
end

function GuidePointer:show(key: string, target: GuiObject?, options): boolean
	options = options or {}
	local current = self.Options
	if
		self.Key == key
		and self.Target == target
		and current
		and current.Title == options.Title
		and current.Note == options.Note
		and sameList(current.Extra, options.Extra)
	then
		return false -- already showing exactly this
	end
	if self.Key ~= key or self.Target ~= target then
		self.Started = os.clock()
	end
	self.Key = key
	self.Target = target
	self.Options = options
	self.Title.Text = options.Title or "TAP HERE"
	self.Note.Text = options.Note or ""
	self.Note.Visible = options.Note ~= nil and options.Note ~= ""
	for _, extra in self.ExtraRings do
		extra:Destroy()
	end
	self.ExtraRings = {}
	for index in options.Extra or {} do
		self.ExtraRings[index] = ring(self.Root, "ExtraRing" .. index, 3)
	end
	return true
end

function GuidePointer:clear(key: string?)
	if key and self.Key ~= key then
		return
	end
	self.Key = nil
	self.Target = nil
	self.Options = nil
	for _, extra in self.ExtraRings do
		extra:Destroy()
	end
	self.ExtraRings = {}
	self:setVisible(false)
end

function GuidePointer:isShowing(): string?
	return self.Key
end

function GuidePointer:setVisible(visible: boolean)
	self.Ring.Visible = visible
	self.Hand.Visible = visible
	self.Bubble.Visible = visible
	for _, extra in self.ExtraRings do
		extra.Visible = visible
	end
end

-- On screen = in the game tree, every GuiObject up to its ScreenGui visible, ScreenGui on.
function GuidePointer.isOnScreen(target: Instance?): boolean
	if not target or not target.Parent or not target:IsA("GuiObject") then
		return false
	end
	local node: Instance? = target
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled and node.Parent ~= nil
		end
		node = node.Parent
	end
	return false
end

-- Target's rectangle in this guide's own coordinates.
function GuidePointer:rectOf(target: GuiObject): (Vector2, Vector2)
	return target.AbsolutePosition - self.Root.AbsolutePosition, target.AbsoluteSize
end

local function placeRing(self, frame: Frame, target: GuiObject, scale: number, pulse: number)
	local position, size = self:rectOf(target)
	local pad = (RING_PAD + pulse * 3) * scale
	frame.Position = UDim2.fromOffset(position.X - pad, position.Y - pad)
	frame.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
	-- Match the button's own rounding (round buttons get round rings). Offsets are in
	-- design pixels, so scale them like the button was; never past a full circle.
	local corner = target:FindFirstChildOfClass("UICorner")
	local half = math.min(size.X, size.Y) / 2
	local uiScale = target:FindFirstChildOfClass("UIScale")
	local radius = if corner
		then corner.CornerRadius.Offset * (if uiScale then uiScale.Scale else 1) + corner.CornerRadius.Scale * half * 2
		elseif self.Options and self.Options.Round then half
		else 12
	radius = math.min(radius, half) + pad
	frame:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, radius)
	frame.Edge:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, radius + 4)
	frame.Glow.Transparency = 0.25 * (1 - pulse)
	return position - Vector2.new(pad, pad), size + Vector2.new(pad * 2, pad * 2)
end

-- Picks the side of the target with room for the hand + bubble (first that fits, in order).
local function chooseSide(sides, position: Vector2, size: Vector2, bounds: Vector2, need: Vector2, hand: number): string
	local best, bestRoom = sides[1], -math.huge
	for _, side in sides do
		local room
		if side == "Left" then
			room = position.X - (hand + GAP + need.X)
		elseif side == "Right" then
			room = bounds.X - (position.X + size.X) - (hand + GAP + need.X)
		elseif side == "Above" then
			room = position.Y - (hand + GAP + need.Y)
		else
			room = bounds.Y - (position.Y + size.Y) - (hand + GAP + need.Y)
		end
		if room >= 0 then
			return side
		end
		if room > bestRoom then
			best, bestRoom = side, room
		end
	end
	return best
end

local function clampBox(position: Vector2, size: Vector2, bounds: Vector2): Vector2
	return Vector2.new(
		math.clamp(position.X, 0, math.max(0, bounds.X - size.X)),
		math.clamp(position.Y, 0, math.max(0, bounds.Y - size.Y))
	)
end

-- Label only, bottom centre (above the bottom HUD, clear of the screen centre).
local function placeHint(self)
	local bounds = self.Root.AbsoluteSize
	local scale = math.clamp(bounds.Y / 620, 0.72, 1)
	local width = math.floor(math.min(320 * scale, bounds.X * 0.5))
	self.Bubble.Size = UDim2.fromOffset(width, 0)
	self.Title.TextSize = math.floor(22 * scale)
	self.Note.TextSize = math.floor(16 * scale)
	local height = math.max(self.Bubble.AbsoluteSize.Y, 30 * scale)
	self.Bubble.Position = UDim2.fromOffset((bounds.X - width) / 2, bounds.Y * 0.72 - height / 2)
	self.Ring.Visible = false
	self.Hand.Visible = false
	self.Bubble.Visible = true
end

function GuidePointer:update()
	local target = self.Target
	if not target then
		if self.Key and self.Options then
			placeHint(self)
		end
		return
	end
	if not target.Parent then
		self:clear() -- the button is gone
		return
	end
	if not GuidePointer.isOnScreen(target) or target.AbsoluteSize.X < 1 then
		self:setVisible(false)
		return
	end
	local bounds = self.Root.AbsoluteSize
	if bounds.X < 1 then
		return
	end
	local scale = math.clamp(bounds.Y / 620, 0.72, 1)
	local still = reducedMotion()
	local t = os.clock() - self.Started
	local wave = if still then 0 else 0.5 - 0.5 * math.cos(t * math.pi * 2 * BOUNCE_HZ)

	-- Rings
	local ringPosition, ringSize = placeRing(self, self.Ring, target, scale, wave)
	for index, extra in self.ExtraRings do
		local other = self.Options.Extra[index]
		local shown = other and GuidePointer.isOnScreen(other)
		extra.Visible = shown == true
		if shown then
			placeRing(self, extra, other, scale, wave)
		end
	end

	-- Bubble size (width fixed; height from the text)
	local bubbleWidth = math.floor(math.min(250 * scale, bounds.X * 0.42))
	self.Bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
	self.Title.TextSize = math.floor(22 * scale)
	self.Note.TextSize = math.floor(16 * scale)
	local bubbleSize = Vector2.new(bubbleWidth, math.max(self.Bubble.AbsoluteSize.Y, 30 * scale))
	local hand = math.floor(40 * scale)

	-- Above a panel: measure "above" from the panel's top edge, not the button's.
	local aboveTop = ringPosition.Y
	local outside = self.Options.Outside
	if outside and GuidePointer.isOnScreen(outside) then
		local panelTop = (outside.AbsolutePosition - self.Root.AbsolutePosition).Y
		aboveTop = math.min(aboveTop, panelTop)
	end
	local placeRect = Vector2.new(ringPosition.X, aboveTop)
	local placeSize = Vector2.new(ringSize.X, ringSize.Y + (ringPosition.Y - aboveTop))
	local side = chooseSide(self.Options.Sides or DEFAULT_SIDES, placeRect, placeSize, bounds, bubbleSize, hand)
	local bounce = BOUNCE * scale * wave
	local centre = ringPosition + ringSize / 2
	local handPosition, bubblePosition
	if side == "Left" then
		handPosition = Vector2.new(ringPosition.X - GAP - hand - bounce, centre.Y - hand / 2)
		bubblePosition = Vector2.new(handPosition.X - GAP - bubbleSize.X, centre.Y - bubbleSize.Y / 2)
	elseif side == "Right" then
		handPosition = Vector2.new(ringPosition.X + ringSize.X + GAP + bounce, centre.Y - hand / 2)
		bubblePosition = Vector2.new(handPosition.X + hand + GAP, centre.Y - bubbleSize.Y / 2)
	elseif side == "Above" then
		handPosition = Vector2.new(centre.X - hand / 2, aboveTop - GAP - hand - bounce)
		bubblePosition = Vector2.new(centre.X - bubbleSize.X / 2, handPosition.Y - GAP - bubbleSize.Y)
	else
		handPosition = Vector2.new(centre.X - hand / 2, ringPosition.Y + ringSize.Y + GAP + bounce)
		bubblePosition = Vector2.new(centre.X - bubbleSize.X / 2, handPosition.Y + hand + GAP)
	end
	handPosition = clampBox(handPosition, Vector2.new(hand, hand), bounds)
	bubblePosition = clampBox(bubblePosition, bubbleSize, bounds)

	self.Hand.Text = HANDS[side]
	self.Hand.Size = UDim2.fromOffset(hand, hand)
	self.Hand.Position = UDim2.fromOffset(handPosition.X, handPosition.Y)
	self.Bubble.Position = UDim2.fromOffset(bubblePosition.X, bubblePosition.Y)
	self.Side = side
	self.Ring.Visible = true
	self.Hand.Visible = true
	self.Bubble.Visible = true
end

function GuidePointer:destroy()
	self:clear()
	self.Gui:Destroy()
end

return GuidePointer
