-- Client half of the seat-reclaim harness: plays its turns, then reports what it saw.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local remotes = RS:WaitForChild("PartyRemotes")
local input = remotes:WaitForChild("PartyInput")
local report = RS:WaitForChild("ReclaimTestReport")
local me = "player_" .. Players.LocalPlayer.UserId

local seen = { Welcome = 0, AfterMinigameNotice = false, Returned = false, Toasts = {}, Final = "", Rows = 0,
	FinalRowsForMe = 0, Fingerprint = "none", ResyncLayouts = 0 }
local lastState = nil
local configured, sent, turnKey = false, false, nil

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

local function sendLater(payload)
	task.delay(0.2, function()
		input:FireServer(payload)
	end)
end

remotes.PartyState.OnClientEvent:Connect(function(m)
	if m.Type == "Toast" then
		if m.Text:find("Welcome back") then
			seen.Welcome += 1
			seen.Returned = true
			input:FireServer({ Kind = "Ready" }) -- resync like a reconnecting client
		elseif m.Text:find("Rejoining your seat after this minigame") then
			seen.AfterMinigameNotice = true
		end
		if m.Text:find("seat") then
			table.insert(seen.Toasts, m.Text)
		end
	elseif m.Type == "BoardLayout" then
		if seen.Returned then
			seen.ResyncLayouts += 1
		end
	elseif m.Type == "Phase" then
		if m.Phase == "Lobby" and m.WaitingRoom and m.HostId == Players.LocalPlayer.UserId and not configured then
			configured = true
			task.spawn(function()
				while #Players:GetPlayers() < 2 do -- both clients must be seated
					task.wait(0.5)
				end
				input:FireServer({ Kind = "Setting", Key = "Board", Value = "MagicalFestival" })
				task.wait(0.3)
				input:FireServer({ Kind = "Setting", Key = "Rounds", Value = 3 })
				task.wait(0.3)
				input:FireServer({ Kind = "StartMatch" })
			end)
		elseif m.Phase == "Vote" then
			sendLater({ Kind = "Vote", Choice = 1 })
		elseif m.Phase == "Standings" and m.Stage == "Final" and not sent then
			sent = true
			local rows = {}
			for _, row in m.Rows do
				table.insert(rows, ("%d.%s/%d/%d"):format(row.Placement, row.Id, row.Collectibles, row.Coins))
				if row.Id == me then
					seen.FinalRowsForMe += 1
				end
			end
			seen.Rows = #m.Rows
			seen.Final = table.concat(rows, " ")
			seen.Fingerprint = fingerprint(lastState)
			report:FireServer(seen)
		end
	elseif m.Type == "BoardState" then
		lastState = m
		if m.Stage == "OrderRoll" and m.OrderPending and m.OrderPending[me] then
			sendLater({ Kind = "Roll" })
		end
		if m.Stage == "Roll" and m.TurnId == me then
			local key = tostring(m.Round) .. ":" .. me
			if turnKey ~= key then
				turnKey = key
				sendLater({ Kind = "Roll" })
			end
		end
	elseif m.Type == "Prompt" and m.PromptId then
		sendLater({ Kind = "Choice", PromptId = m.PromptId, Index = 1 })
	end
end)
input:FireServer({ Kind = "Ready" })
