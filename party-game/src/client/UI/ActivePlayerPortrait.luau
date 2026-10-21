--[[
	ActivePlayerPortrait
	The active participant's real avatar (clothes, body colours, accessories) in a ViewportFrame,
	lower-left, facing inward toward the board. Big during the turn-start banner, normal while
	they choose, gone while they move.

	  local portrait = ActivePlayerPortrait.new(screen)
	  portrait:show(character, "Big" | "Normal")
	  portrait:hide()
	  portrait.Root                        position it from BoardView:layout()

	  ActivePlayerPortrait.mount(viewport, character, framing) -> Model?
	      copies a character into any ViewportFrame ("Head" for standings chips, "Body" here)
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local ActivePlayerPortrait = {}
ActivePlayerPortrait.__index = ActivePlayerPortrait

ActivePlayerPortrait.NORMAL = Vector2.new(230, 290) -- design px (BoardView scales them)
ActivePlayerPortrait.BIG = Vector2.new(360, 450)
local TURN_IN = math.rad(28) -- yaw so the avatar faces right, toward the menu and board

-- A display-only copy of a character: anchored, no scripts, sounds, name tags or shields.
-- nil when there's nothing to copy yet. (TutorialPreview uses it for its actors too.)
function ActivePlayerPortrait.copy(character: Model?): Model?
	if not character or not character.Parent or not character:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	local archivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(character.Clone, character)
	character.Archivable = archivable
	if not ok or not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return copy
end

-- Copies `character` into `viewport` (a fresh WorldModel, so layered clothing and accessories
-- render) and aims a camera at it. Returns the copy, or nil when there's nothing to copy yet.
function ActivePlayerPortrait.mount(viewport: ViewportFrame, character: Model?, framing: string): Model?
	for _, child in viewport:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Camera") then -- keep the frame's UIScale / corner
			child:Destroy()
		end
	end
	local copy = ActivePlayerPortrait.copy(character)
	if not copy then
		return nil
	end
	copy:PivotTo(CFrame.Angles(0, TURN_IN, 0))
	local world = make("WorldModel", { Parent = viewport })
	copy.Parent = world
	local camera = make("Camera", { FieldOfView = 30, Parent = viewport })
	viewport.CurrentCamera = camera
	-- Frame from the bounding box: works for any rig, including non-humanoid avatar shapes.
	local box, size = copy:GetBoundingBox()
	local top = box.Position.Y + size.Y / 2
	if framing == "Head" then
		local target = Vector3.new(0, top - 1.3, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.2, -6), target)
	else
		local target = Vector3.new(0, box.Position.Y, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.6, -(size.Y * 2.1 + 2)), target)
	end
	return copy
end

function ActivePlayerPortrait.new(screen: ScreenGui)
	local self = setmetatable({ Character = nil, Model = nil, Mode = nil }, ActivePlayerPortrait)
	self.Root = make("ViewportFrame", {
		Name = "ActivePlayerPortrait",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(ActivePlayerPortrait.NORMAL.X, ActivePlayerPortrait.NORMAL.Y),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.fromRGB(255, 244, 220),
		LightDirection = Vector3.new(-1, -1, -1),
		Visible = false,
		Parent = screen,
	})
	self.Scale = make("UIScale", { Parent = self.Root })
	-- Gentle idle: a slow bob and sway (the copy is anchored; no animator needed).
	RunService.RenderStepped:Connect(function()
		if self.Root.Visible and self.Model and self.Model.Parent then
			local t = os.clock()
			self.Model:PivotTo(CFrame.new(0, math.sin(t * 2.2) * 0.06, 0) * CFrame.Angles(0, TURN_IN + math.sin(t * 0.9) * 0.1, 0))
		end
	end)
	return self
end

function ActivePlayerPortrait:show(character: Model?, mode: string)
	if character ~= self.Character or not (self.Model and self.Model.Parent) then
		self.Character = character
		self.Model = ActivePlayerPortrait.mount(self.Root, character, "Body")
	end
	if not self.Model then
		self:hide()
		return
	end
	local size = if mode == "Big" then ActivePlayerPortrait.BIG else ActivePlayerPortrait.NORMAL
	local goal = UDim2.fromOffset(size.X, size.Y)
	if not self.Root.Visible then
		self.Root.Size = goal
		self.Root.Visible = true
		self.Root.ImageTransparency = 1
		TweenService:Create(self.Root, TweenInfo.new(0.2), { ImageTransparency = 0 }):Play()
	elseif mode ~= self.Mode then
		TweenService:Create(self.Root, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = goal }):Play()
	end
	self.Mode = mode
end

function ActivePlayerPortrait:hide()
	self.Root.Visible = false
	self.Mode = nil
end

return ActivePlayerPortrait
