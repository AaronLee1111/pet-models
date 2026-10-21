--[[
	Four-client foundation regression (client half; test only). Plays every scenario on
	autopilot (the host applies the scenario's settings and starts it), checks this client's
	own screen and controls as it goes, and reports what it saw at the final standings.
	See FoundationTestServer for the scenarios and the cross-client comparison.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local remotes = RS:WaitForChild("PartyRemotes")
local input = remotes:WaitForChild("PartyInput")
local report = RS:WaitForChild("FoundationReport")
local scenarioValue = RS:WaitForChild("FoundationScenario")
local player = Players.LocalPlayer
local me = "player_" .. player.UserId

local BOARD_UI = { "BoardHeader", "BoardStandings", "BoardRoll", "BoardItems", "BoardPrompt", "BoardMap", "BoardMapPanel" }

local scenario = nil
local started = {}
local run = nil -- per-scenario record
local bank = nil
local lastState = nil
local actions = {}
local shopChecked = false

local function ui()
	local gui = player:FindFirstChild("PlayerGui")
	return gui and gui:FindFirstChild("PartyUI")
end

local function visible(name: string): boolean
	local root = ui()
	local item = root and root:FindFirstChild(name, true)
	return item ~= nil and item:IsA("GuiObject") and item.Visible
end

local function issue(text)
	if run then
		table.insert(run.Issues, text)
	end
end

local function fingerprint(state)
	if not state then
		return "none"
	end
	local seats = {}
	for _, seat in state.Seats do
		table.insert(seats, ("%s@%d/%d/%d"):format(seat.Id, seat.SpaceId, seat.Coins, seat.Collectibles))
	end
	table.sort(seats)
	local bridge = state.Bridge
	return ("%s|crown=%s|bridge=%s"):format(table.concat(seats, ","), tostring(state.CollectibleSpace),
		bridge and (tostring(bridge.Revision) .. ":" .. tostring(bridge.Alignment)) or "-")
end

-- What the MAP panel is built from on the festival board.
local function mapState(state)
	local bridge = state and state.Bridge
	if not bridge then
		return "-"
	end
	local docks = {}
	for _, dock in bridge.Docks or {} do
		table.insert(docks, ("%s=%s"):format(tostring(dock.SpaceId), tostring(dock.Open)))
	end
	table.sort(docks)
	return ("%s->%s rev%s crown%s dialRound%s next%s %s"):format(tostring(bridge.Alignment), tostring(bridge.NextAlignment),
		tostring(bridge.Revision), tostring(state.CollectibleSpace), tostring(bridge.DialReadyRound), tostring(bridge.NextRound),
		table.concat(docks, ","))
end

local function newRun(name)
	return {
		Scenario = name,
		Issues = {},
		Results = {},
		Teams = {},
		Duels = {},
		BridgeTrack = {},
		Turns = 0,
		TurnsWithControls = 0,
		ItemsUsed = 0,
		Prompts = 0,
		GapCrossings = 0,
		Rotations = 0,
		SawRider = false,
		Alignments = {},
		BankStart = nil, -- set when the match starts (after any shop purchase in the waiting room)
		LastRevision = 0,
		LastSpace = {},
		Seats = nil,
	}
end

local DOCK_END = { [1] = 33, [9] = 33, [17] = 36, [25] = 36 }

local function onBoardState(state)
	lastState = state
	if not run then
		return
	end
	if not run.Seats then
		local ids, mine = {}, 0
		for _, seat in state.Seats do
			table.insert(ids, seat.Id .. (if seat.IsBot then "(bot)" else ""))
			if seat.Id == me then
				mine += 1
			end
		end
		table.sort(ids)
		run.Seats = table.concat(ids, ",")
		if mine ~= 1 then
			issue(("my seat appears %d times"):format(mine))
		end
		if #state.Seats ~= 4 then
			issue(("%d seats"):format(#state.Seats))
		end
	end
	if state.Stage == "OrderRoll" and state.OrderPending and state.OrderPending[me] then
		task.delay(0.4, function()
			input:FireServer({ Kind = "Roll" })
		end)
	end
	local myTurn = state.TurnId == me
	if state.Stage == "Roll" then
		local key = tostring(state.Round) .. ":" .. tostring(state.TurnId)
		if myTurn and run.TurnKey ~= key then
			run.TurnKey = key
			run.Turns += 1
			task.spawn(function()
				task.wait(1.6) -- after the "start!" banner (~1.25 s), the turn menu is up
				if visible("BoardRoll") then
					run.TurnsWithControls += 1
				end
				-- Use an item on my first turn (Moon Dial on the festival, Double Dice on Sunny Loop).
				local mine
				for _, seat in state.Seats do
					if seat.Id == me then
						mine = seat
					end
				end
				if state.Round == 1 and mine and mine.Items and #mine.Items > 0 then
					input:FireServer({ Kind = "UseItem", Slot = 1 })
					run.ItemsUsed += 1
					task.wait(4)
				end
				input:FireServer({ Kind = "Roll" })
			end)
		elseif not myTurn then
			task.delay(1.6, function()
				if lastState == state and visible("BoardRoll") then
					issue("ROLL shown on someone else's turn")
				end
			end)
		end
	end
	-- Festival: bridge timeline, riders, and no hops across a closed dock.
	local bridge = state.Bridge
	if bridge then
		run.Alignments[bridge.Alignment] = true
		local open = {}
		for _, dock in bridge.Docks or {} do
			open[dock.SpaceId] = dock.Open
		end
		for _, seat in state.Seats do
			local from, to = run.LastSpace[seat.Id], seat.SpaceId
			if from and from ~= to and state.Stage == "Moving" then
				local dock = if DOCK_END[from] == to then from elseif DOCK_END[to] == from then to else nil
				if dock and not open[dock] then
					run.GapCrossings += 1
				end
			end
			run.LastSpace[seat.Id] = to
			if state.Stage == "Rotating" and to >= 33 then
				run.SawRider = true
			end
		end
		if bridge.Revision > run.LastRevision then
			table.insert(run.BridgeTrack, ("%d:%s:%s"):format(bridge.Revision, tostring(bridge.Alignment), tostring(state.CollectibleSpace)))
			run.Rotations += bridge.Revision - run.LastRevision
			run.LastRevision = bridge.Revision
		end
		if run.GapCrossings > 0 and not run.GapReported then
			run.GapReported = true
			issue("a rider crossed a closed dock")
		end
	end
end

local function checkMinigameScreen(message, phase)
	task.delay(0.6, function()
		for _, name in BOARD_UI do
			if visible(name) then
				issue(("board %s visible during %s of %s"):format(name, phase, message.Minigame and message.Minigame.Name or "?"))
			end
		end
		if phase ~= "Playing" then
			return
		end
		local active = false
		for _, participant in message.Participants or {} do
			if participant.Id == me then
				active = true
			end
		end
		local hasActions = #(message.Minigame.Controls.Actions or {}) > 0
		local controls = visible("ActionBar") or visible("ActionBarLeft")
		if active and hasActions and not controls then
			issue("no controls while playing " .. message.Minigame.Name)
		elseif not active and controls then
			issue("controls shown while watching " .. message.Minigame.Name)
		end
		if not active then
			local camera = workspace.CurrentCamera
			if not visible("SpectatorBar") or camera.CameraType ~= Enum.CameraType.Scriptable then
				issue("spectator view missing while watching " .. message.Minigame.Name)
			end
		end
	end)
end

local function finish(message)
	if not run or run.Sent then
		return
	end
	run.Sent = true
	task.wait(1.5) -- let the payout's inventory update land
	local rows, myBank = {}, nil
	for _, row in message.Rows do
		table.insert(rows, ("%d.%s/%s/%s/bank%s"):format(row.Placement, row.Id, tostring(row.Collectibles), tostring(row.Coins), tostring(row.BankCoins or 0)))
		if row.Id == me then
			myBank = row.BankCoins or 0
		end
	end
	local gained = (bank or 0) - (run.BankStart or 0)
	if myBank and gained ~= myBank then
		issue(("bank went up %d but the standings say %d"):format(gained, myBank))
	end
	if (run.BankIncreases or 0) > 1 then
		issue(("bank went up %d times after the match"):format(run.BankIncreases))
	end
	local alignments = {}
	for name in run.Alignments do
		table.insert(alignments, name)
	end
	table.sort(alignments)
	report:FireServer({
		Scenario = run.Scenario,
		Final = table.concat(rows, " "),
		FinalBoard = fingerprint(lastState),
		MapFinal = mapState(lastState),
		Results = table.concat(run.Results, " || "),
		Teams = table.concat(run.Teams, " || "),
		Duels = table.concat(run.Duels, " || "),
		BridgeTrack = table.concat(run.BridgeTrack, ","),
		Seats = run.Seats,
		Issues = run.Issues,
		Summary = ("turns %d (controls on %d) items %d prompts %d rotations %d riders %s alignments %s bank +%d shop %s"):format(
			run.Turns, run.TurnsWithControls, run.ItemsUsed, run.Prompts, run.Rotations, tostring(run.SawRider),
			table.concat(alignments, "/"), gained, tostring(run.Shop)),
	})
	if run.Turns > 0 and run.TurnsWithControls < run.Turns then
		-- (reported in Summary; a turn can end by timeout before the check)
	end
end

remotes.PartyState.OnClientEvent:Connect(function(message)
	if message.Type == "Inventory" then
		if run and run.FinalSeen and type(message.BankCoins) == "number" and bank and message.BankCoins > bank then
			run.BankIncreases = (run.BankIncreases or 0) + 1
		end
		bank = message.BankCoins
	elseif message.Type == "ShopResult" and run then
		run.Shop = ("%s:%s"):format(tostring(message.Ok), tostring(message.Code))
	elseif message.Type == "Phase" then
		local phase = message.Phase
		if run and run.BankStart == nil and not (phase == "Lobby" and message.WaitingRoom) then
			run.BankStart = bank or 0 -- the match has started
		end
		if phase == "Lobby" and message.WaitingRoom and scenario and not started[scenario.Name] then
			started[scenario.Name] = true
			run = newRun(scenario.Name)
			-- Shop check (Sunny Loop lobby): the button is there and a purchase goes through.
			if scenario.Name == "SunnyLoop" and not shopChecked then
				shopChecked = true
				if not visible("ShopButton") then
					issue("no Shop button in the waiting room")
				end
				input:FireServer({ Kind = "BuyCosmetic", ItemId = "trail_confetti" })
			end
			if message.HostId == player.UserId then
				task.spawn(function()
					task.wait(2)
					input:FireServer({ Kind = "Setting", Key = "Mode", Value = scenario.Mode })
					if scenario.Board then
						input:FireServer({ Kind = "Setting", Key = "Board", Value = scenario.Board })
					end
					input:FireServer({ Kind = "Setting", Key = "Rounds", Value = scenario.Rounds or message.Choices.Rounds[1] })
					task.wait(1)
					input:FireServer({ Kind = "StartMatch" })
				end)
			end
		elseif phase == "Instructions" then
			task.delay(math.max(0, (message.ReadyAt or 0) - workspace:GetServerTimeNow()) + 0.3, function()
				input:FireServer({ Kind = "TutorialReady" })
			end)
			if run then
				local teams = {}
				for _, participant in message.Participants or {} do
					table.insert(teams, ("%s=%s"):format(participant.Id, tostring(participant.Team)))
				end
				table.insert(run.Teams, message.Minigame.Name .. ":" .. table.concat(teams, ","))
				if message.Minigame.Layout == "Duel" then
					table.insert(run.Duels, message.Minigame.Name .. ":" .. table.concat(teams, ","))
				end
			end
			checkMinigameScreen(message, "Instructions")
		elseif phase == "Playing" and message.Minigame then
			actions = {}
			for _, action in message.Minigame.Controls.Actions do
				table.insert(actions, action.Action)
			end
			checkMinigameScreen(message, "Playing")
		elseif phase == "Results" and run then
			local rows = {}
			for _, row in message.Results do
				table.insert(rows, ("%d.%s+%d"):format(row.Placement, row.Id, row.Coins))
			end
			table.insert(run.Results, message.Minigame.Name .. ":" .. table.concat(rows, " "))
		elseif phase == "Standings" and message.Stage == "Final" and run then
			run.FinalSeen = true
			task.spawn(finish, message)
		end
		if phase ~= "Playing" then
			actions = {}
		end
	elseif message.Type == "BoardState" then
		onBoardState(message)
	elseif message.Type == "Prompt" and message.PromptId then
		if run then
			run.Prompts += 1
		end
		task.delay(0.4, function()
			input:FireServer({ Kind = "Choice", PromptId = message.PromptId, Index = 1 })
		end)
	end
end)

-- Minigame actions now and then (rate limits apply).
task.spawn(function()
	while true do
		task.wait(0.45)
		if #actions > 0 then
			input:FireServer({ Kind = "Action", Action = actions[math.random(1, #actions)] })
		end
	end
end)

local function readScenario()
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, scenarioValue.Value)
	scenario = if ok and type(decoded) == "table" then decoded else nil
end
scenarioValue.Changed:Connect(function()
	readScenario()
	-- Re-ask for the lobby so the host applies the new scenario straight away.
	input:FireServer({ Kind = "Ready" })
end)
readScenario()
input:FireServer({ Kind = "Ready" })
