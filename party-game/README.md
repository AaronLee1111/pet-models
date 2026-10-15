# Party Games (working title)

A 4-player board-and-minigame party game for Roblox. A match goes:

waiting room (the host picks rounds and bot difficulty) → **board rounds** (each seat rolls a die,
moves and resolves the space it lands on) → a **minigame** after every full turn cycle → repeat for
the chosen number of rounds → **final standings** (most Crowns wins, coins break ties) → back to
the waiting room. Bots fill empty seats and take over from players who leave. The server owns all
game state; clients only send inputs.

Six placeholder minigames exercise the framework:

| Minigame | Layout | Camera | Controls | Chips show |
|---|---|---|---|---|
| Hot Potato | FFA | AngledOverhead | move + jump, **Pass** (E / ButtonX / on-screen) | 🥔 HOT / 😎 safe / 💥 |
| Falling Platforms | FFA | FollowBehind | move + jump, no actions | seconds survived |
| Mash Dash | 2v2 | SideView | **movement locked**, **Mash** (Space / ButtonA / on-screen) | % of track |
| Kernel Catch | FFA | AngledOverhead | move + jump, no actions | 🍿 popcorn caught |
| Ice Dash | FFA | FollowBehind | **auto-forward**, hold **◀ / ▶** to steer (A/D, arrows, on-screen) | race bar along the top |
| Pole Shimmy | FFA | SideView (follows you up) | **movement locked**, alternate **LEFT / RIGHT** (A / D, on-screen) | height % |

## Play it in Studio (1 real player + 3 bots)

**Option A: open the prebuilt place (no plugins needed)**
1. Open `party-game/MemeParty.rbxlx` in Roblox Studio.
2. Press **Play** (F5). The waiting room counts down 15 s (as host you can change the settings or
   press START), then you're seated with 3 bots on the board. Press ROLL (or Space) on your turn.
3. To test touch controls: **Test → Device** → pick a phone, then Play.

**Option B: live sync with Rojo**
1. `cd party-game && rojo serve` (uses `default.project.json`, which syncs code only)
2. In Studio, connect with the Rojo plugin, then press Play.
   - With no `SpawnLocation` in the place, a lobby is built automatically.

Rebuild the place file after changing code with `rojo build place.project.json -o MemeParty.rbxlx`.

## Board game

| Piece | File |
|---|---|
| Match loop (waiting room → match → back) | `src/server/Main.server.luau` |
| Waiting room + host settings | `src/server/WaitingRoom.luau` |
| Turns, timing, prompts, bots, seats, world | `src/server/Board/BoardGame.luau` |
| Rules only (testable): movement, forks, collectible, shop, rewards, standings | `src/server/Board/Match.luau` |
| Board layouts | `src/server/Board/Boards/*.luau` |
| Space types (look + effect) | `src/server/Board/SpaceTypes.luau` |
| Events | `src/server/Board/Events.luau` |
| Items / bot decisions | `src/server/Board/Items.luau`, `src/server/Board/BotBrain.luau` |
| Coins + Crowns wallets (per match) | `src/server/CoinService.luau` |
| Cosmetic catalog / ownership / drawing | `src/shared/Cosmetics.luau`, `src/server/Inventory.luau`, `src/server/CosmeticService.luau` |
| Permanent profiles | `src/server/Profiles/` |
| Prices, rewards, timings, round counts | `Config.Match`, `Config.Board`, `Config.Collectible`, `Config.Economy` |
| Client UI | `src/client/UI/BoardView.luau`, `LobbyPanel.luau`, `StandingsScreen.luau` |

Crowns are the placeholder name for the main collectible (`Config.Collectible`). Passing or
landing on the Crown's space offers it for `Price` coins; after a purchase it moves to another of
the board's `CrownSpaces`. Coins and Crowns reset every match. Cosmetics and bank coins live in
the player's profile.

### Add a board
1. Copy `src/server/Board/Boards/Classic.luau` to e.g. `Beach.luau`.
2. List the spaces: `{ Id, Type, At = { x, z }, Next = { ids }, Paths = { labels }? }`. Two or
   more `Next` entries make a fork; the mover picks (bots pick at random).
3. Set `Start` and at least two `CrownSpaces`.
4. Set `Config.Match.Board = "Beach"`. A broken board stops the match with a message saying
   exactly what's wrong (dead end, missing space, unreachable space, unknown type...).

### Add a space type
Add an entry to `src/server/Board/SpaceTypes.luau` with `Name`, `Short` (tile text), `Color`
and `Resolve(match, seat, space) -> feed text`, then use its key in a board. Resolve can use
`match:changeCoins`, `match:runEvent`, `match:giveReward`, `match:visitShop`,
`match:grantCosmetic`, or ask the player something with
`match:ask(seat, { Kind, Prompt, Options, Default })`. Give bots an answer for a new `Kind` in
`Match:botDecision`.

### Add an event
Append `{ Id, Name, Weight, Apply = function(match, seat, rng) return "feed text" end }` to
`src/server/Board/Events.luau`. If it moves pieces (changes `seat.SpaceId`), BoardGame redraws
them after the landing.

### Turn order
Before round 1 everyone rolls once (players press ROLL, bots roll automatically, anyone who
doesn't press in `Config.Match.OrderRollTimeout` rolls automatically). Highest goes first; tied
seats roll again among themselves until nobody is tied (`Match:decideTurnOrder`).

### Board items
Each seat holds up to `Config.Items.MaxHeld` items (they stay with the seat if a bot takes
over). On your turn, before rolling, tap one item button (or a bot decides); `Match:useItem`
checks turn, timing, one-per-turn, ownership and the target for players and bots alike. Items
come from Gift spaces (`Kind = "Item"` reward), the Item Drop event and the shop.
`Config.Items.StartingItems` hands everyone items at the start (handy for testing).

### Add an item
1. Append to `src/server/Board/Items.luau`:
   `{ Id, Name, Description, Price, Weight, Dice?, Target? = "Opponent", Use = function(match, seat, target) return "feed text" end }`.
   Return `nil, "reason"` from `Use` to refuse (the item is kept). `Dice = n` rolls n dice this turn.
2. Tell bots when it's worth using in `BotBrain.itemScore` and its shop value in `BotBrain.ItemValue`.
3. Add a test in `tests/unit/BoardTests.luau` (the "every item" test checks the fields).

### Bonus awards
After the last round: standings before bonuses -> bonus card -> final standings. Bonuses are
`Config.Bonuses` (`Stat`, `Crowns`, `AwardTies`); stats are tracked on each seat by Match:
`MinigamePoints` (`Config.MinigamePointsByPlacement` per minigame), `CoinsEarned` (every coin
gained on the board or in minigames, never reduced by losses or spending) and `SpacesMoved`
(warps and swaps don't count). A bonus whose best value is 0 goes to nobody.

### Bots
`src/server/Board/BotBrain.luau`, tuned per difficulty in `Config.Match.BotBehavior`
(random-choice chance, item-use chance, Crown savings, fork look-ahead, cosmetic spending).
Bots see only what players see: Crown position and price, board distances, coins,
standings and round. They never read upcoming dice or rewards. All their item uses go through
`Match:useItem`, same as players.

### Add a cosmetic
Append to `src/shared/Cosmetics.luau`:
`{ Id, Name, Slot, Price, Rarity, Visual = { Kind = "Hat" | "Trail" | "Sparkles", ... } }`
(`Slot` must be one of `Cosmetics.Slots`; see the comment there for each `Visual` shape). Shops
and Gift spaces offer it automatically, and CosmeticService draws it. Never reuse or rename an
`Id`, because players' saved profiles refer to it. A new `Visual.Kind` needs a drawer in
`CosmeticService` (`drawers` table).

Equipping: clients send `Equip { ItemId }` / `Unequip { Slot }`; `Inventory.equip` refuses
anything unowned. The waiting room shows a wardrobe row. CosmeticService redraws any character
whose drawn set doesn't match its owner's (respawns, teleports, bot takeovers all heal on their own).

### Profiles (permanent data)
`src/server/Profiles/`: `ProfileStore` (data shape `{ Version, Coins, Owned, Equipped }`,
`reconcile` for repairs/migrations), `MemoryBackend` (Studio and tests) and `DataStoreBackend`
(**not enabled**: it refuses to read/write). `Profiles` (init) loads on join, gives the profile's
cosmetic tables to Inventory, and saves on leave and in `BindToClose`.

- Match coins, Crowns, items and stats are never stored in a profile. The only thing a match
  writes is permanent bank coins (`Config.Profile.BankCoinsByPlacement`), added at the final standings.
- To turn on real saving: finish `DataStoreBackend.read/write` (instructions in that file:
  `GetAsync`/`UpdateAsync`, retries, session locking, autosave), then set
  `Config.Profile.Backend = "DataStore"`. Nothing else changes.

### Rewards and prices
Gift-space rewards (`Config.Economy.Rewards`, weighted), coin space amounts, starting coins,
the Crown price, item prices (`Items.luau`), shop offer counts and bank coins are all in
`src/shared/Config.luau`.

## Where things live

```
ReplicatedStorage/PartyShared      (src/shared)  Config (all tuning: timings, coins, cameras), Net (remotes + message names)
ServerScriptService/PartyServer    (src/server)
  Main.server         party loop: seat players, fill with bots, run rounds
  MinigameManager     vote → instructions → countdown → play → results → lobby
  MinigameInfo        validates minigame modules + fills Info defaults
  RoundContext        the per-round toolbox minigames get (Eliminate, ReportProgress, …)
  BotService          bot bodies + think loop that calls each minigame's UpdateBot
  Participant         one seat: wraps a real Player or a Bot behind one API
  Arena / CoinService / ResultsUtil
  Minigames/          one ModuleScript per minigame (_Template is ignored)
StarterPlayerScripts/PartyClient   (src/client)
  Main.client         renders server state, sends inputs
  CameraController    per-player Scriptable camera + spectator orbit
  Controls            key/gamepad binds, on-screen buttons, movement lock
  UI/                 vote, instructions, HUD (timer, banner, toasts), player chips, action bar, spectator bar, results
```

Coins by placement are set in `Config.CoinsByPlacement = { 10, 6, 3, 1 }`. Ties share a placement and its coins.

## Adding a new minigame

1. Copy `src/server/Minigames/_Template.luau` to e.g. `src/server/Minigames/CoinRush.luau`.
   Files starting with `_` are ignored, so the copy shows up in the vote automatically.
2. Fill in `Info`:
   ```lua
   Info = {
       Name = "Coin Rush", Description = "...", Duration = 60,
       Layout = "FFA",                                 -- "FFA" | "1v3" | "2v2"
       Camera = { Mode = "AngledOverhead" },           -- or "FollowBehind" | "SideView" (+ Height/Distance overrides)
       Controls = {
           Move = true, Jump = true, WalkSpeed = 16,   -- Move=false locks walking (server-enforced)
           Actions = { { Action = "Grab", Label = "Grab!", Key = "E", Gamepad = "ButtonX" } },
       },
       ProgressLabel = "Coins",                        -- caption under each player chip
   }
   ```
3. Implement the functions. Per-round state goes on `self`, because each round gets a fresh instance.
   - `Setup(arena, participants, round)`: build the map in `arena.Folder` around
     `arena.Origin`, and return one spawn `CFrame` per participant.
   - `Start()`: connect loops; players are unfrozen.
   - `OnInput(participant, action)`: an action from a player *or* a bot. It has
     already been validated against `Info.Controls.Actions`.
   - `UpdateBot(bot, dt)`: bot brain. Use `bot:MoveTo(pos)`, `bot:Jump()`,
     `bot:Input("Grab")`, `bot.Memory`, `bot.Skill`.
   - `GetResults()`: ranked table. Use `ResultsUtil.fromScores`, `fromElimination(self.Participants, self.Round)`
     or `fromTeams`.
   - `Cleanup()`: disconnect everything; `arena.Folder` is destroyed for you.
   - Optional: `OnParticipantLost(p, "Died"|"Left")` and `OnRoundEnding("TimeUp"|reason)`.
4. Inside the game, use `self.Round`:
   - `ReportProgress(p, value, label?)` updates chips.
   - `Eliminate(p)` sends the player to the spectator box, and their client switches to the spectator camera.
   - Other calls: `End()`, `Toast(text)`, `SetStatus(text)`, `GetAlive()`, `GetTeam(n)`.
5. Run `lune run tests/sim` (it plays every registered minigame with 1 fake player + 3 bots),
   then Play in Studio.

If a module is broken (missing a function, bad `Layout`/`Camera`), the server prints
`[MinigameManager] Skipping minigame X: <why>` and the rest of the game keeps working.

## Testing under lag

Ice Dash moves each player's racer on their own client and smooths everyone else, so it
needs checking with real latency. `tests/lag` builds a place with a small measuring harness:

1. `rojo build tests/lag/lag.project.json -o LagTest.rbxlx` (delete the other minigame
   modules from a copy first if you want Ice Dash every round).
2. Quit Studio, set `IncomingReplicationLag` (seconds, each way) in
   `~/Library/Roblox/GlobalSettings_13.xml` (Studio Settings > Network on Windows), reopen
   Studio with the place. Studio only reads the value at startup.
3. In the command bar: `print(game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2))`.
   One server and two clients play a round; the result lists, per client, how smoothly its
   own racer, the other player and a bot were drawn, plus input latency.
4. Keep Studio in the foreground while it runs: background windows are throttled to ~15 fps.
5. Set `IncomingReplicationLag` back to 0 afterwards.

## Tests and lint

- Unit tests (board rules, turn order, items, bonuses, bot decisions, cosmetics, profiles):
  `rojo build tests/unit.project.json -o UnitTests.rbxlx`, open it in Studio and run
  `require(game.ServerStorage.PartyTests.RunAll)()` in the command bar (edit mode is fine).

- `lune run tests/sim [seed] [-v]`: headless end-to-end run on a mock engine with virtual time.
  It plays 9 rounds plus a rage-quit and rejoin, and checks phase order, results and coins,
  chips, camera restore, action and spectator UI, arena cleanup, and that nothing errored or warned.
  It's a smoke test only. Real physics, rendering and networking still need a Studio playtest.
- `selene src`: lint against the Roblox API (`selene generate-roblox-std` once to create `roblox.yml`).
