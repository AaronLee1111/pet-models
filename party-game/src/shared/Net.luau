--[[
	Net
	The two RemoteEvents the whole framework uses, plus the message vocabulary.

	  PartyState  (server -> client): authoritative state. The client only ever renders this.
	  PartyInput  (client -> server): inputs only (ready / vote / minigame action).
	                                  The server validates every one of them.

	Two more remotes exist for minigames that run their own client code (Info.ClientModule):

	  PartyMinigame      reliable, both ways: setup data, corrections
	  PartyMinigameFast  unreliable, both ways: high-rate state (positions) where a lost
	                     packet doesn't matter because a newer one is right behind it

	Whatever a client sends on these goes to the active minigame's OnClientMessage, which
	must treat it as untrusted.

	The server creates the remotes; clients wait for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "PartyRemotes"

local Net = {}

-- Phases the server walks through each round. The client shows a screen per phase.
Net.Phase = {
	Lobby = "Lobby",
	Vote = "Vote",
	Instructions = "Instructions",
	Countdown = "Countdown",
	Playing = "Playing",
	Finished = "Finished",
	Results = "Results",
	-- Board game (around the minigame rounds above)
	Board = "Board", -- turns on the board; details arrive as BoardState messages
	Standings = "Standings", -- final match standings
}

-- Server -> client message types (message.Type).
Net.Message = {
	Phase = "Phase", -- full phase change; carries everything needed to draw that screen
	VoteUpdate = "VoteUpdate", -- live vote counts during the Vote phase
	Status = "Status", -- persistent HUD line set by the minigame ("Pip has the potato!")
	Toast = "Toast", -- short-lived feed message ("BOOM!")
	Chips = "Chips", -- player-chip strip: every participant's live value + eliminated flag
	BoardLayout = "BoardLayout", -- the board's spaces (sent once per match and to late joiners)
	BoardState = "BoardState", -- seats, coins, collectibles, whose turn, dice, moves left
	Prompt = "Prompt", -- to one player: pick an option (fork, buy, shop); Prompt = nil closes it
}

-- Client -> server input kinds (payload.Kind).
Net.Input = {
	Ready = "Ready", -- client finished loading; server replies with a state snapshot
	Vote = "Vote", -- payload.Choice = index of the vote card
	Action = "Action", -- payload.Action = action name declared in the minigame's Info.Controls
	Roll = "Roll", -- roll the die on your turn
	Choice = "Choice", -- payload.PromptId, payload.Index: answer to a Prompt
	UseItem = "UseItem", -- your turn, before rolling: payload.Slot = index into your items
	Setting = "Setting", -- waiting room, host only: payload.Key ("Rounds" | "Difficulty"), payload.Value
	StartMatch = "StartMatch", -- waiting room, host only: skip the countdown
}

local function getFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function getRemote(name: string, className: string?): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className or "RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.stateRemote(): RemoteEvent
	return getRemote("PartyState")
end

function Net.inputRemote(): RemoteEvent
	return getRemote("PartyInput")
end

function Net.minigameRemote(): RemoteEvent
	return getRemote("PartyMinigame")
end

function Net.minigameFastRemote(): UnreliableRemoteEvent
	return getRemote("PartyMinigameFast", "UnreliableRemoteEvent") :: any
end

return Net
