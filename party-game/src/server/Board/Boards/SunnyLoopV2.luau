--[[
	Sunny Loop v2 (PREVIEW): the production redesign of Sunny Loop as a floating sky-garden
	festival with three areas around a sundial pavilion. Development variant: only offered in
	the waiting room when Config.Match.ShowPreviewBoards is on (Studio). The original Sunny Loop
	(Classic.luau) is unchanged and stays the default.

	Same rules as Classic; only the route and the look differ. Plan, landmarks and art notes:
	docs/SunnyLoopV2.md. Route plan picture: docs/sunny-loop-v2/route-plan.svg.

	Each space adds to the Classic format:
	  At      { x, z, height }: grid cell (x Config.Board.SpaceSpacing) + height in studs
	  Area    "Stream" | "Orchard" | "Fair" | "Village" (art + camera grouping only)
	  Landmark  the physical place this space belongs to (art + camera moments only)

	Clockwise loop: Sun Gate (south) -> Orchard (west) -> Hilltop Fairground (north)
	-> Waterwheel Village (east) -> Stream walk (south) -> Sun Gate.

	  Fork A  5: Market Lane (6-9, past the Orchard Market shop)  | Hillside Steps (30-32, up the
	          orchard terrace: shorter, riskier). Both rejoin at 10.
	  Fork B 12: Fairground Road (13-24, the long way)              | Sundial Bridge (33-37, elevated
	          over the stream and past the sundial; toll 3, the Bell Switch at 19 can close it).
	          Rejoins at 25.
	  Fork C 15: Fair Midway (16-18, event stage)                     | Crown Terrace (38-40, past the
	          Crown pavilion and the fair kiosk). Both rejoin at 19 (Bell Switch).
]]

return {
	Name = "SunnyLoopV2",
	DisplayName = "Sunny Loop (preview)",
	Preview = true, -- development variant (see Config.Match.PreviewBoards)
	Style = "Medallion", -- round space medallions, height-aware paths
	Scene = "SkyGarden", -- environment dressing (vertical slice: the orchard)
	Presentation = "Diorama", -- close turn camera + thrown dice
	Start = 1,
	-- Board-opening intro (BoardWorld:introSpec): a sky dive-in to the whole map, then each participant rides a
	-- sunbeam down under the Sun Gate (between 29 and 1) and walks to their slot on Start.
	Intro = {
		Arrival = { Camera = { 0.2, -5.85, 12 }, Look = { 0.25, -4.45, 2.5 } }, -- due south: clear of gate posts and lamps
		Entry = { { 0.58, -4.43, 16 }, { 0.58, -4.43, 0 } },
		Group = { Camera = { 0.05, -6.15, 10 }, Look = { 0.05, -4.6, 2.5 } },
		Effect = "Sunbeam",
	},
	CrownSpaces = { 9, 17, 22, 26, 28, 31, 39 },
	Gates = {
		{ Id = "SundialBridge", From = 12, To = 33, Open = true, Toll = 3 },
	},
	Spaces = {
		-- Stream walk + Sun Gate (south), heading west
		{ Id = 1, Type = "Neutral", At = { 0.0, -4.6, 0 }, Next = { 2 }, Area = "Stream", Landmark = "SunGate" },
		{ Id = 2, Type = "Gain", At = { -1.05, -4.7, 0 }, Next = { 3 }, Area = "Stream" },
		{ Id = 3, Type = "Item", At = { -2.1, -4.5, 0 }, Next = { 4 }, Area = "Stream" },
		-- Orchard (west), heading north
		{ Id = 4, Type = "Gain", At = { -3.0, -4.0, 0 }, Next = { 5 }, Area = "Orchard" },
		{
			Id = 5,
			Type = "Neutral",
			At = { -3.7, -3.25, 0 },
			Next = { 6, 30 },
			Paths = { "Market Lane", "Hillside Steps" },
			Area = "Orchard",
			Landmark = "OrchardSignpost",
		},
		{ Id = 6, Type = "Gain", At = { -4.6, -2.75, 0 }, Next = { 7 }, Area = "Orchard" },
		{ Id = 7, Type = "Shop", At = { -5.15, -1.85, 0 }, Next = { 8 }, Area = "Orchard", Landmark = "OrchardMarket" },
		{ Id = 8, Type = "Lose", At = { -5.35, -0.85, 0 }, Next = { 9 }, Area = "Orchard" },
		{ Id = 9, Type = "Gain", At = { -5.2, 0.15, 0 }, Next = { 10 }, Area = "Orchard" },
		{ Id = 10, Type = "Gain", At = { -4.75, 1.1, 1 }, Next = { 11 }, Area = "Orchard" },
		{ Id = 11, Type = "Lose", At = { -4.35, 2.05, 2 }, Next = { 12 }, Area = "Orchard" },
		{
			Id = 12,
			Type = "Neutral",
			At = { -3.7, 2.85, 3 },
			Next = { 13, 33 },
			Paths = { "Fairground Road", "Sundial Bridge (toll)" },
			Area = "Orchard",
			Landmark = "BridgeGate",
		},
		-- Hilltop Fairground (north), heading east
		{ Id = 13, Type = "Gain", At = { -2.85, 3.5, 4 }, Next = { 14 }, Area = "Fair" },
		{ Id = 14, Type = "Chaos", At = { -1.85, 3.9, 5 }, Next = { 15 }, Area = "Fair" },
		{
			Id = 15,
			Type = "Neutral",
			At = { -0.8, 4.05, 6 },
			Next = { 16, 38 },
			Paths = { "Fair Midway", "Crown Terrace" },
			Area = "Fair",
			Landmark = "FairSignpost",
		},
		{ Id = 16, Type = "Event", At = { 0.2, 3.55, 6 }, Next = { 17 }, Area = "Fair", Landmark = "EventStage" },
		{ Id = 17, Type = "Gain", At = { 1.2, 3.4, 6 }, Next = { 18 }, Area = "Fair" },
		{ Id = 18, Type = "Item", At = { 2.2, 3.6, 6 }, Next = { 19 }, Area = "Fair" },
		{ Id = 19, Type = "Switch", At = { 3.1, 4.2, 6 }, Next = { 20 }, Area = "Fair", Landmark = "BellSwitch" },
		-- Waterwheel Village (east), heading south
		{ Id = 20, Type = "Gain", At = { 3.95, 3.6, 5 }, Next = { 21 }, Area = "Village" },
		{ Id = 21, Type = "Lose", At = { 4.6, 2.75, 4 }, Next = { 22 }, Area = "Village" },
		{ Id = 22, Type = "Gain", At = { 5.0, 1.75, 3 }, Next = { 23 }, Area = "Village" },
		{ Id = 23, Type = "Reward", At = { 5.15, 0.7, 2 }, Next = { 24 }, Area = "Village", Landmark = "Waterwheel" },
		{ Id = 24, Type = "Event", At = { 5.0, -0.35, 1 }, Next = { 25 }, Area = "Village" },
		{ Id = 25, Type = "Gain", At = { 4.7, -1.35, 0 }, Next = { 26 }, Area = "Village" },
		{ Id = 26, Type = "Item", At = { 4.1, -2.25, 0 }, Next = { 27 }, Area = "Village", Landmark = "MillDock" },
		-- Stream walk (south), heading west back to the Sun Gate
		{ Id = 27, Type = "Lose", At = { 3.3, -3.0, 0 }, Next = { 28 }, Area = "Stream" },
		{ Id = 28, Type = "Gain", At = { 2.3, -3.65, 0 }, Next = { 29 }, Area = "Stream" },
		{ Id = 29, Type = "Chaos", At = { 1.15, -4.25, 0 }, Next = { 1 }, Area = "Stream" },
		-- Hillside Steps (fork A, up the orchard terrace)
		{ Id = 30, Type = "Event", At = { -3.55, -2.15, 4 }, Next = { 31 }, Area = "Orchard", Landmark = "OrchardSteps" },
		{ Id = 31, Type = "Reward", At = { -3.75, -1.05, 6 }, Next = { 32 }, Area = "Orchard", Landmark = "OrchardGrove" },
		{ Id = 32, Type = "Duel", At = { -3.95, 0.05, 6 }, Next = { 10 }, Area = "Orchard" },
		-- Sundial Bridge (fork B, elevated toll shortcut over the stream)
		{ Id = 33, Type = "Lose", At = { -2.6, 2.2, 6 }, Next = { 34 }, Area = "Stream", Landmark = "SundialBridge" },
		{ Id = 34, Type = "Gain", At = { -1.45, 1.35, 8 }, Next = { 35 }, Area = "Stream", Landmark = "SundialBridge" },
		{ Id = 35, Type = "Event", At = { -0.1, 0.45, 10 }, Next = { 36 }, Area = "Stream", Landmark = "SundialPavilion" },
		{ Id = 36, Type = "Reward", At = { 1.75, -0.3, 8 }, Next = { 37 }, Area = "Stream", Landmark = "SundialBridge" },
		{ Id = 37, Type = "Neutral", At = { 3.3, -0.85, 4 }, Next = { 25 }, Area = "Village", Landmark = "SundialBridge" },
		-- Crown Terrace (fork C, upper fairground)
		{ Id = 38, Type = "Gain", At = { -0.2, 4.95, 9 }, Next = { 39 }, Area = "Fair" },
		{ Id = 39, Type = "Neutral", At = { 1.0, 5.25, 10 }, Next = { 40 }, Area = "Fair", Landmark = "CrownPavilion" },
		{ Id = 40, Type = "Shop", At = { 2.15, 5.05, 9 }, Next = { 19 }, Area = "Fair", Landmark = "FairKiosk" },
	},
}
