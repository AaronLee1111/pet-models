--[[
	Main (client entry point)
	Renders whatever state the server sends and forwards inputs. No game logic lives here:
	the client never decides who won, who has the potato, or when a round ends.
	It does own purely local presentation: this player's camera, UI and control bindings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("PartyShared"):WaitForChild("Net"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ActionBar = require(UI:WaitForChild("ActionBar"))
local Hud = require(UI:WaitForChild("Hud"))
local InstructionsCard = require(UI:WaitForChild("InstructionsCard"))
local PlayerChips = require(UI:WaitForChild("PlayerChips"))
local ResultsScreen = require(UI:WaitForChild("ResultsScreen"))
local SpectatorBar = require(UI:WaitForChild("SpectatorBar"))
local VoteScreen = require(UI:WaitForChild("VoteScreen"))

local player = Players.LocalPlayer
local myId = "player_" .. player.UserId
local stateRemote = Net.stateRemote()
local inputRemote = Net.inputRemote()

local function sendInput(payload)
	inputRemote:FireServer(payload)
end

local function sendAction(action: string)
	sendInput({ Kind = Net.Input.Action, Action = action })
end

-- Screens ---------------------------------------------------------------------------------

local screen = Theme.make("ScreenGui", {
	Name = "PartyUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10, -- draw the vote / results cards over the mobile thumbstick and jump button
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local hud = Hud.new(screen)
local voteScreen = VoteScreen.new(screen, function(choice)
	sendInput({ Kind = Net.Input.Vote, Choice = choice })
end)
local instructions = InstructionsCard.new(screen)
local results = ResultsScreen.new(screen)
local chips = PlayerChips.new(screen)
local spectatorBar
spectatorBar = SpectatorBar.new(screen, function(direction)
	CameraController.cycle(direction)
	spectatorBar:show(CameraController.getTargetName())
end)
Controls.setActionBar(ActionBar.new(screen))

-- The top/bottom HUD strips are sized in pixels for a desktop window. On a phone they would
-- cover almost half the screen, so shrink them (and their pixel offsets) with the viewport.
local HUD_STRIPS = { "Timer", "Status", "PlayerChips", "SpectatorBar", "Lobby" }
local HUD_DESIGN_HEIGHT = 720
local hudBasePositions = {}

local function fitHudToScreen()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local scale = math.clamp(camera.ViewportSize.Y / HUD_DESIGN_HEIGHT, 0.55, 1)
	for _, name in HUD_STRIPS do
		local strip = screen:FindFirstChild(name)
		if strip and strip:IsA("GuiObject") then
			local base = hudBasePositions[name] or strip.Position
			hudBasePositions[name] = base
			local uiScale = strip:FindFirstChildOfClass("UIScale") or Theme.make("UIScale", { Parent = strip })
			uiScale.Scale = scale
			strip.Position = UDim2.new(base.X.Scale, base.X.Offset * scale, base.Y.Scale, base.Y.Offset * scale)
		end
	end
end

fitHudToScreen()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHudToScreen)

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

-- Round presentation state -----------------------------------------------------------------

local inRound = false -- true from Instructions until Results/Lobby
local amParticipant = false

local function beginRound(message)
	if inRound then
		return
	end
	inRound = true
	amParticipant = isParticipant(message.Participants)
	CameraController.start(message.Minigame.Camera, message.ArenaOrigin)
	CameraController.setSpectating(not amParticipant)
end

local function endRound()
	inRound = false
	Controls.unbind()
	CameraController.stop()
	spectatorBar:hide()
	chips:hide()
end

local function refreshSpectator()
	if CameraController.isActive() and CameraController.isSpectating() then
		spectatorBar:show(CameraController.getTargetName())
	else
		spectatorBar:hide()
	end
end

local function onChips(list)
	if not inRound then
		return
	end
	chips:update(list, myId)
	CameraController.setTargets(list)
	for _, chip in list do
		if chip.Id == myId and chip.Eliminated and not CameraController.isSpectating() then
			-- Knocked out: lose the controls, switch to the spectator camera.
			Controls.unbind()
			CameraController.setSpectating(true)
			hud:showBanner("ELIMINATED", Theme.Colors.Hot, 1.2)
		end
	end
	refreshSpectator()
end

-- Phase handlers ------------------------------------------------------------------------------

local Phase = Net.Phase
local phaseHandlers = {}

phaseHandlers[Phase.Lobby] = function(message)
	hideOverlays()
	endRound()
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
	beginRound(message)
	if not amParticipant then
		hud:setStatus("👀 Spectating this round")
	end
	refreshSpectator()
end

phaseHandlers[Phase.Countdown] = function(message)
	hideOverlays()
	chips:show() -- not during Instructions: the strip would sit on top of the card
	hud:showBanner(tostring(message.Number), nil, 0.7)
end

phaseHandlers[Phase.Playing] = function(message)
	hideOverlays()
	beginRound(message) -- no-op normally; covers joining mid-round
	chips:show()
	hud:showBanner("GO!", Theme.Colors.Good, 0.8)
	hud:setTimer(message.EndsAt)
	if amParticipant and not CameraController.isSpectating() then
		Controls.bind(message.Minigame.Controls, sendAction)
	end
end

phaseHandlers[Phase.Finished] = function(_message)
	Controls.unbind()
	hud:setTimer(nil)
	hud:showBanner("FINISH!", Theme.Colors.Hot, 1.5)
end

phaseHandlers[Phase.Results] = function(message)
	hideOverlays()
	endRound() -- everyone is back in the lobby: normal camera + controls
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
	elseif message.Type == Net.Message.Chips then
		onChips(message.Chips)
	end
end)

RunService.RenderStepped:Connect(function()
	hud:update()
	voteScreen:update()
	instructions:update()
end)

-- Ask for the current state in case we joined mid-round.
sendInput({ Kind = Net.Input.Ready })
