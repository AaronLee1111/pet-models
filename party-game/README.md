# Party Games (working title)

A 4-player party-game prototype for Roblox: lobby vote → arena → 3-2-1 → minigame →
results and coins → back to the lobby. Bots fill any empty seats. The server owns all game
state, and clients only send inputs.

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
2. Press **Play** (F5). You are seated with 3 bots, and the vote opens after about 5 s.
3. To test touch controls: **Test → Device** → pick a phone, then Play.

**Option B: live sync with Rojo**
1. `cd party-game && rojo serve` (uses `default.project.json`, which syncs code only)
2. In Studio, connect with the Rojo plugin, then press Play.
   - With no `SpawnLocation` in the place, a lobby is built automatically.

Rebuild the place file after changing code with `rojo build place.project.json -o MemeParty.rbxlx`.

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

- `lune run tests/sim [seed] [-v]`: headless end-to-end run on a mock engine with virtual time.
  It plays 9 rounds plus a rage-quit and rejoin, and checks phase order, results and coins,
  chips, camera restore, action and spectator UI, arena cleanup, and that nothing errored or warned.
  It's a smoke test only. Real physics, rendering and networking still need a Studio playtest.
- `selene src`: lint against the Roblox API (`selene generate-roblox-std` once to create `roblox.yml`).
