--[[
	Unit tests for match modes and waiting-room settings. Run with RunAll (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.PartyServer
local Config = require(ReplicatedStorage.PartyShared.Config)
local MinigameMode = require(Server.MinigameMode)
local WaitingRoom = require(Server.WaitingRoom)

local tests = {}
local function test(name: string, fn)
	table.insert(tests, { Name = name, Fn = fn })
end

local function eq(actual, expected, what: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

test("waiting room shows board names, not ids", function()
	local names = WaitingRoom.boardNames()
	eq(names.Classic, "Sunny Loop", "Classic")
	eq(names.MagicalFestival, "Magical Festival Island", "MagicalFestival")
	for _, id in Config.Match.Boards do
		assert(type(names[id]) == "string" and names[id] ~= "", "every board has a name: " .. id)
	end
end)

-- The waiting-room card must fit every supported landscape screen with SHOP (header) and
-- START (fixed column) on screen. Screen heights / top-bar insets measured in Studio.
test("waiting-room card fits every landscape screen; SHOP and START stay on screen", function()
	local client = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local module = client and client:FindFirstChild("LobbyPanel", true)
	assert(module, "LobbyPanel module not mapped into this place")
	local LobbyPanel = require(module)
	-- Main scales the waiting room with the screen height, never below 0.85.
	local function scaleFor(height: number): number
		return math.max(math.clamp(height / 720, 0.55, 1), 0.85)
	end
	local profiles = {
		{ "iPhone 17 Pro landscape", 402, 58 },
		{ "small landscape phone", 320, 58 },
		{ "short Studio window", 616, 58 },
		{ "HD 1080", 1080, 58 },
	}
	for _, rows in { 4, 5, 7 } do
		for _, profile in profiles do
			local name, height, inset = profile[1], profile[2], profile[3]
			local scale = scaleFor(height)
			local card, natural = LobbyPanel.fitHeight(rows, height, inset, scale)
			local bottom = height - LobbyPanel.BOTTOM_MARGIN * scale
			local top = bottom - card * scale
			assert(top >= inset + LobbyPanel.TOP_MARGIN - 0.5, ("%s, %d rows: card top %.1f under the top bar"):format(name, rows, top))
			assert(bottom <= height, name .. ": card bottom off screen")
			-- SHOP is in the header; START fills the column under it (at least one row high).
			local startHeight = (card - LobbyPanel.PADDING * 2 - LobbyPanel.BODY_TOP) * scale
			assert(startHeight >= 44 - 0.5, ("%s: START only %.1f px tall"):format(name, startHeight))
			assert(LobbyPanel.HEADER * scale >= 44 - 0.5, name .. ": SHOP below 44 px")
			assert(LobbyPanel.ROW * scale >= 44 - 0.5, name .. ": setting rows below 44 px")
			if height >= 1000 and rows <= 5 then
				eq(card, natural, name .. ": everything shows without scrolling")
			end
		end
	end
	-- Width: full card on desktop; between the thumbstick and jump button on a phone
	-- (iPhone 17 Pro: 749 px wide, thumbstick ends at 103, jump starts at 654).
	eq(LobbyPanel.fitWidth(1918, 0, 1), LobbyPanel.WIDTH, "desktop: full width")
	local reserve = math.max(103, 749 - 654) + LobbyPanel.CONTROL_GAP
	local width = LobbyPanel.fitWidth(749, reserve, 0.85) * 0.85
	local left = (749 - width) / 2
	assert(left >= 103 + LobbyPanel.CONTROL_GAP - 0.5, ("card starts at %.1f, over the thumbstick"):format(left))
	assert(left + width <= 654 - LobbyPanel.CONTROL_GAP + 0.5, "card runs under the jump button")
	assert(width >= 480, ("card too narrow to read: %.1f px"):format(width))
end)

test("minigame mode ranks by coins, ties share a place", function()
	local coins = { a = 10, b = 25, c = 10, d = 3 }
	local participants = {}
	for _, id in { "a", "b", "c", "d" } do
		table.insert(participants, { Id = id, Name = id })
	end
	local rows = MinigameMode.rank(participants, {
		get = function(p)
			return coins[p.Id]
		end,
	})
	eq(rows[1].Participant.Id, "b", "1st")
	eq(rows[2].Placement, 2, "a placement")
	eq(rows[3].Placement, 2, "c shares 2nd")
	eq(rows[4].Placement, 4, "d is 4th")
end)

test("waiting room accepts only legal settings", function()
	local before = WaitingRoom.getSettings()
	eq(WaitingRoom.applySetting("Mode", "Minigames"), true, "minigame mode")
	eq(WaitingRoom.getSettings().Mode, "Minigames", "applied")
	eq(WaitingRoom.applySetting("Mode", "Adventure"), false, "unknown mode")
	eq(WaitingRoom.applySetting("Rounds", 999), false, "rounds not offered")
	eq(WaitingRoom.applySetting("Rounds", Config.Match.BoardRoundChoices[1]), true, "offered rounds")
	eq(WaitingRoom.applySetting("Board", "NotABoard"), false, "unknown board")
	eq(WaitingRoom.applySetting("Board", Config.Match.Boards[1]), true, "known board")
	eq(WaitingRoom.applySetting("Coins", 1000), false, "not a setting")
	eq(WaitingRoom.applySetting({}, "x"), false, "junk key")
	eq(WaitingRoom.applySetting("Difficulty", { "Hard" }), false, "junk value")
	for key, value in before do
		WaitingRoom.applySetting(key, value)
	end
	eq(WaitingRoom.getSettings().Mode, before.Mode, "restored")
end)

test("every board in the picker exists", function()
	for _, name in Config.Match.Boards do
		eq(Server.Board.Boards:FindFirstChild(name) ~= nil, true, name)
	end
	eq(table.find(Config.Match.Boards, Config.Match.Board) ~= nil, true, "default board is pickable")
	eq(table.find(Config.Match.Modes, Config.Match.Mode) ~= nil, true, "default mode is pickable")
end)

test("long display names are shortened with an ellipsis, punctuation kept", function()
	local Theme = require(game:GetService("StarterPlayer").StarterPlayerScripts.PartyClient.UI.Theme)
	eq(Theme.shortWords("WWWWWWWWWWWWWWWWWWWW left", 14), "WWWWWWWWWWWWW… left", "long name cut")
	eq(Theme.shortWords("Supercalifragilistic's Coin Shield", 14), "Supercalifrag…'s Coin Shield", "possessive kept")
	eq(Theme.shortWords("Catch-up: MMMMMMMMMMMMMMMMMMMM, Pip +5", 14), "Catch-up: MMMMMMMMMMMMM…, Pip +5", "comma kept")
	eq(Theme.shortWords("Main road\nCrown in 8", 14), "Main road\nCrown in 8", "short text and line breaks untouched")
	eq(Theme.shortWords("ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ", 5), "ÄÄÄÄ…", "counts characters, not bytes")
end)

return function()
	local passed, failed = 0, 0
	for _, case in tests do
		local success, err = pcall(case.Fn)
		if success then
			passed += 1
		else
			failed += 1
			warn(("[ModeTests] FAIL %s: %s"):format(case.Name, tostring(err)))
		end
	end
	print(("[ModeTests] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
