--[[
	Pattern Recall (FFA, memory)
	Four coloured pads flash a sequence. Then everyone repeats it with the four colour
	buttons. A wrong colour, or not finishing in time, knocks you out. Each round the
	sequence is one longer. Last one standing wins (players out in the same round tie).

	Server-authoritative: the server makes the sequence and checks every press. Bots
	remember each step with a chance that drops as the sequence grows (less with skill).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.PartyShared.Config)
local ResultsUtil = require(script.Parent.Parent.ResultsUtil)

local PatternRecall = {}

PatternRecall.COLORS = { "Red", "Blue", "Green", "Yellow" }
local COLOR_VALUES = {
	Red = Color3.fromRGB(235, 70, 70),
	Blue = Color3.fromRGB(70, 130, 245),
	Green = Color3.fromRGB(70, 210, 100),
	Yellow = Color3.fromRGB(250, 210, 60),
}

PatternRecall.Info = {
	Name = "Pattern Recall",
	Description = "Watch the pads flash, then repeat the colours in order with the buttons. One mistake and you're out. It gets longer every round!",
	Duration = 75,
	Layout = Config.Layouts.FFA,
	Camera = { Mode = "AngledOverhead", Height = 34, Distance = 26 },
	Controls = {
		Move = false,
		Jump = false,
		Actions = {
			{ Action = "Red", Label = "RED", Key = "One", Gamepad = "ButtonB", Side = "Left", Color = COLOR_VALUES.Red },
			{ Action = "Blue", Label = "BLUE", Key = "Two", Gamepad = "ButtonX", Side = "Left", Color = COLOR_VALUES.Blue },
			{ Action = "Green", Label = "GREEN", Key = "Three", Gamepad = "ButtonA", Color = COLOR_VALUES.Green },
			{ Action = "Yellow", Label = "YELLOW", Key = "Four", Gamepad = "ButtonY", Color = COLOR_VALUES.Yellow },
		},
	},
	ProgressLabel = "Recalled",
}

-- Tuning ----------------------------------------------------------------------------------
PatternRecall.START_LENGTH = 3
PatternRecall.FLASH_TIME = 0.55 -- each colour is lit this long ...
PatternRecall.GAP_TIME = 0.2 -- ... with this gap between colours
PatternRecall.INPUT_TIME_PER_STEP = 1.2 -- seconds allowed per colour to repeat it
PatternRecall.INPUT_TIME_BASE = 2
PatternRecall.BOT_STEP_ACCURACY = 0.985 -- skill-1 bot's chance per colour, falls with length
PatternRecall.BOT_FORGET_PER_STEP = 0.02 -- extra miss chance per colour of length (skill 0)

function PatternRecall:Setup(arena, participants, round)
	self.Rng = round.Rng
	self.Sequence = {}
	self.Progress = {} -- participant -> how many of this round's colours they've entered
	self.Done = {} -- participant -> finished this round's sequence
	self.Phase = "Idle" -- Idle | Show | Input
	self.Pads = {}
	self.OutRound = {} -- participant -> round they were knocked out in

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(36, 1, 30)
	floor.CFrame = arena.Origin
	floor.Color = Color3.fromRGB(60, 60, 80)
	floor.Parent = arena.Folder
	for index, colour in PatternRecall.COLORS do
		local pad = Instance.new("Part")
		pad.Name = "Pad" .. colour
		pad.Anchored = true
		pad.Size = Vector3.new(6, 1, 6)
		pad.CFrame = arena.Origin * CFrame.new((index - 2.5) * 7.5, 0.6, -6)
		pad.Color = COLOR_VALUES[colour]:Lerp(Color3.new(0, 0, 0), 0.55)
		pad.Parent = arena.Folder
		self.Pads[colour] = pad
	end

	local spawns = {}
	for index, participant in participants do
		local position = (arena.Origin * CFrame.new((index - (#participants + 1) / 2) * 6, 4, 8)).Position
		spawns[index] = CFrame.lookAt(position, (arena.Origin * CFrame.new(0, 4, -6)).Position)
	end
	return spawns
end

function PatternRecall:_light(colour: string?, on: boolean)
	local pad = colour and self.Pads[colour]
	if pad and pad.Parent then
		pad.Color = if on then COLOR_VALUES[colour] else COLOR_VALUES[colour]:Lerp(Color3.new(0, 0, 0), 0.55)
		pad.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

-- Next round: one colour longer, shown, then everyone repeats it.
function PatternRecall:_nextRound()
	local length = if #self.Sequence == 0 then PatternRecall.START_LENGTH else #self.Sequence + 1
	while #self.Sequence < length do
		table.insert(self.Sequence, PatternRecall.COLORS[self.Rng:NextInteger(1, #PatternRecall.COLORS)])
	end
	self.Phase = "Show"
	self.RoundNumber = (self.RoundNumber or 0) + 1
	local roundNumber = self.RoundNumber
	self.Round:SetStatus(("Watch! %d colours"):format(#self.Sequence))
	task.spawn(function()
		for _, colour in self.Sequence do
			if self.Round.Ended or self.RoundNumber ~= roundNumber then
				return
			end
			self:_light(colour, true)
			task.wait(PatternRecall.FLASH_TIME)
			self:_light(colour, false)
			task.wait(PatternRecall.GAP_TIME)
		end
		if self.Round.Ended or self.RoundNumber ~= roundNumber then
			return
		end
		self:_beginInput()
	end)
end

function PatternRecall:_beginInput()
	self.Phase = "Input"
	self.Progress, self.Done = {}, {}
	for _, participant in self.Round:GetAlive() do
		self.Progress[participant] = 0
	end
	self.Round:SetStatus("Your turn: repeat the colours!")
	local roundNumber = self.RoundNumber
	task.delay(PatternRecall.INPUT_TIME_BASE + PatternRecall.INPUT_TIME_PER_STEP * #self.Sequence, function()
		if self.RoundNumber == roundNumber and self.Phase == "Input" and not self.Round.Ended then
			self:_finishInput()
		end
	end)
end

-- Input over: anyone who didn't finish is out. Then the next round, or the end.
function PatternRecall:_finishInput()
	self.Phase = "Idle"
	for _, participant in self.Round:GetAlive() do
		if not self.Done[participant] then
			self:_knockOut(participant)
		end
	end
	if #self.Round:GetAlive() <= 1 then
		self.Round:End("LastStanding")
		return
	end
	task.delay(1, function()
		if not self.Round.Ended then
			self:_nextRound()
		end
	end)
end

-- A colour press. Wrong colour = out; finishing the sequence = safe this round.
function PatternRecall:Press(participant, colour: string)
	if self.Phase ~= "Input" or self.Done[participant] or self.Round:IsEliminated(participant) then
		return nil
	end
	local index = (self.Progress[participant] or 0) + 1
	if self.Sequence[index] ~= colour then
		self:_knockOut(participant)
		self.Round:Toast(("%s pressed %s, it was %s"):format(participant.Name, colour, self.Sequence[index]))
		self:_checkEveryoneDone()
		return false
	end
	self.Progress[participant] = index
	self.Round:ReportProgress(participant, ("%d/%d"):format(index, #self.Sequence))
	if index == #self.Sequence then
		self.Done[participant] = true
		self:_checkEveryoneDone()
	end
	return true
end

function PatternRecall:_knockOut(participant)
	self.OutRound[participant] = self.RoundNumber or 0
	self.Round:Eliminate(participant)
end

function PatternRecall:_checkEveryoneDone()
	for _, participant in self.Round:GetAlive() do
		if not self.Done[participant] then
			return
		end
	end
	if self.Phase == "Input" then
		self:_finishInput()
	end
end

function PatternRecall:Start()
	for _, participant in self.Participants do
		self.Round:ReportProgress(participant, "0")
	end
	self:_nextRound()
end

function PatternRecall:OnInput(participant, action)
	if table.find(PatternRecall.COLORS, action) then
		self:Press(participant, action)
	end
end

-- Chance a bot gets one colour right in a sequence of `length` (tested).
function PatternRecall.botStepChance(skill: number, length: number): number
	return PatternRecall.BOT_STEP_ACCURACY - (1 - skill) * PatternRecall.BOT_FORGET_PER_STEP * length
end

function PatternRecall:UpdateBot(bot, _dt)
	local participant = bot.Participant
	if self.Phase ~= "Input" or self.Done[participant] then
		return
	end
	local memory = bot.Memory
	if memory.Round ~= self.RoundNumber then
		memory.Round = self.RoundNumber
		memory.NextAt = os.clock() + 0.4 + math.random() * 0.4
	end
	if os.clock() < memory.NextAt then
		return
	end
	memory.NextAt = os.clock() + 0.25 + math.random() * 0.35
	local expected = self.Sequence[(self.Progress[participant] or 0) + 1]
	local colour = expected
	if math.random() > PatternRecall.botStepChance(bot.Skill, #self.Sequence) then
		repeat
			colour = PatternRecall.COLORS[math.random(1, #PatternRecall.COLORS)]
		until colour ~= expected
	end
	bot:Input(colour)
end

-- Lasting longer is better; everyone knocked out in the same round ties.
function PatternRecall:GetResults()
	return ResultsUtil.fromScores(self.Participants, function(participant)
		return self.OutRound[participant] or math.huge
	end)
end

function PatternRecall:Cleanup()
	self.RoundNumber = -1
	self.Phase = "Idle"
end

return PatternRecall
