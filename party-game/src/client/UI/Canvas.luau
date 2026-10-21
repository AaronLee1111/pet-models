--[[
	Canvas
	Full-screen presentation helper for the minigame pick and tutorial screens: an opaque
	sea-green backdrop (the board / arena setup never shows behind it) and a 1280x720 design
	canvas, scaled to fit and centred in the space below Roblox's top bar.

	  local root, canvas = Canvas.new(parent, name)
	  Canvas.fit(root, canvas, height?)  call when shown and every frame (cheap); height = the
	                                     canvas's design height (default 720; shorter = bigger)
	  Canvas.wide(root)                  true on wide, short screens (landscape phones)
]]

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local make = Theme.make

local Canvas = {}

Canvas.SIZE = Vector2.new(1280, 720)

function Canvas.new(parent: Instance, name: string)
	local root = make("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), -- the gradient below sets the colour
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	}, {
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(44, 132, 118), Color3.fromRGB(18, 76, 70)),
		}),
	})
	local canvas = make("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Canvas.SIZE.X, Canvas.SIZE.Y),
		BackgroundTransparency = 1,
		Parent = root,
	})
	make("UIScale", { Parent = canvas })
	Canvas.fit(root, canvas)
	return root, canvas
end

function Canvas.wide(root: GuiObject): boolean
	local size = root.AbsoluteSize
	return size.X / math.max(1, size.Y - GuiService:GetGuiInset().Y) > 1.95
end

function Canvas.fit(root: GuiObject, canvas: GuiObject, designHeight: number?)
	local size = root.AbsoluteSize
	local top = GuiService:GetGuiInset().Y
	local height = math.max(1, size.Y - top)
	local design = designHeight or Canvas.SIZE.Y
	canvas.Size = UDim2.fromOffset(Canvas.SIZE.X, design)
	local scale = math.min(size.X / Canvas.SIZE.X, height / design)
	local uiScale = canvas:FindFirstChildOfClass("UIScale")
	if uiScale and math.abs(uiScale.Scale - scale) > 0.001 then
		uiScale.Scale = scale
	end
	canvas.Position = UDim2.fromOffset(size.X / 2, top + height / 2)
end

return Canvas
