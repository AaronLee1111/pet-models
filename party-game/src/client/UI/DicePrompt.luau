--[[
	DicePrompt
	While ROLL is selected on your turn: a physical die hovers and turns above your character,
	with a short instruction ("Press Space or click the die" / "Tap the die" / "Press A").
	Clicking or tapping the die rolls. The throw itself is BoardDice (the server picks the number).

	  local prompt = DicePrompt.new(playerGui, onActivate)
	  prompt:show(character, hint)
	  prompt:hide()
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BoardDice = require(script.Parent.BoardDice)
local Theme = require(script.Parent.Theme)
local make = Theme.make

local DicePrompt = {}
DicePrompt.__index = DicePrompt

-- Above the head and the YOU tag; the throw starts here. Phones sit lower so the die stays
-- below the standings strip in the close camera.
DicePrompt.HOVER = Vector3.new(0, if game:GetService("UserInputService").TouchEnabled then 5.5 else 8.4, 0)
local HOVER = DicePrompt.HOVER

function DicePrompt.new(playerGui: PlayerGui, onActivate: () -> ())
	local self = setmetatable({ Root = nil }, DicePrompt)
	-- In PlayerGui (not the Workspace) so the billboard button receives clicks and taps. The
	-- click target is sized in studs (plus a margin), so it covers the die at any distance.
	self.Gui = make("BillboardGui", {
		Name = "DicePrompt",
		Size = UDim2.new(4.6, 24, 4.6, 24), -- studs + 24 px: never under a 44 px tap target
		Active = true, -- a BillboardGui only passes clicks and taps to its button when Active
		LightInfluence = 0,
		Enabled = false,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	self.Button = make("TextButton", {
		Name = "Die",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = self.Gui,
	})
	-- Desktop: above the die. Phone: beside it, smaller (above would sit under the standings).
	local touch = game:GetService("UserInputService").TouchEnabled
	self.HintGui = make("BillboardGui", {
		Name = "DicePromptHint",
		Size = if touch then UDim2.fromOffset(150, 34) else UDim2.fromOffset(280, 52),
		-- SizeOffset Y 0.5: the hint's bottom edge sits at the offset point, just over the die.
		SizeOffset = if touch then Vector2.new(0.85, 0) else Vector2.new(0, 0.5),
		StudsOffsetWorldSpace = if touch then Vector3.zero else Vector3.new(0, 2.2, 0),
		LightInfluence = 0,
		Enabled = false,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	self.Hint = Theme.glass(make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.TitleFont,
		TextSize = if touch then 15 else 24,
		TextWrapped = true,
		TextColor3 = Theme.Glass.Cream,
		Parent = self.HintGui,
	}), 16)
	self.Button.Activated:Connect(onActivate)
	return self
end

function DicePrompt:show(character: Model?, hint: string)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		self:hide()
		return
	end
	self.Hint.Text = hint
	if not (self.Die and self.Die.Parent) then
		self.Die = BoardDice.makeDie()
		self.Die.Name = "HoverDie"
		self.Die.Parent = Workspace.CurrentCamera
	end
	self.Gui.Adornee = self.Die
	self.HintGui.Adornee = self.Die
	self.Gui.Enabled = true
	self.HintGui.Enabled = true
	if not self.Connection then
		self.Connection = RunService.RenderStepped:Connect(function()
			if not (self.Die and self.Die.Parent and root.Parent) then
				return
			end
			local t = os.clock()
			self.Die.CFrame = CFrame.new(root.Position + HOVER + Vector3.new(0, math.sin(t * 2.4) * 0.35, 0))
				* CFrame.Angles(math.rad(20), t * 1.6, math.rad(12))
		end)
	end
end

function DicePrompt:hide()
	self.Gui.Enabled = false
	self.HintGui.Enabled = false
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	if self.Die then
		self.Die:Destroy()
		self.Die = nil
	end
end

return DicePrompt
