--[[
	Tutorial
	Which guided first actions a real player has already done (Config.Tutorial.Flags). The
	client points at the right button while a flag is unset; the server sets a flag only when
	the matching action really went through (a roll was accepted, a route was picked...).

	  Tutorial.configure(getProfile, send)   Main wires in Profiles.get and MinigameManager.sendTo
	  Tutorial.complete(who, flag) -> bool   who = Player or Participant; bots are ignored
	  Tutorial.flags(player) -> { [flag] = true }
	  Tutorial.send(player)                  push the flags to that player's client
	  Tutorial.reset(player)                 development only (see README)

	Flags live in the profile (ProfileStore.Tutorial) and are saved with it. A player whose
	profile isn't available (still loading, or DataStores down) keeps flags for this session
	only, so the guidance still works and never repeats within the session.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PartyShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Tutorial = {}

local known = {}
for _, flag in Config.Tutorial.Flags do
	known[flag] = true
end

local getProfile: (Player) -> any = function()
	return nil
end
local sendTo: ((Player, any) -> ())? = nil
local session: { [number]: { [string]: boolean } } = {} -- by UserId, when there's no profile

local function realPlayer(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end
local isPlayer = realPlayer

-- playerCheck: unit tests pass one that accepts their stand-in players.
function Tutorial.configure(profileGetter: (Player) -> any, sender: ((Player, any) -> ())?, playerCheck: ((any) -> boolean)?)
	getProfile = profileGetter
	sendTo = sender
	isPlayer = playerCheck or realPlayer
end

-- A Player, or a Participant that is a real player (bots and seats taken over by bots: nil).
local function playerOf(who): Player?
	if isPlayer(who) then
		return who
	end
	if type(who) == "table" and not who.IsBot and isPlayer(who.Player) then
		return who.Player
	end
	return nil
end

-- The table the flags are kept in: the profile's, or this session's.
local function store(player: Player): { [string]: boolean }
	local profile = getProfile(player)
	if type(profile) == "table" then
		if type(profile.Tutorial) ~= "table" then
			profile.Tutorial = {}
		end
		-- Anything done before the profile finished loading counts too.
		local early = session[player.UserId]
		if early then
			for flag in early do
				profile.Tutorial[flag] = true
			end
			session[player.UserId] = nil
		end
		return profile.Tutorial
	end
	session[player.UserId] = session[player.UserId] or {}
	return session[player.UserId]
end

function Tutorial.flags(player: Player): { [string]: boolean }
	local flags = {}
	for flag, done in store(player) do
		if known[flag] and done == true then
			flags[flag] = true
		end
	end
	return flags
end

function Tutorial.send(player: Player)
	if sendTo and player.Parent ~= nil then
		sendTo(player, { Type = Net.Message.Tutorial, Flags = Tutorial.flags(player) })
	end
end

-- Marks `flag` done. Returns true if it was newly set (and tells that player's client).
function Tutorial.complete(who, flag: string): boolean
	local player = playerOf(who)
	if not player or not known[flag] then
		return false
	end
	local flags = store(player)
	if flags[flag] then
		return false
	end
	flags[flag] = true
	Tutorial.send(player)
	return true
end

-- Development only: forget a player's flags (profile and session) so the guidance starts over.
function Tutorial.reset(player: Player)
	local profile = getProfile(player)
	if type(profile) == "table" then
		profile.Tutorial = {}
	end
	session[player.UserId] = nil
	Tutorial.send(player)
end

-- Profile just loaded: optional Studio reset, then send the saved flags.
function Tutorial.onProfileLoaded(player: Player, _profile)
	if Config.Tutorial.ResetInStudio and RunService:IsStudio() then
		Tutorial.reset(player)
	else
		Tutorial.send(player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	session[player.UserId] = nil
end)

return Tutorial
