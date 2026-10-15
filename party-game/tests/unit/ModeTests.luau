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
