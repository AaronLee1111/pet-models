--[[
	Unit tests for the guided first actions: profile flags (migration, saving, bots), the
	server's Tutorial flags, the client's step rules (Onboarding.decide), the pointer
	(GuidePointer), instruction-card control text and the local YOU marker.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Server = ServerScriptService.PartyServer
local Client = StarterPlayer.StarterPlayerScripts.PartyClient
local Config = require(ReplicatedStorage.PartyShared.Config)
local MemoryBackend = require(Server.Profiles.MemoryBackend)
local ProfileStore = require(Server.Profiles.ProfileStore)
local Tutorial = require(Server.Tutorial)

local tests = {}
local function test(name: string, fn)
	table.insert(tests, { Name = name, Fn = fn })
end

local function eq(actual, expected, what: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function ok(condition, what: string)
	if not condition then
		error(what, 2)
	end
end

-- Stand-in players (edit mode has no real Player objects) -------------------------------------

local nextUserId = 900
local function fakePlayer()
	nextUserId += 1
	return { IsFakePlayer = true, UserId = nextUserId, Parent = workspace, Name = "Tester" .. nextUserId }
end
local function isFake(value): boolean
	return type(value) == "table" and value.IsFakePlayer == true
end

-- Tutorial wired to a real ProfileStore on a memory backend; records what it sends.
local function tutorialWith(store)
	local sent = {}
	Tutorial.configure(function(player)
		return store and store:get("player_" .. player.UserId)
	end, function(player, message)
		table.insert(sent, { Player = player, Message = message })
	end, isFake)
	return sent
end

local function restoreTutorial()
	Tutorial.configure(function()
		return nil
	end, nil, nil)
end

-- Profiles -----------------------------------------------------------------------------------

test("tutorial profile: new profiles get version 2 and no flags set", function()
	local profile = ProfileStore.new(MemoryBackend.new()):load("player_1")
	eq(profile.Version, 2, "version")
	eq(type(profile.Tutorial), "table", "tutorial table")
	eq(next(profile.Tutorial), nil, "no flags")
end)

test("tutorial profile: a version-1 save keeps coins, cosmetics and equips, gains empty flags", function()
	local backend = MemoryBackend.new()
	backend.Data.player_5 = {
		Version = 1,
		Coins = 260,
		Owned = { hat_party = true, trail_rainbow = true },
		Equipped = { Hat = "hat_party", Trail = "trail_rainbow" },
	}
	local profile = ProfileStore.new(backend):load("player_5")
	eq(profile.Version, 2, "migrated version")
	eq(profile.Coins, 260, "bank coins kept")
	eq(profile.Owned.hat_party, true, "hat kept")
	eq(profile.Owned.trail_rainbow, true, "trail kept")
	eq(profile.Equipped.Hat, "hat_party", "hat still worn")
	eq(profile.Equipped.Trail, "trail_rainbow", "trail still worn")
	eq(next(profile.Tutorial), nil, "no flags yet")
end)

test("tutorial profile: known flags load, junk is dropped", function()
	local backend = MemoryBackend.new()
	backend.Data.player_6 = {
		Version = 2,
		Coins = 3,
		Owned = {},
		Equipped = {},
		Tutorial = { StartedMatch = true, ChoseFork = "yes", Bogus = true, [4] = true, RolledForOrder = true },
	}
	local profile = ProfileStore.new(backend):load("player_6")
	eq(profile.Tutorial.StartedMatch, true, "kept")
	eq(profile.Tutorial.RolledForOrder, true, "kept")
	eq(profile.Tutorial.ChoseFork, nil, "non-true dropped")
	eq(profile.Tutorial.Bogus, nil, "unknown flag dropped")
	eq(profile.Tutorial[4], nil, "non-string dropped")
	eq(#Config.Tutorial.Flags, 7, "seven flags")
end)

test("tutorial flags: saved in the profile and still set after leaving and rejoining", function()
	local backend = MemoryBackend.new()
	local store = ProfileStore.new(backend)
	local player = fakePlayer()
	local key = "player_" .. player.UserId
	store:load(key)
	local sent = tutorialWith(store)
	eq(Tutorial.complete(player, "RolledForOrder"), true, "newly set")
	eq(Tutorial.complete(player, "RolledForOrder"), false, "second time is a no-op")
	eq(#sent, 1, "client told once")
	eq(sent[1].Message.Flags.RolledForOrder, true, "flag sent")
	store:release(key)
	local again = store:load(key)
	eq(again.Tutorial.RolledForOrder, true, "saved flag")
	eq(again.Tutorial.ChoseFork, nil, "others still unset")
	eq(again.Coins, 0, "nothing else changed")
	restoreTutorial()
end)

test("tutorial flags: bots and bot-held seats never get flags", function()
	local store = ProfileStore.new(MemoryBackend.new())
	local sent = tutorialWith(store)
	eq(Tutorial.complete({ IsBot = true, Name = "Pip" }, "RolledBoardTurn"), false, "bot")
	eq(Tutorial.complete({ IsBot = true, Player = fakePlayer() }, "RolledBoardTurn"), false, "bot flagged participant")
	eq(Tutorial.complete(nil, "RolledBoardTurn"), false, "nobody")
	eq(#sent, 0, "nothing sent")
	local player = fakePlayer()
	store:load("player_" .. player.UserId)
	eq(Tutorial.complete({ IsBot = false, Player = player }, "NotAFlag"), false, "unknown flag refused")
	eq(next(store:get("player_" .. player.UserId).Tutorial), nil, "profile untouched")
	restoreTutorial()
end)

test("tutorial flags: without a profile they last for the session, then move into the profile", function()
	local store = ProfileStore.new(MemoryBackend.new())
	tutorialWith(store)
	local player = fakePlayer()
	eq(Tutorial.complete(player, "StartedMatch"), true, "set before the profile loaded")
	eq(Tutorial.flags(player).StartedMatch, true, "remembered this session")
	store:load("player_" .. player.UserId)
	eq(Tutorial.flags(player).StartedMatch, true, "carried into the profile")
	eq(store:get("player_" .. player.UserId).Tutorial.StartedMatch, true, "in the profile table")
	Tutorial.reset(player)
	eq(next(Tutorial.flags(player)), nil, "dev reset clears it")
	restoreTutorial()
end)

test("tutorial flags: refused inputs set nothing (waiting room closed, no board match)", function()
	local store = ProfileStore.new(MemoryBackend.new())
	tutorialWith(store)
	local player = fakePlayer()
	store:load("player_" .. player.UserId)
	local WaitingRoom = require(Server.WaitingRoom)
	WaitingRoom.handleInput(player, { Kind = "StartMatch" }) -- not open, not the host
	local BoardGame = require(Server.Board.BoardGame)
	BoardGame.handleInput(player, { Kind = "Roll" }) -- no match running
	BoardGame.handleInput(player, { Kind = "UseItem", Slot = 1 })
	BoardGame.handleInput(player, { Kind = "Choice", PromptId = 1, Index = 1 })
	eq(next(Tutorial.flags(player)), nil, "no flag from a refused input")
	restoreTutorial()
end)

-- Step rules (Onboarding.decide) --------------------------------------------------------------

local Onboarding = require(Client.Onboarding)

local function context(overrides)
	local base = { Known = true, Flags = {}, Mode = "Touch", Modal = false }
	for key, value in overrides do
		base[key] = value
	end
	return base
end

local function all(flags)
	local set = {}
	for _, flag in flags do
		set[flag] = true
	end
	return set
end

test("onboarding: the host gets the START pointer, a non-host never does", function()
	local step = Onboarding.decide(context({ Lobby = { StartVisible = true } }))
	eq(step.Key, "StartedMatch", "host step")
	eq(step.Title, "TAP HERE TO START", "touch wording")
	eq(Onboarding.decide(context({ Lobby = { StartVisible = true }, Mode = "Mouse" })).Title, "CLICK HERE TO START", "mouse wording")
	eq(Onboarding.decide(context({ Lobby = { StartVisible = false } })), nil, "non-host: START isn't on screen")
	eq(Onboarding.decide(context({ Lobby = { StartVisible = true }, Flags = all({ "StartedMatch" }) })), nil, "done once")
	eq(Onboarding.decide(context({ Lobby = { StartVisible = true }, Known = false })), nil, "flags not loaded yet")
end)

test("onboarding: turn-order roll, then normal roll, each explained once", function()
	local order = Onboarding.decide(context({ Board = { OrderRoll = true, Roll = false } }))
	eq(order.Key, "RolledForOrder", "order roll step")
	eq(order.Note, "Roll to decide turn order.", "order note")
	eq(order.Target.Kind, "Roll", "points at ROLL")
	local roll = Onboarding.decide(context({ Board = { Roll = true }, Flags = all({ "RolledForOrder" }) }))
	eq(roll.Key, "RolledBoardTurn", "turn roll step")
	eq(roll.Note, "Roll to move.", "turn note")
	eq(Onboarding.decide(context({ Board = { Roll = true }, Flags = all({ "RolledBoardTurn" }) })), nil, "done")
	eq(Onboarding.decide(context({ Board = { Roll = false } })), nil, "not my turn: nothing")
	ok(string.find(Onboarding.decide(context({ Board = { Roll = true }, Mode = "Mouse" })).Title, "SPACE") ~= nil, "desktop shows the key")
	eq(Onboarding.decide(context({ Board = { Roll = true }, Mode = "Gamepad" })).Title, "PRESS A", "gamepad shows the button")
end)

test("onboarding: item guidance explains the item and leaves ROLL as the way out", function()
	local items = { { Name = "Coin Shield", Description = "Blocks the next coin loss, then breaks" } }
	local step = Onboarding.decide(context({ Board = { Roll = true, Items = items } }))
	eq(step.Key, "SawItem", "item step first")
	eq(step.Target.Kind, "Item", "points at the item")
	ok(string.find(step.Note, "Coin Shield: Blocks the next coin loss") ~= nil, "says what it does")
	ok(string.find(step.Note, "ROLL to roll without it") ~= nil, "roll-without path")
	-- Rolling without the item finishes the step (and the roll step) on the spot.
	local cleared = {}
	local controller = Onboarding.new({
		Guide = { clear = function(_, key) table.insert(cleared, key) end },
		Board = { State = { Stage = "Roll" }, ItemBar = { Visible = true } },
	})
	controller:setFlags({ RolledForOrder = true })
	controller.Step = step
	controller:noteInput({ Kind = "Roll" })
	eq(controller:isDone("SawItem"), true, "rolled without it: item step done")
	eq(controller:isDone("RolledBoardTurn"), true, "roll step done too")
	eq(cleared[1], "SawItem", "pointer removed at once")
	eq(Onboarding.decide(context({ Board = { Roll = true, Items = items }, Flags = controller:flags() })), nil, "nothing left")
end)

test("onboarding: a fork rings every route and suggests the closest to the Crown", function()
	local routes = { { SpaceId = 4, CrownDistance = 9 }, { SpaceId = 20, CrownDistance = 3 }, { SpaceId = 30 } }
	local step = Onboarding.decide(context({ Board = { Prompt = { Kind = "Path", Routes = routes, Count = 3 } } }))
	eq(step.Key, "ChoseFork", "fork step")
	eq(step.Target.Index, 2, "points at the closest route")
	eq(#step.Extra, 2, "the other routes get rings")
	ok(string.find(step.Note, "Any path is fine") ~= nil, "a suggestion, not an order")
	eq(Onboarding.recommendedRoute({ {}, {} }), nil, "no distances: no suggestion")
	eq(Onboarding.decide(context({ Board = { Prompt = { Kind = "Path", Routes = routes, Count = 3 } }, Flags = all({ "ChoseFork" }) })), nil, "done")
end)

test("onboarding: a Crown offer points at BUY only when you can afford it", function()
	local prompt = { Kind = "Collectible", Price = 20, Count = 2 }
	eq(Onboarding.decide(context({ Board = { Prompt = prompt, Coins = 12 } })), nil, "can't afford: no pointer")
	local step = Onboarding.decide(context({ Board = { Prompt = prompt, Coins = 20 } }))
	eq(step.Key, "SawCrownPurchase", "affordable")
	eq(step.Target.Index, 1, "BUY")
	eq(step.Note, "Crowns win the match. Coins break ties.", "explains Crowns")
	eq(Onboarding.decide(context({ Board = { Prompt = { Kind = "Collectible", Count = 2 }, Coins = 99 } })), nil, "unknown price: no pointer")
end)

test("onboarding: minigame action uses the real label; spectators and knocked-out players get nothing", function()
	local mash = { { Action = "Mash", Label = "MASH!", Key = "Space", Gamepad = "ButtonA" } }
	local playing = { Playing = true, Participant = true, Spectating = false, Bound = true, Actions = mash, Move = false }
	eq(Onboarding.decide(context({ Minigame = playing })).Title, "TAP TO MASH", "touch")
	eq(Onboarding.decide(context({ Minigame = playing, Mode = "Mouse" })).Title, "PRESS SPACE TO MASH", "desktop")
	eq(Onboarding.decide(context({ Minigame = playing, Mode = "Gamepad" })).Title, "PRESS A TO MASH", "gamepad")
	local watching = table.clone(playing)
	watching.Participant = false
	eq(Onboarding.decide(context({ Minigame = watching })), nil, "spectator")
	local out = table.clone(playing)
	out.Spectating = true
	out.Bound = false
	eq(Onboarding.decide(context({ Minigame = out })), nil, "knocked out")
	local turns = table.clone(playing)
	turns.Actions = { { Action = "Left", Label = "LEFT", Key = "A", Side = "Left" }, { Action = "Right", Label = "RIGHT", Key = "D" } }
	local pair = Onboarding.decide(context({ Minigame = turns }))
	eq(pair.Title, "TAP LEFT / RIGHT", "pair named together")
	eq(#pair.Extra, 1, "both buttons ringed")
	local walk = { Playing = true, Participant = true, Bound = true, Actions = {}, Move = true, Jump = true, MoveHintDue = true }
	eq(Onboarding.decide(context({ Minigame = walk })).Target.Kind, "Thumbstick", "touch: thumbstick")
	eq(Onboarding.decide(context({ Minigame = walk, Mode = "Mouse" })).Target, nil, "desktop: keys label only")
	walk.MoveHintDue = false
	eq(Onboarding.decide(context({ Minigame = walk })), nil, "movement hint is brief")
end)

test("onboarding: only one step at a time, and none while a card is up or after the phase moves on", function()
	local busy = context({
		Lobby = { StartVisible = true },
		Board = { OrderRoll = true },
		Minigame = { Playing = true, Participant = true, Bound = true, Actions = { { Action = "Go", Label = "GO" } } },
	})
	eq(Onboarding.decide(busy).Key, "StartedMatch", "a single step comes back")
	busy.Modal = true
	eq(Onboarding.decide(busy), nil, "card up: nothing")
	eq(Onboarding.decide(context({})), nil, "phase changed, nothing on screen: nothing")
end)

-- Pointer ------------------------------------------------------------------------------------

local GuidePointer = require(Client.UI.GuidePointer)

local function testScreen()
	local folder = Instance.new("Folder")
	folder.Name = "GuideTest"
	local screen = Instance.new("ScreenGui")
	screen.Parent = folder
	local function button(name)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(100, 60)
		b.Parent = screen
		return b
	end
	return folder, button("A"), button("B")
end

local function countRings(guide): number
	local count = 0
	for _, child in guide.Root:GetChildren() do
		if string.find(child.Name, "Ring") then
			count += 1
		end
	end
	return count
end

test("pointer: one at a time; repeating the same request doesn't add another", function()
	local folder, a, b = testScreen()
	local guide = GuidePointer.new(folder)
	eq(guide:show("RolledBoardTurn", a, { Title = "TAP HERE" }), true, "first show")
	for _ = 1, 5 do
		eq(guide:show("RolledBoardTurn", a, { Title = "TAP HERE" }), false, "duplicate ignored")
	end
	eq(countRings(guide), 1, "one ring")
	eq(#guide.Root:GetChildren(), 3, "ring, hand, bubble only")
	guide:show("SawItem", b, { Title = "TAP HERE TO USE IT" })
	eq(guide:isShowing(), "SawItem", "replaced, not added")
	eq(guide.Target, b, "new target")
	eq(countRings(guide), 1, "still one ring")
	guide:show("ChoseFork", a, { Title = "TAP A PATH", Extra = { b } })
	eq(countRings(guide), 2, "main ring + one extra")
	guide:show("ChoseFork", a, { Title = "TAP A PATH", Extra = { b } })
	eq(countRings(guide), 2, "extras not duplicated either")
	guide:destroy()
	folder:Destroy()
end)

test("pointer: never takes input and cleans up when the target goes", function()
	local folder, a = testScreen()
	local guide = GuidePointer.new(folder)
	guide:show("StartedMatch", a, { Title = "TAP HERE TO START" })
	for _, object in guide.Gui:GetDescendants() do
		if object:IsA("GuiObject") then
			ok(not object:IsA("GuiButton"), "no buttons in the guide")
			ok(object.Active == false, object:GetFullName() .. " is Active")
		end
	end
	a.Visible = false
	guide:update()
	eq(guide.Bubble.Visible, false, "hidden while the target is hidden")
	a:Destroy()
	guide:update()
	eq(guide:isShowing(), nil, "cleared when the target is destroyed")
	guide:show("RolledBoardTurn", Instance.new("TextButton"), {})
	guide:clear("SomethingElse")
	eq(guide:isShowing(), "RolledBoardTurn", "clear(key) only clears its own step")
	guide:clear()
	eq(guide:isShowing(), nil, "clear()")
	guide:destroy()
	folder:Destroy()
end)

-- Instruction card text -------------------------------------------------------------------------

test("instructions: touch shows the action without keyboard hints; desktop and gamepad show the input", function()
	local InstructionsCard = require(Client.UI.InstructionsCard)
	local mashDash = { Move = false, Jump = false, Actions = { { Action = "Mash", Label = "MASH!", Key = "Space", Gamepad = "ButtonA" } } }
	local touch = InstructionsCard.controlsText(mashDash, "Touch")
	ok(string.find(touch, "[", 1, true) == nil, "no [key] on touch: " .. touch)
	ok(string.find(touch, "Space") == nil and string.find(touch, "SPACE") == nil, "no key name on touch")
	ok(string.find(touch, "MASH!") ~= nil, "label shown on touch")
	ok(string.find(InstructionsCard.controlsText(mashDash, "Mouse"), "[SPACE] MASH!", 1, true) ~= nil, "desktop key")
	ok(string.find(InstructionsCard.controlsText(mashDash, "Gamepad"), "[A] MASH!", 1, true) ~= nil, "gamepad button")
end)

-- YOU marker --------------------------------------------------------------------------------------

local YouMarker = require(Client.UI.YouMarker)

local function character(name: string)
	local model = Instance.new("Model")
	model.Name = name
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.Size = Vector3.new(1, 1, 1)
	head.Position = Vector3.new(0, 10, 0)
	head.Parent = model
	model.Parent = Workspace
	return model
end

test("YOU marker: only while you're an active participant", function()
	eq(YouMarker.shouldShow({ Phase = "Board", OnBoard = true, Seated = true }), true, "seated on the board")
	eq(YouMarker.shouldShow({ Phase = "Board", OnBoard = true, Seated = false }), false, "watching the board")
	eq(YouMarker.shouldShow({ Phase = "Lobby" }), false, "waiting room")
	eq(YouMarker.shouldShow({ Phase = "Playing", InRound = true, Participant = true }), true, "playing")
	eq(YouMarker.shouldShow({ Phase = "Playing", InRound = true, Participant = false, Spectating = true }), false, "spectator")
	eq(YouMarker.shouldShow({ Phase = "Playing", InRound = true, Participant = true, Spectating = true }), false, "knocked out")
	eq(YouMarker.shouldShow({ Phase = "Instructions", InRound = true, Participant = true, CardOpen = true }), false, "instructions card")
	eq(YouMarker.shouldShow({ Phase = "Board", OnBoard = true, Seated = true, CardOpen = true }), false, "any card")
	eq(YouMarker.shouldShow({ Phase = "Standings", OnBoard = false, Seated = true }), false, "final standings")
end)

test("YOU marker: local only, follows a replaced character", function()
	local holder = Instance.new("Folder") -- stands in for the local PlayerGui
	local current = character("First")
	local marker = YouMarker.new(function()
		return current
	end, holder)
	marker:setActive(true)
	marker:update()
	eq(marker.Gui.Adornee, current.Head, "on my head")
	eq(marker.Gui.Enabled, true, "showing")
	eq(marker.Gui.Parent, holder, "lives in my own gui, not in the world")
	eq(current:FindFirstChildWhichIsA("BillboardGui", true), nil, "nothing added to the character")
	local old = current
	current = character("Second") -- respawn / replaced body
	old:Destroy()
	marker:update()
	eq(marker.Gui.Adornee, current.Head, "re-attached to the new character")
	current:Destroy()
	marker:update()
	eq(marker.Gui.Enabled, false, "no character: hidden")
	marker:setActive(false)
	eq(marker.Gui.Enabled, false, "inactive")
	local near = YouMarker.pixelHeight(5, 400, 70)
	local far = YouMarker.pixelHeight(500, 400, 70)
	ok(near <= 40 and far >= 26, "size stays readable at any distance")
	marker:destroy()
	holder:Destroy()
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[OnboardingTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	restoreTutorial()
	print(("[OnboardingTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
