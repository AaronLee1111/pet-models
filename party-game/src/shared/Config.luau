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
	Duel = "Duel", -- exactly two players (board Duel spaces); never in the normal vote
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

-- Match (board game) ------------------------------------------------------------

Config.Match = {
	-- Defaults; the host can change these in the waiting room.
	BoardRounds = 5, -- each round = every seat takes one turn, then one minigame
	BoardRoundChoices = { 3, 5, 8, 12 },
	BotDifficulty = "Normal",
	-- bot.Skill is rolled in this range (0..1). Minigame bots and board decisions both use it.
	BotDifficulties = {
		Easy = { 0.1, 0.45 },
		Normal = { 0.35, 0.85 },
		Hard = { 0.75, 1 },
	},
	BotDifficultyOrder = { "Easy", "Normal", "Hard" },
	Board = "Classic", -- default board: module name in PartyServer/Board/Boards
	Boards = { "Classic", "MagicalFestival" }, -- boards the host can pick (in this order)
	-- "Board": full board party.  "Minigames": back-to-back minigames only, most coins wins.
	Mode = "Board",
	Modes = { "Board", "Minigames" },
	WaitingRoomDuration = 15, -- seconds the waiting room counts down before a match
	StandingsDuration = 10, -- final standings screen
	PreBonusDuration = 5, -- standings before the bonus awards
	BonusDuration = 7, -- the bonus awards card
	OrderRollTimeout = 10, -- players who don't roll for turn order in time roll automatically
	-- How bots play the board at each difficulty (see Board/BotBrain).
	--   RandomChoice    chance any decision is made at random instead of thought through
	--   ItemUseChance   chance a bot uses an item when it has a good reason to
	--   SaveFactor      share of the Crown price kept in reserve before shopping (0..1)
	--   LookAhead       spaces scored down each fork branch (0 = don't look)
	--   CosmeticSpend   only buy cosmetics with at least this many coins to spare
	BotBehavior = {
		Easy = { RandomChoice = 0.6, ItemUseChance = 0.3, SaveFactor = 0, LookAhead = 0, CosmeticSpend = 0 },
		Normal = { RandomChoice = 0.2, ItemUseChance = 0.7, SaveFactor = 0.6, LookAhead = 6, CosmeticSpend = 15 },
		Hard = { RandomChoice = 0, ItemUseChance = 1, SaveFactor = 1, LookAhead = 10, CosmeticSpend = 25 },
	},
}

-- Rejoining: a player who leaves mid-match has their seat kept for their UserId until the
-- match ends (a bot plays it meanwhile) and gets it back if they rejoin. Off = old behavior
-- (they watch until the next match).
Config.SeatReclaim = {
	Enabled = true,
}

Config.Board = {
	Origin = Vector3.new(0, 0, -300), -- far from the lobby (0,0,0) and the arenas
	SpaceSpacing = 12, -- studs between grid cells in board layouts
	DieSides = 6,
	RollTimeout = 12, -- a player who doesn't roll in time rolls automatically
	ChoiceTimeout = 10, -- unanswered prompts take their default option
	HopTime = 0.35, -- seconds per space moved
	BotRollDelay = { 0.8, 1.6 },
	BotChoiceDelay = { 0.6, 1.4 },
	LandPause = 1.5, -- beat after landing so everyone can read what happened
}

-- The primary collectible (wins the match; coins only break ties). Placeholder name.
Config.Collectible = {
	Name = "Crown",
	Plural = "Crowns",
	Price = 20, -- coins
}

-- All coin amounts the board hands out or takes, in one place.
Config.Economy = {
	StartingCoins = 10,
	GainSpaceCoins = 3,
	LoseSpaceCoins = 3,
	-- Reward spaces roll one of these (Weight is relative).
	Rewards = {
		{ Kind = "Coins", Amount = 5, Weight = 6 },
		{ Kind = "Coins", Amount = 10, Weight = 3 },
		{ Kind = "Cosmetic", Weight = 2 }, -- a random cosmetic the owner doesn't have yet
		{ Kind = "Collectible", Amount = 1, Weight = 0.5 },
		{ Kind = "Item", Weight = 3 }, -- a random board item (Board/Items), if there's room
	},
	ShopOffers = 2, -- cosmetics offered per shop visit
	ShopItemOffers = 1, -- board items offered per shop visit (on top of the cosmetics)
	ItemSpaceFallbackCoins = 3, -- Item space with a full bag
	ChaosLossCap = 15, -- most coins a single Chaos space can take
	PriceSurgeCap = 10, -- Price Surge can raise the Crown price by at most this much
	DuelStakes = { 5, 10, 20 }, -- Duel space wagers (only ones both duellists can pay are offered)
	CrownMovePrice = 8, -- Switch space: pay this to send the Crown somewhere else
}

-- Comeback help for trailing players. Kept small and late so early play still matters.
--   StartRound            no help before this round
--   LastPlaceCoins        coins for the last-place seat(s) at the start of each round
--   UnderdogGap           a seat this many Crowns behind the leader is an "underdog" ...
--   UnderdogDiscount      ... and pays this much less for a Crown (never below MinCrownPrice)
--   UnderdogGiftBoost     ... and its Gift-space Item/Crown chances are multiplied by this
--   FinalFrenzy           in the last round Gain/Lose spaces are worth FrenzyMultiplier times more
Config.Comeback = {
	Enabled = true,
	StartRound = 2,
	LastPlaceCoins = 5,
	UnderdogGap = 2,
	UnderdogDiscount = 5,
	MinCrownPrice = 10,
	UnderdogGiftBoost = 2,
	FinalFrenzy = true,
	FrenzyMultiplier = 2,
}

-- Board items (Board/Items has the list). One item may be used per turn, before rolling.
Config.Items = {
	MaxHeld = 3,
	StartingItems = {}, -- item ids every seat starts a match with, e.g. { "DoubleDice" }
}

-- End-of-match bonus awards, given after the last round and before the final standings.
--   Stat       a per-seat statistic tracked by Match (MinigamePoints, CoinsEarned, SpacesMoved)
--   AwardTies  true: every tied leader gets it; false: a tie means nobody does
-- Nobody wins a bonus whose best value is 0.
Config.Bonuses = {
	{ Id = "MinigameMaster", Name = "Minigame Master", Description = "Best minigame results", Stat = "MinigamePoints", Crowns = 1, AwardTies = true },
	{ Id = "CoinCollector", Name = "Coin Collector", Description = "Most coins earned this match", Stat = "CoinsEarned", Crowns = 1, AwardTies = true },
	{ Id = "Explorer", Name = "Explorer", Description = "Most board spaces travelled", Stat = "SpacesMoved", Crowns = 1, AwardTies = true },
}
-- Minigame Master points per minigame placement (ties share a placement).
Config.MinigamePointsByPlacement = { 3, 2, 1, 0 }

-- Permanent profile (see PartyServer/Profiles). Match coins and Crowns never go in here.
Config.Profile = {
	-- "Auto": DataStore in live servers, Memory in Studio (so testing never touches real saves).
	-- "Memory" | "DataStore" force one (DataStore in Studio needs API access turned on).
	Backend = "Auto",
	AutosaveInterval = 120, -- seconds between saves of every loaded profile
	BankCoinsByPlacement = { 30, 20, 12, 8 }, -- permanent coins for real players by final placement
}

-- Guided first actions (client pointer + YOU marker). Each flag is set once, in the player's
-- profile, after they really do that thing; until then the pointer shows them where to tap.
Config.Tutorial = {
	Flags = {
		"StartedMatch", -- host pressed START in the waiting room
		"RolledForOrder", -- rolled for turn order
		"RolledBoardTurn", -- rolled on a normal board turn
		"SawItem", -- used an item, or rolled while holding one
		"ChoseFork", -- picked a route at a fork
		"UsedMinigameAction", -- pressed a minigame action button
		"SawCrownPurchase", -- answered a Crown purchase offer
	},
	-- Development only: in Studio, wipe a player's flags when they join (fresh tutorial
	-- every playtest even with a saved profile). Never applies on live servers.
	ResetInStudio = false,
}

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
-- Touch devices only (desktop and console are not affected). Zoom multiplies the mode's
-- Height and Distance so characters are bigger on a small screen; LookAhead aims the camera
-- that many studs past the arena centre, which slides the arena down out from under the HUD.
Config.TouchCamera = { AngledOverhead = { Zoom = 0.8, LookAhead = 6 } }
Config.Spectator = { Height = 28, Distance = 30, OrbitSpeed = 0.25 }

-- Player chips: how often progress updates are pushed to clients (seconds).
Config.ChipFlushInterval = 0.15

-- Bots ---------------------------------------------------------------------------

Config.BotThinkInterval = 0.2 -- how often each bot's brain runs
Config.BotVoteDelay = { 1.5, 5 } -- bots "think" about their vote for this long (min, max)
Config.BotNames = {
	"Pip",
	"Mochi",
	"Ziggy",
	"Nova",
	"Biscuit",
	"Pebble",
	"Juniper",
	"Comet",
	"Waffles",
	"Maple",
}

-- Networking -------------------------------------------------------------------

Config.InputRateLimit = 20 -- max inputs per second per player before they are dropped
Config.MinigameMessageRateLimit = 40 -- same, for messages a minigame's own client code sends

-- The extra vote card shown when there are fewer minigames than Config.VoteChoices.
Config.RandomChoice = {
	Id = "__random",
	Name = "🎲 Surprise Me",
	Description = "Can't decide? Let the game pick one at random.",
	Layout = "???",
}

return Config
