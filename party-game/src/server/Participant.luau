--[[
	Participant
	One seat in a round. Wraps either a real Player or a Bot behind the same API,
	so minigames never need to care which one they are dealing with.

	Fields:
	  Id      unique string ("player_123" / "bot_1"), also what the client sees
	  Name    display name
	  IsBot   true for bots
	  Player  the Player (real players only)
	  Bot     the Bot object from BotService (bots only)
	  Team    team number for 1v3 / 2v2 layouts, nil in FFA
	  Left    true once a real player leaves mid-round
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)

local Participant = {}
Participant.__index = Participant

function Participant.fromPlayer(player: Player)
	return setmetatable({
		Id = "player_" .. player.UserId,
		Name = player.DisplayName,
		IsBot = false,
		Player = player,
		Bot = nil,
		Team = nil,
		Left = false,
	}, Participant)
end

function Participant.fromBot(bot)
	local self = setmetatable({
		Id = bot.Id,
		Name = bot.Name,
		IsBot = true,
		Player = nil,
		Bot = bot,
		Team = nil,
		Left = false,
	}, Participant)
	bot.Participant = self
	return self
end

function Participant:GetCharacter(): Model?
	if self.IsBot then
		return self.Bot.Model
	end
	return self.Player.Character
end

function Participant:GetHumanoid(): Humanoid?
	local character = self:GetCharacter()
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Participant:GetRoot(): BasePart?
	local character = self:GetCharacter()
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Participant:GetPosition(): Vector3?
	local root = self:GetRoot()
	return root and root.Position
end

-- True if the participant is still in the game and has a living body in the world.
function Participant:IsAlive(): boolean
	if self.Left then
		return false
	end
	local character = self:GetCharacter()
	local humanoid = self:GetHumanoid()
	return character ~= nil
		and character.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and self:GetRoot() ~= nil
end

-- Moves the whole character, killing any leftover momentum.
function Participant:Teleport(cframe: CFrame)
	local character = self:GetCharacter()
	local root = self:GetRoot()
	if not character or not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(cframe)
	if self.IsBot then
		self.Bot:Stop()
	end
end

function Participant:SetMovement(walkSpeed: number, canJump: boolean)
	local humanoid = self:GetHumanoid()
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = walkSpeed
	-- Set both so it works whichever of UseJumpPower the place uses.
	humanoid.JumpPower = if canJump then Config.DefaultJumpPower else 0
	humanoid.JumpHeight = if canJump then Config.DefaultJumpHeight else 0
end

function Participant:Freeze()
	self:SetMovement(0, false)
	if self.IsBot then
		self.Bot:Stop()
	end
end

function Participant:ResetMovement()
	self:SetMovement(Config.DefaultWalkSpeed, true)
end

-- Data the client needs to draw this participant (names, bot icon, team colour).
function Participant:Describe()
	return {
		Id = self.Id,
		Name = self.Name,
		IsBot = self.IsBot,
		Team = self.Team,
	}
end

return Participant
