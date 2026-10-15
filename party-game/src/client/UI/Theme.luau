--[[
	Theme
	Colours, fonts and tiny helpers for building UI in code (no Studio-made GUIs needed).
]]

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.TitleFont = Enum.Font.FredokaOne
Theme.BodyFont = Enum.Font.GothamBold

Theme.Colors = {
	Overlay = Color3.fromRGB(20, 10, 40),
	Card = Color3.fromRGB(45, 30, 80),
	CardLight = Color3.fromRGB(70, 50, 120),
	Accent = Color3.fromRGB(255, 220, 60),
	Hot = Color3.fromRGB(255, 90, 140),
	Cool = Color3.fromRGB(90, 220, 255),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(200, 190, 230),
	Good = Color3.fromRGB(120, 255, 140),
}

Theme.TeamColors = {
	[1] = Color3.fromRGB(255, 90, 90),
	[2] = Color3.fromRGB(90, 160, 255),
}

Theme.PlacementColors = {
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(200, 210, 225),
	Color3.fromRGB(215, 140, 70),
	Color3.fromRGB(140, 130, 170),
}

-- make("Frame", { Size = ..., Parent = x }, { children })
function Theme.make(className: string, props: { [string]: any }?, children: { Instance }?)
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

function Theme.corner(radius: number?)
	return Theme.make("UICorner", { CornerRadius = UDim.new(0, radius or 14) })
end

function Theme.stroke(color: Color3?, thickness: number?)
	return Theme.make("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(pixels: number)
	local p = UDim.new(0, pixels)
	return Theme.make("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

-- Scaled text label with a max size so it stays readable on phones and huge monitors.
function Theme.label(props: { [string]: any }, maxTextSize: number?)
	local label = Theme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		TextWrapped = true,
	})
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	Theme.make("UITextSizeConstraint", { MaxTextSize = maxTextSize or 28, MinTextSize = 8, Parent = label })
	label.Parent = props.Parent
	return label
end

-- Bouncy "pop in" used for cards and banners. Ends at the element's phone HUD scale
-- (the "HudScale" attribute set by the client main script), not always at 1.
function Theme.pop(guiObject: GuiObject)
	local scale = guiObject:FindFirstChildOfClass("UIScale") or Theme.make("UIScale", { Parent = guiObject })
	local target = guiObject:GetAttribute("HudScale") or 1
	scale.Scale = target * 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end

-- "1:05" style clock.
function Theme.formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

function Theme.ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return n .. suffix
end

return Theme
