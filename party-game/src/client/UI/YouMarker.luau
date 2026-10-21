--[[
	YouMarker
	A "YOU" tag with a small arrow, floating above your own character (on the board and in
	minigames) so you can find yourself among four similar bodies. Only on this client: the
	BillboardGui lives in your PlayerGui, so nobody else sees it, and it's never put on bots
	or other players.

	  YouMarker.new(getCharacter, parent)   getCharacter() -> your current character (or nil)
	  marker:setActive(on)                  Main turns it on only while you're an active
	                                        participant and no full-screen card is up
	  marker:update()                       every frame: (re)attach to the current head, keep a
	                                        readable size at any camera distance

	Its arrow tip sits just above the top of the character, cosmetics included, and it stays
	upright facing the camera, as billboards do. A new character (respawn, replaced body) is picked up on the next frame.
]]

local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local YouMarker = {}
YouMarker.__index = YouMarker

local HEIGHT_STUDS = 1.6 -- tag height it aims for in the world...
local MIN_PIXELS, MAX_PIXELS = 26, 40 -- ...kept between these on screen (phone readable)
local CLEARANCE = 0.8 -- studs between the top of the character (hats, buckets...) and the arrow tip
local MIN_ABOVE_HEAD = 1.5 -- never lower than this above the head's centre

function YouMarker.new(getCharacter: () -> Model?, parent: Instance)
	local self = setmetatable({ GetCharacter = getCharacter, Active = false }, YouMarker)
	self.Gui = make("BillboardGui", {
		Name = "YouMarker",
		-- Not AlwaysOnTop: it floats above the head with nothing in front of it from these
		-- cameras, and always-on-top billboards didn't render in Studio's capture.
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(78, 64),
		-- The gui's bottom edge (the arrow tip) sits at the anchor point, so it never hangs down
		-- over the character however big the tag is on screen.
		SizeOffset = Vector2.new(0, 0.5),
		StudsOffsetWorldSpace = Vector3.new(0, MIN_ABOVE_HEAD, 0),
		MaxDistance = 1000,
		Enabled = false,
		Parent = parent,
	})
	self.Tag = make("Frame", {
		Name = "Tag",
		Size = UDim2.fromScale(1, 0.66),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 0.05,
		Parent = self.Gui,
	}, { Theme.corner(10), Theme.stroke(Theme.Colors.Accent, 3) })
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.TitleFont,
		Text = "YOU",
		TextColor3 = Theme.Colors.Text,
		Parent = self.Tag,
	}, 40)
	self.Arrow = make("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromScale(0.4, 0.36),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextScaled = true,
		Text = "▼",
		TextColor3 = Theme.Colors.Accent,
		TextStrokeColor3 = Theme.Colors.Overlay,
		TextStrokeTransparency = 0,
		Parent = self.Gui,
	})
	return self
end

--[[
	Should the marker show? state = {
	  CardOpen     a full-screen card (minigame pick, tutorial, results, standings) is up
	  Phase        current Net.Phase name
	  InRound      a minigame is on for this client
	  Participant  you play this minigame (not a spectator)
	  Spectating   the spectator camera is on (watching, or knocked out)
	  OnBoard      board HUD showing
	  Seated       you hold a seat in this board match
	}
]]
function YouMarker.shouldShow(state): boolean
	if state.CardOpen then
		return false
	end
	if state.InRound then
		local live = state.Phase == "Countdown" or state.Phase == "Playing" or state.Phase == "Finished"
		return live and state.Participant == true and not state.Spectating
	end
	return state.Phase == "Board" and state.OnBoard == true and state.Seated == true
end

function YouMarker:setActive(active: boolean)
	self.Active = active
	if not active then
		self.Gui.Enabled = false
	end
end

local function headOf(character: Model?): BasePart?
	if not character or not character.Parent then
		return nil
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	return if head and head:IsA("BasePart") then head else nil
end

-- On-screen tag height in pixels for a head this far from the camera.
function YouMarker.pixelHeight(distance: number, viewportHeight: number, fieldOfView: number): number
	local pixelsPerStud = (viewportHeight / 2) / math.tan(math.rad(fieldOfView) / 2) / math.max(distance, 1)
	return math.clamp(HEIGHT_STUDS * pixelsPerStud, MIN_PIXELS, MAX_PIXELS)
end

function YouMarker:update()
	local head = if self.Active then headOf(self.GetCharacter()) else nil
	if not head then
		self.Gui.Enabled = false
		self.Gui.Adornee = nil
		return
	end
	if self.Gui.Adornee ~= head then
		self.Gui.Adornee = head -- first time, or a new character
	end
	-- Just above whatever is highest on the character: hats, and anything welded to it from
	-- elsewhere (Kernel Catch's popcorn bucket lives in the arena, not in the character).
	local top = head.Position.Y + head.Size.Y / 2
	local ok, parts = pcall(head.GetConnectedParts, head, true)
	for _, part in if ok then parts else {} do
		if part.Transparency < 1 then
			top = math.max(top, part.Position.Y + part.Size.Magnitude / 2)
		end
	end
	local above = math.max(MIN_ABOVE_HEAD, top - head.Position.Y + CLEARANCE)
	if math.abs(self.Gui.StudsOffsetWorldSpace.Y - above) > 0.05 then
		self.Gui.StudsOffsetWorldSpace = Vector3.new(0, above, 0)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		local height = YouMarker.pixelHeight(
			(camera.CFrame.Position - head.Position).Magnitude,
			camera.ViewportSize.Y,
			camera.FieldOfView
		)
		-- Tag is 66% of the gui; the arrow hangs under it.
		local tag = height / 0.66
		self.Gui.Size = UDim2.fromOffset(math.floor(height * 1.7), math.floor(tag))
	end
	self.Gui.Enabled = true
end

function YouMarker:destroy()
	self.Gui:Destroy()
end

return YouMarker
