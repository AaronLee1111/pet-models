--[[
	Net
	The two RemoteEvents the whole framework uses, plus the message vocabulary.

	  PartyState  (server -> client): authoritative state. The client only ever renders this.
	  PartyInput  (client -> server): inputs only (ready / vote / minigame action).
	                                  The server validates every one of them.

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
}

-- Server -> client message types (message.Type).
Net.Message = {
	Phase = "Phase", -- full phase change; carries everything needed to draw that screen
	VoteUpdate = "VoteUpdate", -- live vote counts during the Vote phase
	Status = "Status", -- persistent HUD line set by the minigame ("Doge has the potato!")
	Toast = "Toast", -- short-lived feed message ("BOOM!")
}

-- Client -> server input kinds (payload.Kind).
Net.Input = {
	Ready = "Ready", -- client finished loading; server replies with a state snapshot
	Vote = "Vote", -- payload.Choice = index of the vote card
	Action = "Action", -- payload.Action = action name declared in the minigame's Info.Controls
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

local function getRemote(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
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

return Net
