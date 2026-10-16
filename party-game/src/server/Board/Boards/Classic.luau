--[[
	Classic board: a 26-space loop with one shortcut up the middle.

	Each space:
	  Id      unique number
	  Type    a key of Board/SpaceTypes
	  At      { x, z } grid cell; multiplied by Config.Board.SpaceSpacing
	  Next    ids you can move to from here (2+ = a fork, the mover picks)
	  Paths   optional labels for a fork's choices, same order as Next

	Start          where everyone begins
	CrownSpaces    where the collectible can appear (it moves after every purchase)
	Gates          fork edges that Switch spaces can shut, and/or that cost a toll

	Layout (x across, z up), clockwise from Start at the bottom-left:

	  22 21 20 19 18 17 16 15 14     top row (z = 5); the shortcut rejoins at 18
	  23          30          13
	  24          29          12
	  25          28          11
	  26          27          10
	   1  2  3  4  5  6  7  8  9     5 is a fork: main road (6) or shortcut (27)

	Signature mechanic: the Shortcut toll gate. It saves 8 spaces for 3 coins, but a Switch
	space (17) can close it for everyone, or open it again. Board item: the Gate Key flips
	the gate from anywhere.
]]

return {
	Name = "Classic", -- id: used by Config.Match.Boards and items' Boards lists
	DisplayName = "Sunny Loop", -- shown to players
	-- Beginner board: one loop, one toll shortcut, a single Switch, few Chaos spaces.
	Start = 1,
	CrownSpaces = { 7, 10, 13, 15, 20, 23, 26 },
	Gates = {
		{ Id = "Shortcut", From = 5, To = 27, Open = true, Toll = 3 },
	},
	Spaces = {
		-- bottom row, left to right
		{ Id = 1, Type = "Neutral", At = { 0, 0 }, Next = { 2 } },
		{ Id = 2, Type = "Gain", At = { 1, 0 }, Next = { 3 } },
		{ Id = 3, Type = "Gain", At = { 2, 0 }, Next = { 4 } },
		{ Id = 4, Type = "Item", At = { 3, 0 }, Next = { 5 } },
		{ Id = 5, Type = "Neutral", At = { 4, 0 }, Next = { 6, 27 }, Paths = { "Main road", "Shortcut (toll)" } },
		{ Id = 6, Type = "Lose", At = { 5, 0 }, Next = { 7 } },
		{ Id = 7, Type = "Gain", At = { 6, 0 }, Next = { 8 } },
		{ Id = 8, Type = "Reward", At = { 7, 0 }, Next = { 9 } },
		{ Id = 9, Type = "Gain", At = { 8, 0 }, Next = { 10 } },
		-- right column, upwards
		{ Id = 10, Type = "Gain", At = { 8, 1 }, Next = { 11 } },
		{ Id = 11, Type = "Event", At = { 8, 2 }, Next = { 12 } },
		{ Id = 12, Type = "Shop", At = { 8, 3 }, Next = { 13 } },
		{ Id = 13, Type = "Gain", At = { 8, 4 }, Next = { 14 } },
		-- top row, right to left
		{ Id = 14, Type = "Duel", At = { 8, 5 }, Next = { 15 } },
		{ Id = 15, Type = "Gain", At = { 7, 5 }, Next = { 16 } },
		{ Id = 16, Type = "Lose", At = { 6, 5 }, Next = { 17 } },
		{ Id = 17, Type = "Switch", At = { 5, 5 }, Next = { 18 } },
		{ Id = 18, Type = "Neutral", At = { 4, 5 }, Next = { 19 } },
		{ Id = 19, Type = "Reward", At = { 3, 5 }, Next = { 20 } },
		{ Id = 20, Type = "Gain", At = { 2, 5 }, Next = { 21 } },
		{ Id = 21, Type = "Lose", At = { 1, 5 }, Next = { 22 } },
		{ Id = 22, Type = "Chaos", At = { 0, 5 }, Next = { 23 } },
		-- left column, downwards
		{ Id = 23, Type = "Gain", At = { 0, 4 }, Next = { 24 } },
		{ Id = 24, Type = "Shop", At = { 0, 3 }, Next = { 25 } },
		{ Id = 25, Type = "Lose", At = { 0, 2 }, Next = { 26 } },
		{ Id = 26, Type = "Gain", At = { 0, 1 }, Next = { 1 } },
		-- shortcut up the middle: quicker, but riskier
		{ Id = 27, Type = "Lose", At = { 4, 1 }, Next = { 28 } },
		{ Id = 28, Type = "Event", At = { 4, 2 }, Next = { 29 } },
		{ Id = 29, Type = "Chaos", At = { 4, 3 }, Next = { 30 } },
		{ Id = 30, Type = "Reward", At = { 4, 4 }, Next = { 18 } },
	},
}
