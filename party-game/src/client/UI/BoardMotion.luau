--[[
	BoardMotion
	Runs board pieces along the route the server sends after a roll (Message.BoardMove): turn
	toward the segment, run the visible path (curves, slopes and every stair step are points in
	it), a small hop onto the next space, land facing the route. Presentation only: pieces are
	anchored and the server snaps each one to its confirmed space when the segment ends, so a
	late, missed or failed animation just shows that snap and never holds the match up.

	  BoardMotion.play(message)          start a segment (a newer one for the same piece replaces it)
	  BoardMotion.update(dt)             every frame
	  BoardMotion.stopAll()              leaving the board
	  BoardMotion.sample(points, d)      -> position d studs along the path, segment direction (pure)
	  BoardMotion.track(character, name) -> the character's own "run" / "wave" AnimationTrack

	Animations are the character's own Animate script ones (Roblox's default R15 ones when a
	body has none); nothing is uploaded.
]]

local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local BoardMotion = {}

local HOP_HEIGHT = 1.1 -- studs: the step-up onto the next space
local TURN_RATE = 16 -- facing catch-up per second (higher = snappier turns)
local RUN_SPEED = 16 -- studs/s the run cycle is authored for
-- Roblox's own default R15 animations, used only when a body has no Animate script.
local DEFAULT_ANIMATIONS = { run = "rbxassetid://913376220", wave = "rbxassetid://507770239" }

local moves = {} -- [character] = the segment in progress
local tracks = setmetatable({}, { __mode = "k" }) -- [character] = { [name] = AnimationTrack }

local function reducedMotion(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end
BoardMotion.reducedMotion = reducedMotion

function BoardMotion.sample(points: { Vector3 }, distance: number): (Vector3, Vector3)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local length = (b - a).Magnitude
		if distance <= length or i == #points then
			return a:Lerp(b, if length > 0 then math.clamp(distance / length, 0, 1) else 1), b - a
		end
		distance -= length
	end
	return points[1], Vector3.zero
end

function BoardMotion.length(points: { Vector3 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

function BoardMotion.track(character: Model, name: string): AnimationTrack?
	local cache = tracks[character]
	if cache and cache[name] then
		return cache[name]
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animate = character:FindFirstChild("Animate")
	local folder = animate and animate:FindFirstChild(name)
	local animation = folder and folder:FindFirstChildOfClass("Animation")
	if not animation then
		animation = Instance.new("Animation")
		animation.AnimationId = DEFAULT_ANIMATIONS[name]
	end
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		return nil
	end
	track.Priority = if name == "run" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
	tracks[character] = cache or {}
	tracks[character][name] = track
	return track
end

local function rootOf(character: Model?): BasePart?
	return character and character.Parent and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function finish(character: Model, move)
	moves[character] = nil
	if move.Track then
		move.Track:Stop(0.15)
	end
	local root = rootOf(character)
	if root then
		local last = move.Points[#move.Points]
		local face = flat(move.Face or Vector3.zero)
		root.CFrame = if face.Magnitude > 0.01 then CFrame.lookAt(last, last + face) else CFrame.new(last) * root.CFrame.Rotation
	end
end

function BoardMotion.play(message)
	local character = message.Character
	local root = rootOf(character)
	local points = message.Points
	if not root or type(points) ~= "table" or #points < 2 then
		return -- the server's snap still puts it on the space
	end
	local previous = moves[character]
	if previous then
		finish(character, previous)
	end
	local move = {
		Points = points,
		Total = BoardMotion.length(points),
		StartsAt = message.StartsAt,
		Duration = math.max(0.05, message.Duration or 0.35),
		Face = message.Face,
		Look = flat(root.CFrame.LookVector),
	}
	if reducedMotion() then
		-- No run: wait out the segment, then appear on the space (no hop, no camera swing).
		move.Instant = true
	else
		move.Track = BoardMotion.track(character, "run")
		if move.Track then
			move.Track:Play(0.1)
			move.Track:AdjustSpeed(math.clamp(move.Total / move.Duration / RUN_SPEED, 0.8, 1.8))
		end
	end
	moves[character] = move
end

function BoardMotion.update(dt: number)
	local now = Workspace:GetServerTimeNow()
	for character, move in moves do
		local root = rootOf(character)
		if not root then
			moves[character] = nil
			continue
		end
		local u = (now - move.StartsAt) / move.Duration
		if u >= 1 then
			finish(character, move)
			continue
		end
		if move.Instant or u < 0 then
			continue
		end
		-- Mostly even pace with a soft start and finish.
		local eased = 0.75 * u + 0.25 * u * u * (3 - 2 * u)
		local distance = move.Total * eased
		local position, direction = BoardMotion.sample(move.Points, distance)
		-- The hop onto the next space over the last stretch.
		local window = math.min(move.Total, math.max(3, move.Total * 0.3))
		local s = (distance - (move.Total - window)) / window
		if s > 0 then
			position += Vector3.new(0, HOP_HEIGHT * 4 * s * (1 - s), 0)
		end
		local heading = flat(direction)
		if heading.Magnitude > 0.05 then
			move.Look = move.Look:Lerp(heading.Unit, 1 - math.exp(-TURN_RATE * dt))
		end
		root.CFrame = if move.Look.Magnitude > 0.01 then CFrame.lookAt(position, position + move.Look) else CFrame.new(position)
	end
end

function BoardMotion.isMoving(character: Model?): boolean
	return character ~= nil and moves[character] ~= nil
end

function BoardMotion.stopAll()
	for character, move in moves do
		finish(character, move)
	end
end

return BoardMotion
