--[[
	Multi-client board test (client half). Plays a board match on autopilot: the host picks
	the shortest match and starts, everyone rolls, answers every prompt with option 1, votes, and
	presses minigame actions now and then. Reports what it saw when the final standings show.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("PartyRemotes")
local input = remotes:WaitForChild("PartyInput")
local report = ReplicatedStorage:WaitForChild("MultiTestReport")
local me = "player_" .. Players.LocalPlayer.UserId

local seen = { Phases = {}, Turns = 0, Prompts = 0, Seated = false, OrderRolled = false, Final = nil, Minigames = {} }
local actions = {}
local sent = false

remotes.PartyState.OnClientEvent:Connect(function(message)
	if message.Type == "Phase" then
		seen.Phases[message.Phase] = (seen.Phases[message.Phase] or 0) + 1
		if message.Phase == "Lobby" and message.WaitingRoom and message.HostId == Players.LocalPlayer.UserId then
			input:FireServer({ Kind = "Setting", Key = "Mode", Value = "Board" })
			input:FireServer({ Kind = "Setting", Key = "Rounds", Value = message.Choices.Rounds[1] }) -- shortest offered
			task.delay(1, function()
				input:FireServer({ Kind = "StartMatch" })
			end)
		elseif message.Phase == "Vote" then
			input:FireServer({ Kind = "Vote", Choice = math.random(1, #message.Choices) })
		elseif message.Phase == "Playing" and message.Minigame then
			table.insert(seen.Minigames, message.Minigame.Name)
			actions = {}
			for _, action in message.Minigame.Controls.Actions do
				table.insert(actions, action.Action)
			end
		elseif message.Phase == "Standings" and message.Stage == "Final" and not sent then
			sent = true
			local placements = {}
			for _, row in message.Rows do
				table.insert(placements, ("%d.%s"):format(row.Placement, row.Name))
			end
			seen.Final = table.concat(placements, " ")
			local phases = {}
			for phase, n in seen.Phases do
				table.insert(phases, phase .. "x" .. n)
			end
			report:FireServer(("seated=%s orderRolled=%s turns=%d prompts=%d minigames=%s phases=%s final=%s"):format(
				tostring(seen.Seated), tostring(seen.OrderRolled), seen.Turns, seen.Prompts,
				table.concat(seen.Minigames, "+"), table.concat(phases, ","), seen.Final))
		end
	elseif message.Type == "BoardState" then
		for _, seat in message.Seats do
			if seat.Id == me then
				seen.Seated = true
			end
		end
		if message.Stage == "OrderRoll" and message.OrderPending and message.OrderPending[me] then
			seen.OrderRolled = true
			input:FireServer({ Kind = "Roll" })
		elseif message.Stage == "Roll" and message.TurnId == me then
			seen.Turns += 1
			input:FireServer({ Kind = "Roll" })
		end
	elseif message.Type == "Prompt" and message.PromptId then
		seen.Prompts += 1
		task.delay(0.3, function()
			input:FireServer({ Kind = "Choice", PromptId = message.PromptId, Index = 1 })
		end)
	end
end)

-- Press minigame actions now and then (not every frame: rate limits apply).
task.spawn(function()
	while true do
		task.wait(0.4)
		if #actions > 0 then
			input:FireServer({ Kind = "Action", Action = actions[math.random(1, #actions)] })
		end
	end
end)

input:FireServer({ Kind = "Ready" })
