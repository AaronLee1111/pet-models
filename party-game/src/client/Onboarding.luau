--[[
	Onboarding (guided first actions)
	Leads a new player to each control the first time they need it, one at a time, with the
	GuidePointer (bouncing hand + ring + short label). Only this player is guided; nothing about
	it is sent to anyone else.

	  1 START (host only)              StartedMatch
	  2 ROLL for turn order            RolledForOrder      "Roll to decide turn order."
	  3 ROLL on a board turn           RolledBoardTurn     "Roll to move."
	  4 an item you could use          SawItem             what it does + "or roll without it"
	  5 a fork                         ChoseFork           rings every route, suggests the one
	                                                       closest to the Crown, numbers match the
	                                                       route on the board
	  6 the minigame action            UsedMinigameAction  real label: MASH, DASH, LEFT / RIGHT...
	                                                       (movement-only games: a short "move"
	                                                       hint, once per session, no flag)
	  7 a Crown you can afford         SawCrownPurchase    "Crowns win the match..."

	The server keeps the flags (Tutorial.luau, saved in the profile) and sets each one only when
	the action really went through; the client also marks a step done the moment you press,
	so the pointer goes away at once. Until the server has sent the flags, nothing is shown
	(so returning players never see a flash of tutorial).

	Onboarding.decide(context) is the whole rule set as a pure function (unit tested); the
	object below builds the context from the live UI every frame and drives the pointer.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UI = script.Parent:WaitForChild("UI")
local InputHint = require(UI:WaitForChild("InputHint"))
local GuidePointer = require(UI:WaitForChild("GuidePointer"))
local Theme = require(UI:WaitForChild("Theme"))
local make = Theme.make

local Onboarding = {}
Onboarding.__index = Onboarding

Onboarding.MOVE_HINT_SECONDS = 5

-- "TAP HERE" / "CLICK or press SPACE" / "PRESS A" for a button with a key and pad button.
local function pressText(mode: string, key: string?, pad: string?): string
	if mode == "Gamepad" and pad then
		return "PRESS " .. pad
	elseif mode == "Mouse" and key then
		return "CLICK or press " .. key
	end
	return InputHint.verb(mode) .. " HERE"
end

local function orRoll(mode: string): string
	return if mode == "Gamepad"
		then "Or press A to roll without it."
		else ("Or %s ROLL to roll without it."):format(string.lower(InputHint.verb(mode)))
end

local function done(context, flag: string): boolean
	return context.Flags[flag] == true
end

-- The recommended route: fewest moves to the Crown (nil if no route says).
function Onboarding.recommendedRoute(routes): number?
	local best, bestDistance = nil, math.huge
	for index, route in routes or {} do
		if route.CrownDistance and route.CrownDistance < bestDistance then
			best, bestDistance = index, route.CrownDistance
		end
	end
	return best
end

local function minigameStep(context)
	local round = context.Minigame
	if not round or not round.Playing or not round.Participant or round.Spectating or not round.Bound then
		return nil -- spectators, knocked-out players and anyone not in this round: nothing
	end
	local mode = context.Mode
	local actions = round.Actions or {}
	if #actions > 0 then
		if done(context, "UsedMinigameAction") then
			return nil
		end
		local first = actions[1]
		local extra = {}
		for index = 2, #actions do
			table.insert(extra, { Kind = "Action", Action = actions[index].Action })
		end
		local title
		if #actions == 2 then
			-- A pair (LEFT / RIGHT): name both.
			local words = InputHint.actionWord(first.Label) .. " / " .. InputHint.actionWord(actions[2].Label)
			if mode == "Mouse" and InputHint.keyFor(first) and InputHint.keyFor(actions[2]) then
				title = ("PRESS %s / %s"):format(InputHint.keyName(InputHint.keyFor(first)), InputHint.keyName(InputHint.keyFor(actions[2])))
			elseif mode == "Gamepad" and InputHint.gamepadFor(first, 1) and InputHint.gamepadFor(actions[2], 2) then
				title = ("PRESS %s / %s"):format(InputHint.keyName(InputHint.gamepadFor(first, 1)), InputHint.keyName(InputHint.gamepadFor(actions[2], 2)))
			else
				title = InputHint.verb(mode) .. " " .. words
			end
			if mode ~= "Touch" then
				title ..= "  (" .. words .. ")"
			end
		else
			local word = InputHint.actionWord(first.Label)
			local key = if mode == "Mouse"
				then InputHint.keyName(InputHint.keyFor(first))
				elseif mode == "Gamepad" then InputHint.keyName(InputHint.gamepadFor(first, 1))
				else nil
			title = if key then ("PRESS %s TO %s"):format(key, word) else ("%s TO %s"):format(InputHint.verb(mode), word)
		end
		return {
			Flag = "UsedMinigameAction",
			Key = "UsedMinigameAction",
			Target = { Kind = "Action", Action = first.Action },
			Extra = extra,
			Title = title,
			Note = if #actions > 2 then "Use these buttons to play." else nil,
			Sides = { "Left", "Above", "Right" },
		}
	end
	-- Movement only: a short pointer at the thumbstick (touch) or the keys (desktop).
	if round.Move and round.MoveHintDue then
		if mode == "Touch" then
			return { Key = "MoveHint", Target = { Kind = "Thumbstick" }, Title = "DRAG HERE TO MOVE", Sides = { "Above", "Right" }, Round = true }
		end
		local title = if mode == "Gamepad" then "LEFT STICK TO MOVE" else "WASD / ARROWS TO MOVE"
		if round.Jump then
			title ..= if mode == "Gamepad" then "  ·  A TO JUMP" else "  ·  SPACE TO JUMP"
		end
		return { Key = "MoveHint", Target = nil, Title = title }
	end
	return nil
end

--[[
	context = {
	  Known, Flags = { [flag] = true }, Mode = "Touch" | "Mouse" | "Gamepad",
	  Modal       a full-screen card (minigame pick, tutorial, results, standings) or the shop is up
	  Lobby       { StartVisible }                        START is on screen (host only)
	  Board       { OrderRoll, Roll, Items = { { Name, Description } }, Coins,
	                Prompt = { Kind, Price, Routes, Count }? }
	  Minigame    { Playing, Participant, Spectating, Bound, Actions, Move, Jump, MoveHintDue }
	}
	Returns at most one step: { Flag?, Key, Target, Extra?, Title, Note?, Sides? } or nil.
]]
function Onboarding.decide(context)
	if not context.Known or context.Modal then
		return nil
	end
	local mode = context.Mode

	local lobby = context.Lobby
	if lobby and lobby.StartVisible and not done(context, "StartedMatch") then
		return {
			Flag = "StartedMatch",
			Key = "StartedMatch",
			Target = { Kind = "Start" },
			Title = if mode == "Gamepad" then "SELECT HERE TO START" else InputHint.verb(mode) .. " HERE TO START",
			Sides = { "Right", "Left", "Above" },
		}
	end

	local board = context.Board
	if board then
		local prompt = board.Prompt
		if prompt and prompt.Kind == "Path" and not done(context, "ChoseFork") then
			local best = Onboarding.recommendedRoute(prompt.Routes)
			local extra = {}
			for index = 1, prompt.Count or 0 do
				if index ~= (best or 1) then
					table.insert(extra, { Kind = "Option", Index = index })
				end
			end
			local route = best and prompt.Routes[best]
			return {
				Flag = "ChoseFork",
				Key = "ChoseFork",
				Target = { Kind = "Option", Index = best or 1 },
				Extra = extra,
				Routes = prompt.Routes,
				Recommended = best,
				Title = InputHint.verb(mode) .. " A PATH",
				Note = if route
					then ("★ %d is closest to the Crown (%d move%s). Any path is fine."):format(
						best,
						route.CrownDistance,
						if route.CrownDistance == 1 then "" else "s"
					)
					else "Any path is fine. The numbers match the board.",
				Sides = { "Above" },
			}
		end
		if prompt and prompt.Kind == "Collectible" and not done(context, "SawCrownPurchase") then
			local affordable = type(prompt.Price) == "number" and type(board.Coins) == "number" and board.Coins >= prompt.Price
			if affordable then
				return {
					Flag = "SawCrownPurchase",
					Key = "SawCrownPurchase",
					Target = { Kind = "Option", Index = 1 },
					Title = InputHint.verb(mode) .. " HERE TO BUY",
					Note = "Crowns win the match. Coins break ties.",
					Sides = { "Above" },
				}
			end
			return nil
		end
		if board.OrderRoll and not done(context, "RolledForOrder") then
			return {
				Flag = "RolledForOrder",
				Key = "RolledForOrder",
				Target = { Kind = "Roll" },
				Title = pressText(mode, "SPACE", "A"),
				Note = "Roll to decide turn order.",
				Sides = { "Right", "Below" },
			}
		end
		if board.Roll then
			local items = board.Items or {}
			if #items > 0 and not done(context, "SawItem") then
				local item = items[1]
				return {
					Flag = "SawItem",
					Key = "SawItem",
					Target = { Kind = "Item", Slot = 1 },
					Title = InputHint.verb(mode) .. " HERE TO USE IT",
					Note = ("%s: %s. %s"):format(item.Name or "Item", string.gsub(item.Description or "", "%.$", ""), orRoll(mode)),
					Sides = { "Right", "Below" },
				}
			end
			if not done(context, "RolledBoardTurn") then
				return {
					Flag = "RolledBoardTurn",
					Key = "RolledBoardTurn",
					Target = { Kind = "Roll" },
					Title = pressText(mode, "SPACE", "A"),
					Note = "Roll to move.",
					Sides = { "Right", "Below" },
				}
			end
		end
	end

	return minigameStep(context)
end

-- Live controller ------------------------------------------------------------------------------

--[[
	deps = { Guide, Lobby (LobbyPanel), Board (BoardView), Shop (ShopScreen), Screen (PartyUI),
	         PlayerGui, Modals = { GuiObject } }
]]
function Onboarding.new(deps)
	local self = setmetatable({}, Onboarding)
	self.Deps = deps
	self.Guide = deps.Guide
	self.Known = false
	self.ServerFlags = {}
	self.LocalDone = {}
	self.Minigame = nil
	self.MoveHintUsed = false
	self.MoveHintUntil = 0
	self.Badges = {}
	self.BadgeKey = nil
	self.Step = nil
	return self
end

function Onboarding:setFlags(flags)
	self.Known = true
	self.ServerFlags = {}
	for flag, value in flags or {} do
		if value == true then
			self.ServerFlags[flag] = true
		end
	end
	-- The server is the authority: what this client marked on a press only bridges the gap
	-- until the server answers (and a dev reset wipes it too).
	self.LocalDone = {}
end

function Onboarding:flags()
	local flags = table.clone(self.ServerFlags)
	for flag in self.LocalDone do
		flags[flag] = true
	end
	return flags
end

function Onboarding:isDone(flag: string): boolean
	return self.ServerFlags[flag] == true or self.LocalDone[flag] == true
end

-- Main: a minigame's play phase started / ended for this client.
function Onboarding:setMinigame(info)
	self.Minigame = info
	-- Only spend the once-per-session move hint on a round you actually play.
	local movementOnly = info and info.Controls and #(info.Controls.Actions or {}) == 0 and info.Controls.Move
	if movementOnly and info.Participant and not self.MoveHintUsed then
		self.MoveHintUsed = true -- once per session
		self.MoveHintUntil = os.clock() + Onboarding.MOVE_HINT_SECONDS
	end
end

-- Every input this client sends passes through here: the step it answers is done at once.
function Onboarding:noteInput(payload)
	local kind = payload.Kind
	local step = self.Step
	if kind == "StartMatch" then
		self.LocalDone.StartedMatch = true
	elseif kind == "Roll" then
		local state = self.Deps.Board.State
		if state and state.Stage == "OrderRoll" then
			self.LocalDone.RolledForOrder = true
		else
			self.LocalDone.RolledBoardTurn = true
			if self.Deps.Board.ItemsOffered then
				self.LocalDone.SawItem = true -- rolled without using the item
			end
		end
	elseif kind == "UseItem" then
		-- Not marked here: the server may refuse the item (wrong target, cancelled). Its flag
		-- arrives when the item is really used; until then just drop the pointer.
		if step and step.Key == "SawItem" then
			self.Guide:clear("SawItem")
		end
	elseif kind == "Choice" then
		local prompt = self.Deps.Board.PromptMessage
		if prompt and prompt.Kind == "Path" then
			self.LocalDone.ChoseFork = true
		elseif prompt and prompt.Kind == "Collectible" then
			self.LocalDone.SawCrownPurchase = true
		end
	elseif kind == "Action" or kind == "ActionUsed" then
		self.LocalDone.UsedMinigameAction = true
	end
	if step and step.Flag and self.LocalDone[step.Flag] then
		self.Guide:clear(step.Key)
	end
end

local function mySeat(state)
	local myId = "player_" .. Players.LocalPlayer.UserId
	for _, seat in (state and state.Seats) or {} do
		if seat.Id == myId then
			return seat
		end
	end
	return nil
end

function Onboarding:context()
	local deps = self.Deps
	local modal = deps.Shop.Open == true
	for _, card in deps.Modals do
		if card.Visible then
			modal = true
		end
	end
	local context = { Known = self.Known, Flags = self:flags(), Mode = InputHint.mode(), Modal = modal }

	local lobby = deps.Lobby
	if lobby.Showing and GuidePointer.isOnScreen(lobby.StartButton) then
		context.Lobby = { StartVisible = true }
	end

	local board = deps.Board
	if board.Visible and board.Header.Visible and board.State then
		local state = board.State
		local seat = mySeat(state)
		local prompt = board.Prompt.Visible and board.PromptId and board.PromptMessage
		context.Board = {
			OrderRoll = board.RollButton.Visible and state.Stage == "OrderRoll",
			Roll = board.RollButton.Visible and state.Stage == "Roll",
			Items = if board.ItemsOffered and seat then seat.Items else {},
			Coins = seat and seat.Coins,
			Prompt = if prompt
				then { Kind = prompt.Kind, Price = prompt.Price, Routes = prompt.Routes, Count = #(prompt.Options or {}) }
				else nil,
		}
	end

	local round = self.Minigame
	if round then
		local controls = round.Controls or {}
		context.Minigame = {
			Playing = round.Playing,
			Participant = round.Participant,
			Spectating = round.Spectating and round.Spectating() or false,
			Bound = round.Bound and round.Bound() or false,
			Actions = controls.Actions,
			Move = controls.Move,
			Jump = controls.Jump,
			MoveHintDue = os.clock() < self.MoveHintUntil,
		}
	end
	return context
end

-- The actual GuiObject a step points at.
function Onboarding:resolve(target): GuiObject?
	if not target then
		return nil
	end
	local deps = self.Deps
	if target.Kind == "Start" then
		return deps.Lobby.StartButton
	elseif target.Kind == "Roll" then
		return deps.Board.RollButton
	elseif target.Kind == "Item" then
		for _, child in deps.Board.ItemBar:GetChildren() do
			if child:IsA("GuiButton") and child.LayoutOrder == target.Slot and deps.Board.ItemBar.Visible then
				return child
			end
		end
		return deps.Board.ItemsButton -- item list closed: point at ITEMS first
	elseif target.Kind == "Option" then
		for _, child in deps.Board.PromptButtons:GetChildren() do
			if child:IsA("GuiButton") and child.LayoutOrder == target.Index then
				return child
			end
		end
	elseif target.Kind == "Action" then
		return deps.Screen:FindFirstChild("Action_" .. target.Action, true) :: GuiObject?
	elseif target.Kind == "Thumbstick" then
		-- The stick itself, not Roblox's large invisible touch zone around it.
		local touchGui = deps.PlayerGui:FindFirstChild("TouchGui")
		for _, path in { { "DynamicThumbstickFrame", "ThumbstickStart" }, { "ThumbstickFrame", "OuterImage" } } do
			local frame = touchGui and touchGui:FindFirstChild(path[1], true)
			local stick = frame and frame:FindFirstChild(path[2])
			if stick and GuidePointer.isOnScreen(stick) then
				return stick :: GuiObject
			end
		end
	end
	return nil
end

-- Fork: a number on each route button and the same number over that route's first space.
function Onboarding:clearBadges()
	for _, badge in self.Badges do
		badge:Destroy()
	end
	self.Badges = {}
	self.BadgeKey = nil
end

function Onboarding:showBadges(step)
	local key = tostring(self.Deps.Board.PromptId)
	if self.BadgeKey == key then
		return
	end
	self:clearBadges()
	self.BadgeKey = key
	local layout = self.Deps.Board.Layout
	for index, route in step.Routes or {} do
		local text = (if index == step.Recommended then "★" else "") .. tostring(index)
		local button = self:resolve({ Kind = "Option", Index = index })
		if button then
			local chip = make("TextLabel", {
				Name = "RouteBadge",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 4, 0, 4),
				Size = UDim2.fromOffset(40, 30),
				BackgroundColor3 = Theme.Colors.Overlay,
				Font = Theme.TitleFont,
				TextScaled = true,
				TextColor3 = Theme.Colors.Accent,
				Text = text,
				Active = false,
				ZIndex = 5,
				Parent = button,
			}, { Theme.corner(10), Theme.stroke(Theme.Colors.Accent, 2) })
			table.insert(self.Badges, chip)
		end
		local position
		for _, space in (layout and layout.Spaces) or {} do
			if space.Id == route.SpaceId then
				position = space.Position
			end
		end
		if position then
			local anchor = make("Part", {
				Name = "RouteBadgeAnchor",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Transparency = 1,
				Size = Vector3.new(0.2, 0.2, 0.2),
				Position = position + Vector3.new(0, 2.5, 0), -- on the tile, below the YOU tag's height
				Parent = Workspace.CurrentCamera, -- local only
			})
			local billboard = make("BillboardGui", {
				Size = UDim2.fromOffset(42, 32),
				AlwaysOnTop = false,
				LightInfluence = 0,
				Parent = anchor,
			})
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.Colors.Overlay,
				Font = Theme.TitleFont,
				TextScaled = true,
				TextColor3 = Theme.Colors.Accent,
				Text = text,
				Parent = billboard,
			}, { Theme.corner(12), Theme.stroke(Theme.Colors.Accent, 3), Theme.padding(4) })
			table.insert(self.Badges, anchor)
		end
	end
end

function Onboarding:update()
	local step = Onboarding.decide(self:context())
	self.Step = step
	if step and step.Key == "ChoseFork" then
		self:showBadges(step)
	elseif self.BadgeKey then
		self:clearBadges()
	end
	if not step then
		self.Guide:clear()
	else
		local target = self:resolve(step.Target)
		if step.Target and not target then
			self.Guide:clear() -- not on screen yet
		else
			local extra = {}
			for _, other in step.Extra or {} do
				local object = self:resolve(other)
				if object then
					table.insert(extra, object)
				end
			end
			self.Guide:show(step.Key, target, {
				Title = step.Title,
				Note = step.Note,
				Sides = step.Sides,
				Extra = extra,
				Round = step.Round,
				-- Board prompt choices: keep the hand and label above the prompt card.
				Outside = if step.Target and step.Target.Kind == "Option" then self.Deps.Board.Prompt else nil,
			})
		end
	end
	self.Guide:update()
end

return Onboarding
