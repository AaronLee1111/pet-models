--[[
	Main (client entry point)
	Renders whatever state the server sends and forwards inputs. No game logic lives here:
	the client never decides who won, who has the potato, or when a round ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("PartyShared"):WaitForChild("Net"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Hud = require(UI:WaitForChild("Hud"))
local VoteScreen = require(UI:WaitForChild("VoteScreen"))
local InstructionsCard = require(UI:WaitForChild("InstructionsCard"))
local ResultsScreen = require(UI:WaitForChild("ResultsScreen"))

local player = Players.LocalPlayer
local myId = "player_" .. player.UserId
local stateRemote = Net.stateRemote()
local inputRemote = Net.inputRemote()

local function sendInput(payload)
	inputRemote:FireServer(payload)
end

-- Screens ---------------------------------------------------------------------------------

local screen = Theme.make("ScreenGui", {
	Name = "PartyUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local hud = Hud.new(screen)
local voteScreen = VoteScreen.new(screen, function(choice)
	sendInput({ Kind = Net.Input.Vote, Choice = choice })
end)
local instructions = InstructionsCard.new(screen)
local results = ResultsScreen.new(screen)

local function hideOverlays()
	voteScreen:hide()
	instructions:hide()
	results:hide()
end

local function isParticipant(participants): boolean
	for _, participant in participants or {} do
		if participant.Id == myId then
			return true
		end
	end
	return false
end

-- Phase handlers ------------------------------------------------------------------------------

local Phase = Net.Phase
local phaseHandlers = {}

phaseHandlers[Phase.Lobby] = function(message)
	hideOverlays()
	Controls.unbind()
	hud:setTimer(nil)
	hud:setStatus(nil)
	hud:setLobby(message.Text or "Lobby", message.EndsAt)
end

phaseHandlers[Phase.Vote] = function(message)
	hideOverlays()
	hud:setLobby(nil)
	voteScreen:show(message.Choices, message.EndsAt)
end

phaseHandlers[Phase.Instructions] = function(message)
	hideOverlays()
	hud:setLobby(nil)
	instructions:show(message.Minigame, message.Participants, message.EndsAt, myId)
	if not isParticipant(message.Participants) then
		hud:setStatus("👀 Spectating this round")
	end
end

phaseHandlers[Phase.Countdown] = function(message)
	hideOverlays()
	hud:showBanner(tostring(message.Number), nil, 0.7)
end

phaseHandlers[Phase.Playing] = function(message)
	hideOverlays()
	hud:showBanner("GO!", Theme.Colors.Good, 0.8)
	hud:setTimer(message.EndsAt)
	if isParticipant(message.Participants) then
		Controls.bind(message.Minigame.Controls, function(action)
			sendInput({ Kind = Net.Input.Action, Action = action })
		end)
	end
end

phaseHandlers[Phase.Finished] = function(_message)
	Controls.unbind()
	hud:setTimer(nil)
	hud:showBanner("FINISH!", Theme.Colors.Hot, 1.5)
end

phaseHandlers[Phase.Results] = function(message)
	hideOverlays()
	hud:setStatus(nil)
	results:show(message.Minigame, message.Results, myId)
end

-- Message routing ------------------------------------------------------------------------------

stateRemote.OnClientEvent:Connect(function(message)
	if type(message) ~= "table" then
		return
	end
	if message.Type == Net.Message.Phase then
		local handler = phaseHandlers[message.Phase]
		if handler then
			handler(message)
		end
	elseif message.Type == Net.Message.VoteUpdate then
		voteScreen:updateCounts(message.Counts, message.Voters)
	elseif message.Type == Net.Message.Status then
		hud:setStatus(message.Text)
	elseif message.Type == Net.Message.Toast then
		hud:toast(message.Text)
	end
end)

RunService.RenderStepped:Connect(function()
	hud:update()
	voteScreen:update()
	instructions:update()
end)

-- Ask for the current state in case we joined mid-round.
sendInput({ Kind = Net.Input.Ready })
