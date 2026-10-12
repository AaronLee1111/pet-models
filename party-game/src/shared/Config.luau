--[[
	Config
	Shared tuning knobs for the party framework. Safe to require from server and client.
	Everything timing/coin related lives here so designers can tweak without touching logic.
]]

local Config = {}

-- Match shape ---------------------------------------------------------------

-- Every round always has exactly this many participants; bots fill empty slots.
Config.PlayersPerMatch = 4

-- Layouts a minigame can declare in Info.Layout.
Config.Layouts = {
	FFA = "FFA", -- everyone for themselves
	OneVsThree = "1v3", -- one solo player vs a team of three
	TwoVsTwo = "2v2", -- two teams of two
}

-- Phase timings (seconds) ----------------------------------------------------

Config.IntermissionDuration = 5 -- lobby wait before the vote opens
Config.VoteChoices = 3 -- cards shown on the vote screen
Config.VoteDuration = 12
Config.InstructionsDuration = 7
Config.CountdownFrom = 3
Config.FinishBannerDuration = 2 -- "FINISH!" beat before teleporting back
Config.ResultsDuration = 8

-- Coins ----------------------------------------------------------------------

-- Coins awarded by placement. Ties share a placement, so two 1st places both get 10.
Config.CoinsByPlacement = { 10, 6, 3, 1 }

-- World layout -----------------------------------------------------------------

-- Arenas are built here, far away from the lobby so they never overlap it.
Config.ArenaOrigin = Vector3.new(0, 80, 600)
-- Eliminated participants watch from a glass box this far above the arena origin.
Config.SpectatorOffset = Vector3.new(0, 45, 0)
-- Anyone this many studs below the arena origin counts as having fallen out.
Config.FallOutDepth = 25

-- Movement defaults restored after every round.
Config.DefaultWalkSpeed = 16
Config.DefaultJumpPower = 50
Config.DefaultJumpHeight = 7.2

-- Camera ---------------------------------------------------------------------------

-- Camera modes a minigame can pick in Info.Camera.Mode. Each minigame can override any
-- of these numbers in its own Info.Camera table.
Config.CameraModes = {
	AngledOverhead = { Height = 55, Distance = 42, Follow = 0.3, Smooth = 6 }, -- whole arena, nudged toward you
	FollowBehind = { Height = 9, Distance = 16, Smooth = 10 }, -- over-the-shoulder chase cam
	SideView = { Height = 6, Distance = 48, Smooth = 8 }, -- 2D side-scroller, looks along the arena's LookVector
}
Config.DefaultCameraMode = "AngledOverhead"
Config.Spectator = { Height = 28, Distance = 30, OrbitSpeed = 0.25 }

-- Player chips: how often progress updates are pushed to clients (seconds).
Config.ChipFlushInterval = 0.15

-- Bots ---------------------------------------------------------------------------

Config.BotThinkInterval = 0.2 -- how often each bot's brain runs
Config.BotVoteDelay = { 1.5, 5 } -- bots "think" about their vote for this long (min, max)
Config.BotNames = {
	"Doge",
	"Big Chungus",
	"Stonks",
	"Sus Bean",
	"Nyan",
	"Shrek",
	"Grumpy",
	"Bonk",
	"Pepe Jr",
	"Rickroll",
}

-- Networking -------------------------------------------------------------------

Config.InputRateLimit = 20 -- max inputs per second per player before they are dropped

-- The extra vote card shown when there are fewer minigames than Config.VoteChoices.
Config.RandomChoice = {
	Id = "__random",
	Name = "🎲 Surprise Me",
	Description = "Can't decide? Let chaos pick for you.",
	Layout = "???",
}

return Config
