--[[
	ShopScreen
	The permanent Cosmetics Shop, opened from the waiting room (SHOP button, B key or
	gamepad Select). Functional placeholder look: one card per cosmetic with a big colour
	swatch standing in for the hero image, name, slot, rarity, bank price and state.

	  PREVIEW   shows it on your own character, only on your screen, until you close the shop
	  BUY       tap once to see the price, tap again within 3 s to confirm (server checks all)
	  WEAR / REMOVE  equip / unequip something you own

	Sits on the right so your character stays visible on the left; never covers Roblox's
	top bar. The server decides everything; this only sends requests and shows replies.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cosmetics = require(ReplicatedStorage:WaitForChild("PartyShared"):WaitForChild("Cosmetics"))
local Theme = require(script.Parent.Theme)
local make = Theme.make

local ShopScreen = {}
ShopScreen.__index = ShopScreen

local TOGGLE_ACTION = "PartyShopToggle"
local PREVIEW_TAG = "PartyPreview"
local CONFIRM_TIME = 3
local RARITY_COLORS = {
	Common = Color3.fromRGB(200, 200, 215),
	Rare = Color3.fromRGB(90, 170, 255),
	Epic = Color3.fromRGB(200, 110, 255),
}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The colour that stands in for an item's hero image.
local function swatchColor(item): Color3
	local visual = item.Visual or {}
	if visual.Color then
		return rgb(visual.Color)
	elseif visual.Colors then
		return rgb(visual.Colors[1])
	end
	return Theme.Colors.CardLight
end

function ShopScreen.new(screen: ScreenGui, send: (any) -> ())
	local self = setmetatable({ Send = send, Inventory = nil, Pending = nil, PreviewId = nil, Open = false }, ShopScreen)

	self.Root = make("Frame", {
		Name = "CosmeticShop",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(580, 360),
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	}, { Theme.corner(18), Theme.stroke(Theme.Colors.Accent, 3), Theme.padding(10) })

	self.Title = Theme.label({
		Size = UDim2.new(0.62, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.TitleFont,
		TextColor3 = Theme.Colors.Accent,
		Text = "COSMETICS SHOP",
		Parent = self.Root,
	}, 28)
	self.Balance = Theme.label({
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(0.7, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Bank: 0 coins",
		Parent = self.Root,
	}, 20)
	self.CloseButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(110, 52),
		BackgroundColor3 = Theme.Colors.CardLight,
		Font = Theme.TitleFont,
		TextScaled = true,
		TextColor3 = Theme.Colors.Text,
		Text = "CLOSE",
		Parent = self.Root,
	}, { Theme.corner(12), Theme.padding(8) })
	self.CloseButton.Activated:Connect(function()
		self:close()
	end)

	self.Grid = make("ScrollingFrame", {
		Name = "Cards",
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -62 - 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = self.Root,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.fromOffset(176, 222),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.Status = Theme.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Muted,
		Text = "",
		Parent = self.Root,
	}, 20)
	return self
end

-- Preview ------------------------------------------------------------------------------------
-- Client-only parts on your own character (nobody else sees them; the server's real
-- cosmetics are left alone).

function ShopScreen:clearPreview()
	local character = Players.LocalPlayer.Character
	if character then
		for _, descendant in character:GetDescendants() do
			if string.sub(descendant.Name, 1, #PREVIEW_TAG) == PREVIEW_TAG then
				descendant:Destroy()
			end
		end
	end
	self.PreviewId = nil
end

function ShopScreen:preview(item)
	self:clearPreview()
	local character = Players.LocalPlayer.Character
	local visual = item.Visual
	if not character or not visual then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if visual.Kind == "Hat" and head then
		local hat = Instance.new("Part")
		hat.Name = PREVIEW_TAG .. "Hat"
		hat.Shape = Enum.PartType[visual.Shape] or Enum.PartType.Block
		hat.Size = Vector3.new(visual.Size[1], visual.Size[2], visual.Size[3])
		hat.Color = rgb(visual.Color)
		hat.CanCollide, hat.CanQuery, hat.CanTouch, hat.Massless = false, false, false, true
		hat.Transparency = 0.2
		local height = if hat.Shape == Enum.PartType.Cylinder then hat.Size.X else hat.Size.Y
		local tilt = if hat.Shape == Enum.PartType.Cylinder then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity
		hat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + height / 2 + 0.6, 0) * tilt -- floats above any real hat
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head, hat
		weld.Parent = hat
		hat.Parent = character
	elseif visual.Kind == "Trail" and root then
		local a0 = Instance.new("Attachment")
		a0.Name, a0.Position = PREVIEW_TAG .. "Top", Vector3.new(0, 0.8, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name, a1.Position = PREVIEW_TAG .. "Bottom", Vector3.new(0, -0.8, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = PREVIEW_TAG .. "Trail"
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.45
		trail.Color = ColorSequence.new(rgb(visual.Colors[1]), rgb(visual.Colors[2]))
		trail.Parent = root
	elseif visual.Kind == "Sparkles" and root then
		local sparkles = Instance.new("Sparkles")
		sparkles.Name = PREVIEW_TAG .. "Sparkles"
		sparkles.SparkleColor = rgb(visual.Color)
		sparkles.Parent = root
	end
	self.PreviewId = item.Id
end

-- Cards --------------------------------------------------------------------------------------

local function cardButton(parent, order: number, text: string, color: Color3, textColor: Color3?)
	return make("TextButton", {
		Name = if order == 1 then "Try" else "Action",
		LayoutOrder = order,
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = color,
		Font = Theme.TitleFont,
		TextScaled = true,
		TextColor3 = textColor or Theme.Colors.Overlay,
		Text = text,
		Parent = parent,
	}, { Theme.corner(10), Theme.padding(6), make("UITextSizeConstraint", { MaxTextSize = 22 }) })
end

function ShopScreen:render()
	for _, child in self.Grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local inventory = self.Inventory or { Owned = {}, Equipped = {}, BankCoins = 0 }
	local owned, equipped = {}, inventory.Equipped or {}
	for _, entry in inventory.Owned or {} do
		owned[entry.Id] = true
	end
	self.Balance.Text = ("Bank: %d coins"):format(inventory.BankCoins or 0)

	local firstButton
	for index, item in Cosmetics.Items do
		local price = Cosmetics.bankPrice(item)
		local isOwned, isWorn = owned[item.Id] == true, equipped[item.Slot] == item.Id
		local card = make("Frame", {
			Name = "Card_" .. item.Id,
			LayoutOrder = index,
			BackgroundColor3 = if isWorn then Theme.Colors.CardLight else Theme.Colors.Overlay,
			Parent = self.Grid,
		}, { Theme.corner(12), Theme.padding(6), Theme.stroke(RARITY_COLORS[item.Rarity] or Theme.Colors.Muted, 2) })
		make("Frame", {
			Name = "Hero",
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = swatchColor(item),
			Parent = card,
		}, { Theme.corner(10) })
		Theme.label({
			Position = UDim2.fromOffset(0, 66),
			Size = UDim2.new(1, 0, 0, 24),
			Font = Theme.TitleFont,
			Text = item.Name,
			Parent = card,
		}, 22)
		Theme.label({
			Position = UDim2.fromOffset(0, 90),
			Size = UDim2.new(1, 0, 0, 20),
			TextColor3 = RARITY_COLORS[item.Rarity] or Theme.Colors.Muted,
			Text = ("%s · %s"):format(item.Slot, item.Rarity or "Common"),
			Parent = card,
		}, 18)
		Theme.label({
			Position = UDim2.fromOffset(0, 110),
			Size = UDim2.new(1, 0, 0, 22),
			TextColor3 = Theme.Colors.Accent,
			Text = if isWorn then "WEARING" elseif isOwned then "OWNED" else ("%d bank coins"):format(price),
			Parent = card,
		}, 20)
		local row = make("Frame", {
			Name = "Buttons",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local previewing = self.PreviewId == item.Id
		local previewButton = cardButton(row, 1, if previewing then "HIDE" else "TRY", Theme.Colors.Cool)
		previewButton.Activated:Connect(function()
			if self.PreviewId == item.Id then
				self:clearPreview()
			else
				self:preview(item)
			end
			self:render()
		end)
		firstButton = firstButton or previewButton

		local action
		if isWorn then
			action = cardButton(row, 2, "REMOVE", Theme.Colors.Hot) -- must stand out from the worn card
			action.Activated:Connect(function()
				self:setStatus("Taking it off...")
				self.Send({ Kind = "Unequip", Slot = item.Slot })
			end)
		elseif isOwned then
			action = cardButton(row, 2, "WEAR", Theme.Colors.Good)
			action.Activated:Connect(function()
				self:setStatus("Putting it on...")
				self.Send({ Kind = "Equip", ItemId = item.Id })
			end)
		else
			local confirming = self.Pending and self.Pending.Id == item.Id and os.clock() < self.Pending.Until
			local affordable = (inventory.BankCoins or 0) >= price
			action = cardButton(
				row,
				2,
				if confirming then ("PAY %d?"):format(price) else "BUY",
				if confirming then Theme.Colors.Hot elseif affordable then Theme.Colors.Accent else Theme.Colors.CardLight,
				if affordable or confirming then Theme.Colors.Overlay else Theme.Colors.Muted
			)
			action.Activated:Connect(function()
				if not affordable then
					self:setStatus(("You need %d more bank coins. Win matches to earn them."):format(price - (inventory.BankCoins or 0)), true)
				elseif self.Pending and self.Pending.Id == item.Id and os.clock() < self.Pending.Until then
					self.Pending = nil
					self:setStatus("Buying...")
					self.Send({ Kind = "BuyCosmetic", ItemId = item.Id })
				else
					self.Pending = { Id = item.Id, Until = os.clock() + CONFIRM_TIME }
					self:setStatus(("Tap PAY to buy the %s for %d bank coins."):format(item.Name, price))
					self:render()
					task.delay(CONFIRM_TIME, function()
						if self.Pending and self.Pending.Id == item.Id and os.clock() >= self.Pending.Until then
							self.Pending = nil
							if self.Open then
								self:render()
							end
						end
					end)
				end
			end)
		end
	end
	return firstButton
end

function ShopScreen:setStatus(text: string, isError: boolean?)
	self.Status.Text = text
	self.Status.TextColor3 = if isError then Theme.Colors.Hot else Theme.Colors.Muted
end

-- Called with every Inventory message (owned, equipped, bank coins).
function ShopScreen:setInventory(message)
	self.Inventory = message
	if self.Open then
		self:render()
	end
end

-- Called with the server's reply to a purchase.
function ShopScreen:showResult(message)
	self:setStatus(message.Text or (if message.Ok then "Done!" else "That didn't work."), not message.Ok)
	if self.Open then
		self:render()
	end
end

-- Open / close ---------------------------------------------------------------------------------

function ShopScreen:open()
	if self.Open then
		return
	end
	self.Open = true
	self.Root.Visible = true
	self:setStatus("Spend bank coins on cosmetics you keep forever.")
	local first = self:render()
	Theme.pop(self.Root)
	if UserInputService.GamepadEnabled and first then
		GuiService.SelectedObject = first -- gamepad: start on the first card
	end
	if self.OnOpenChanged then
		self.OnOpenChanged(true)
	end
end

function ShopScreen:close()
	if not self.Open then
		return
	end
	self.Open = false
	self.Root.Visible = false
	self.Pending = nil
	self:clearPreview()
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Root) then
		GuiService.SelectedObject = nil
	end
	if self.OnOpenChanged then
		self.OnOpenChanged(false)
	end
end

function ShopScreen:toggle()
	if self.Open then
		self:close()
	else
		self:open()
	end
end

-- Keyboard B / gamepad Select open and close it, only while `allowed` (the waiting room).
function ShopScreen:setAvailable(allowed: boolean)
	if allowed then
		ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self:toggle()
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.B, Enum.KeyCode.ButtonSelect)
	else
		ContextActionService:UnbindAction(TOGGLE_ACTION)
		self:close()
	end
end

return ShopScreen
