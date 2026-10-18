--[[
	Main (client entry point)
	Renders whatever state the server sends and forwards inputs. No game logic lives here:
	the client never decides who won, who has the potato, or when a round ends.
	It does own purely local presentation: this player's camera, UI and control bindings.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("PartyShared"):WaitForChild("Net"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local Onboarding = require(script.Parent:WaitForChild("Onboarding"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ActionBar = require(UI:WaitForChild("ActionBar"))
local BoardView = require(UI:WaitForChild("BoardView"))
local GuidePointer = require(UI:WaitForChild("GuidePointer"))
local Hud = require(UI:WaitForChild("Hud"))
local InstructionsCard = require(UI:WaitForChild("InstructionsCard"))
local LobbyPanel = require(UI:WaitForChild("LobbyPanel"))
local PlayerChips = require(UI:WaitForChild("PlayerChips"))
local ProgressBar = require(UI:WaitForChild("ProgressBar"))
local ResultsScreen = require(UI:WaitForChild("ResultsScreen"))
local ShopScreen = require(UI:WaitForChild("ShopScreen"))
local SpectatorBar = require(UI:WaitForChild("SpectatorBar"))
local StandingsScreen = require(UI:WaitForChild("StandingsScreen"))
local VoteScreen = require(UI:WaitForChild("VoteScreen"))
local YouMarker = require(UI:WaitForChild("YouMarker"))

local player = Players.LocalPlayer
local myId = "player_" .. player.UserId
local stateRemote = Net.stateRemote()
local inputRemote = Net.inputRemote()

local onboarding -- guided first actions (made once the screens exist, below)

local function sendInput(payload)
	if onboarding then
		onboarding:noteInput(payload) -- the step this answers is done: drop the pointer now
	end
	inputRemote:FireServer(payload)
end

-- Some minigames run their own client code for the round (Info.ClientModule), e.g. Ice Dash
-- simulates your racer locally. Those modules live in the Minigames folder next to this script.
local minigameClients = script.Parent:FindFirstChild("Minigames")
local activeMinigameClient = nil

local function stopMinigameClient()
	if activeMinigameClient then
		local client = activeMinigameClient
		activeMinigameClient = nil
		client.stop()
	end
end

local function startMinigameClient(name: string?)
	stopMinigameClient()
	local module = name and minigameClients and minigameClients:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, client = pcall(require, module)
		if ok and type(client) == "table" then
			activeMinigameClient = client
			client.start()
		else
			warn("[PartyClient] Could not load minigame client " .. tostring(name) .. ": " .. tostring(client))
		end
	end
end

local function sendAction(action: string)
	-- The minigame's client code gets first go; if it handles the action, the server needn't hear.
	if activeMinigameClient and activeMinigameClient.onAction and activeMinigameClient.onAction(action) then
		-- Sent by the minigame's own code; tell the server only while the tutorial still needs it.
		if onboarding and not onboarding:isDone("UsedMinigameAction") then
			sendInput({ Kind = Net.Input.ActionUsed, Action = action })
		end
		return
	end
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
local progressBar = ProgressBar.new(screen)
local spectatorBar
spectatorBar = SpectatorBar.new(screen, function(direction)
	CameraController.cycle(direction)
	spectatorBar:show(CameraController.getTargetName())
end)
Controls.setActionBar(ActionBar.new(screen))
local boardView = BoardView.new(screen, sendInput)
local lobbyPanel = LobbyPanel.new(screen, sendInput)
local shopScreen = ShopScreen.new(screen, sendInput)
lobbyPanel.OnShop = function()
	shopScreen:toggle()
end

local standings = StandingsScreen.new(screen)

-- Guided first actions: one bouncing pointer at a time, only for this player.
local playerGui = player:WaitForChild("PlayerGui")
onboarding = Onboarding.new({
	Guide = GuidePointer.new(playerGui),
	Lobby = lobbyPanel,
	Board = boardView,
	Shop = shopScreen,
	Screen = screen,
	PlayerGui = playerGui,
	Modals = { voteScreen.Root, instructions.Root, results.Root, standings.Root },
})

-- "YOU" over your own character while you're playing (only this client sees it).
local youMarker = YouMarker.new(function()
	return player.Character
end, playerGui)

-- The top/bottom HUD strips are sized in pixels for a desktop window. On a phone they would
-- cover almost half the screen, so shrink them (and their pixel offsets) with the viewport.
local HUD_STRIPS = {
	"Timer",
	"Status",
	"PlayerChips",
	"ProgressBar",
	"SpectatorBar",
	"Lobby",
	"BoardHeader",
	"BoardStandings",
	"BoardRoll",
	"BoardPrompt",
	"BoardItems",
	"BoardMap",
	"BoardMapPanel",
	"WaitingRoom",
	"CosmeticShop",
}
local HUD_DESIGN_HEIGHT = 720
-- Panels full of buttons would shrink below a tappable size; they don't go smaller than this.
local HUD_MIN_SCALE = { CosmeticShop = 0.85, WaitingRoom = 0.85, BoardPrompt = 0.75, BoardMap = 0.85, BoardMapPanel = 0.75 }
local hudBasePositions = {}
-- Board strips pinned to the top edge: however small the phone scale makes their offset, they
-- stay below Roblox's top bar (PartyUI ignores the inset, so the bar is part of our space).
local CLEAR_TOP_BAR = { BoardHeader = true, BoardStandings = true, BoardMapPanel = true }
local TOP_BAR_GAP = 6

local function fitHudToScreen()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local baseScale = math.clamp(camera.ViewportSize.Y / HUD_DESIGN_HEIGHT, 0.55, 1)
	for _, name in HUD_STRIPS do
		local strip = screen:FindFirstChild(name)
		local scale = math.max(baseScale, HUD_MIN_SCALE[name] or 0)
		if strip and strip:IsA("GuiObject") then
			local base = hudBasePositions[name] or strip.Position
			hudBasePositions[name] = base
			local uiScale = strip:FindFirstChildOfClass("UIScale") or Theme.make("UIScale", { Parent = strip })
			uiScale.Scale = scale
			strip:SetAttribute("HudScale", scale) -- Theme.pop animates back to this, not to 1
			local y = base.Y.Offset * scale
			if CLEAR_TOP_BAR[name] and base.Y.Scale == 0 then
				y = math.max(y, GuiService:GetGuiInset().Y + TOP_BAR_GAP)
			end
			strip.Position = UDim2.new(base.X.Scale, base.X.Offset * scale, base.Y.Scale, y)
		end
	end
end

fitHudToScreen()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHudToScreen)
-- The top bar's size can arrive after this script starts.
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitHudToScreen)
end)

-- While a full-screen card (vote, instructions, results) is up, the mobile thumbstick and
-- jump button are switched off entirely, so they can never sit on top of the card.
local function setCardOpen(open: boolean)
	pcall(function()
		GuiService.TouchControlsEnabled = not open
	end)
end

-- The shop takes the waiting-room card's place while it's open, and the mobile thumbstick and
-- jump button step aside so they never sit on top of it.
shopScreen.OnOpenChanged = function(open)
	lobbyPanel.Root.Visible = not open and lobbyPanel.LastMessage ~= nil and lobbyPanel.Showing == true
	setCardOpen(open)
end

local function hideOverlays()
	voteScreen:hide()
	instructions:hide()
	results:hide()
	standings:hide()
	setCardOpen(false)
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

local currentPhase = nil
local inRound = false -- true from Instructions until Results/Lobby
local amParticipant = false
local useProgressBar = false -- this minigame shows a race bar instead of the chip strip

local function showRoundHud()
	if useProgressBar then
		progressBar:show()
	else
		chips:show()
	end
end

local function beginRound(message)
	if inRound then
		return
	end
	inRound = true
	amParticipant = isParticipant(message.Participants)
	useProgressBar = message.Minigame.ProgressBar == true
	startMinigameClient(message.Minigame.ClientModule)
	CameraController.start(message.Minigame.Camera, message.ArenaOrigin)
	CameraController.setSpectating(not amParticipant)
end

local function endRound()
	inRound = false
	onboarding:setMinigame(nil)
	stopMinigameClient()
	Controls.unbind()
	CameraController.stop()
	spectatorBar:hide()
	chips:hide()
	progressBar:hide()
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
	progressBar:update(list, myId)
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
	boardView:hide()
	hud:setTimer(nil)
	hud:setStatus(nil)
	if message.WaitingRoom then
		hud:setLobby(nil)
		lobbyPanel.Showing = true
		lobbyPanel:show(message)
		shopScreen:setAvailable(true)
		if shopScreen.Open then
			lobbyPanel.Root.Visible = false
		end
	else
		lobbyPanel.Showing = false
		lobbyPanel:hide()
		shopScreen:setAvailable(false)
		hud:setLobby(message.Text or "Lobby", message.EndsAt)
	end
end

phaseHandlers[Phase.Board] = function(_message)
	hideOverlays()
	lobbyPanel.Showing = false
	shopScreen:setAvailable(false)
	endRound()
	lobbyPanel:hide()
	hud:setLobby(nil)
	hud:setTimer(nil)
	hud:setStatus(nil)
	setCardOpen(true) -- no walking on the board: hide the thumbstick so the roll button is clear
	fitHudToScreen() -- the top-bar inset is known by now
	boardView:show()
end

phaseHandlers[Phase.Standings] = function(message)
	hideOverlays()
	lobbyPanel.Showing = false
	shopScreen:setAvailable(false)
	endRound()
	lobbyPanel:hide()
	boardView:show()
	boardView:hidePanels()
	hud:clearToasts()
	setCardOpen(true)
	standings:show(message, myId)
end

phaseHandlers[Phase.Vote] = function(message)
	hideOverlays()
	lobbyPanel.Showing = false
	shopScreen:setAvailable(false)
	boardView:hide()
	lobbyPanel:hide()
	hud:setLobby(nil)
	setCardOpen(true)
	voteScreen:show(message.Choices, message.EndsAt)
end

phaseHandlers[Phase.Instructions] = function(message)
	hideOverlays()
	boardView:hide() -- duels from a board space skip the vote, so the board HUD goes here too
	hud:setLobby(nil)
	setCardOpen(true)
	instructions:show(message.Minigame, message.Participants, message.EndsAt, myId)
	beginRound(message)
	if not amParticipant then
		hud:setStatus("👀 Spectating this round")
	end
	refreshSpectator()
end

phaseHandlers[Phase.Countdown] = function(message)
	hideOverlays()
	showRoundHud() -- not during Instructions: the strip would sit on top of the card
	hud:showBanner(tostring(message.Number), nil, 0.7)
end

phaseHandlers[Phase.Playing] = function(message)
	hideOverlays()
	beginRound(message) -- no-op normally; covers joining mid-round
	showRoundHud()
	hud:showBanner("GO!", Theme.Colors.Good, 0.8)
	hud:setTimer(message.EndsAt)
	if amParticipant and not CameraController.isSpectating() then
		Controls.bind(message.Minigame.Controls, sendAction)
	end
	onboarding:setMinigame({
		Playing = true,
		Participant = amParticipant,
		Controls = message.Minigame.Controls,
		Spectating = CameraController.isSpectating,
		Bound = function()
			return Controls.current() ~= nil
		end,
	})
end

phaseHandlers[Phase.Finished] = function(_message)
	onboarding:setMinigame(nil)
	stopMinigameClient() -- hand the bodies back to the server before it sends everyone home
	Controls.unbind()
	hud:setTimer(nil)
	hud:showBanner("FINISH!", Theme.Colors.Hot, 1.5)
end

phaseHandlers[Phase.Results] = function(message)
	hideOverlays()
	endRound() -- everyone is back in the lobby: normal camera + controls
	hud:setStatus(nil)
	hud:clearToasts()
	setCardOpen(true)
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
			currentPhase = message.Phase
			-- Phones: on the board the toast feed moves to the top right (off the standings).
			hud:setBoardToasts(message.Phase == Phase.Board or message.Phase == Phase.Standings)
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
	elseif message.Type == Net.Message.BoardLayout then
		boardView:setLayout(message)
	elseif message.Type == Net.Message.BoardState then
		boardView:setState(message)
	elseif message.Type == Net.Message.Prompt then
		boardView:showPrompt(message)
	elseif message.Type == Net.Message.Inventory then
		lobbyPanel:setInventory(message)
		shopScreen:setInventory(message)
	elseif message.Type == Net.Message.ShopResult then
		shopScreen:showResult(message)
	elseif message.Type == Net.Message.Tutorial then
		onboarding:setFlags(message.Flags)
	end
end)

local function amSeatedOnBoard(): boolean
	for _, seat in (boardView.State and boardView.State.Seats) or {} do
		if seat.Id == myId then
			return true
		end
	end
	return false
end

-- YOU marker: on the board while you hold a seat, in a minigame while you're playing it (not
-- spectating, not knocked out); never while a full-screen card is up.
local function youMarkerWanted(): boolean
	local cardOpen = false
	for _, card in { voteScreen.Root, instructions.Root, results.Root, standings.Root } do
		cardOpen = cardOpen or card.Visible
	end
	return YouMarker.shouldShow({
		CardOpen = cardOpen,
		Phase = currentPhase,
		InRound = inRound,
		Participant = amParticipant,
		Spectating = CameraController.isSpectating(),
		OnBoard = boardView.Visible and boardView.Header.Visible,
		Seated = amSeatedOnBoard(),
	})
end

RunService.RenderStepped:Connect(function()
	hud:update()
	voteScreen:update()
	instructions:update()
	boardView:update()
	lobbyPanel:update()
	onboarding:update()
	youMarker:setActive(youMarkerWanted())
	youMarker:update()
end)

-- Ask for the current state in case we joined mid-round.
sendInput({ Kind = Net.Input.Ready })
