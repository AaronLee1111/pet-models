# Magical Festival Island

A second board selected by the host in the existing waiting room. Module ID: `MagicalFestival`.
Sunny Loop remains the default. This is a functional, editable primitive blockout, not a final art pass.

## Routes and timing

36 spaces: four clockwise eight-space local loops and four spaces on one straight moving bridge.
North is Moonflower Plaza (1–8), east Crystal-Flower Garden (9–16), south Moon-Tree Grove
(17–24), west Lantern Fair (25–32). Spaces 33–36 belong to the rotating assembly.
Everyone normally starts at space 17.

North–south and east–west alignments alternate after each complete board round, before the
minigame. `Bridge.EveryRounds`, `WarningSeconds` and `RotationSeconds` in the board definition
configure this rule (defaults: 1 round, 2-second warning, 1.5-second rotation).
Each movement is exactly 90 degrees; successive rotations reverse direction so moving-space
IDs keep consistent opposite endpoints. The assembly has a single straight deck, not four arms.

Only the aligned pair of docks connects to the bridge. All other exits are removed from
movement, Crown distances, bot planning and route previews. Closed docks show red barriers
and CLOSED text; MAP lists all four exits. There is no walkable disk or underlying base spanning
the gaps. Every local loop remains playable for any roll, in either orientation. Shops, coin
spaces, gifts, events and validated items keep working during isolation.

The server commits alignment, cache invalidation, Crown correction and revision without yielding.
Automatic changes happen only after the turn ends. Moon Dial can act only before rolling.
Warnings and animation run synchronously in the turn driver, so no connection seam can be
crossed during rotation. Board pieces are anchored and server-positioned, including riders
on moving spaces, and released for minigames, duels and lobby cleanup. The existing recovery
watchdog returns misplaced characters to their authoritative spaces. Crown and trap markers
follow their moving spaces. Ready/reconnect state includes the current revision and alignment.

## Moon Dial and Crown fairness

Moon Dial costs 7 coins and appears only in this board's existing item/shop/reward pools.
It rotates early before rolling. The standard ownership, active seat, phase and one-item-per-turn
checks apply. A shared cooldown lasts two automatic intervals. It never cancels or delays an
automatic rotation. This guarantees an uninterrupted scheduled connection window between uses;
players may wait locally instead of spending an item. The cooldown and next alignment are public.

New Crown destinations are chosen from the currently connected zones or the moving bridge.
When a rotation would strand the Crown, `Match:chooseCrownSpace` moves it to a configured Crown
space in a zone that is open after the rotation, applying each filter only if it leaves an
option: prefer newly opened zones; skip spaces and zones used by the last `CrownMemory` (2)
relocations; skip spaces within `CrownLeaderBuffer` (4) moves of the leading player (this one
wins over variety if the previous relocation already landed near the same leader). It then
picks with the match's seeded Rng. Bridge spaces 34 / 35 are only the fallback when no zone
space qualifies. A Crown in a zone that stays connected is preserved. Orientation, Crown and
the route cache change in one step, so routes, bots and every client see the new spot at once.
Disconnected
players have future scheduled access; access is an opportunity, not a guaranteed purchase
before the finite match ends. Dice, route decisions and purchases still matter.

Bots use the live graph for distance and lookahead, and evaluate Moon Dial without changing
live state: affordable Crown progress, distance to the local dock, the next alignment, and a
leading opponent near the Crown. Bots can save the Dial and wait for automatic reconnection.
Existing difficulty-based mistakes and currency reserves remain in effect.

## Editable geometry

`src/server/Board/FestivalScene.luau` builds the fountain, pavilion, moon tree, lantern wheel,
two festival tents and paired shrine gates. Lamps, rocks, crystals, deck rails and island bases
are reused procedural primitives. `BoardWorld.luau` supplies existing colored space tiles.
No uploaded assets, paid assets, external textures, unions or Blender files are required.
The circular mechanism is decorative and noncolliding; the straight deck and local islands
supply simple anchored collision. Decoration has no collision or touch processing.
Board lighting is restored during minigames and cleanup. The festival-only camera keeps the
whole board visible; Sunny Loop camera behavior is unchanged.

## Verification

Run the complete Studio unit suite:

```sh
rojo build tests/unit.project.json -o /tmp/FestivalUnitTests.rbxlx
```

In that place's edit-mode command bar:

```lua
require(game.ServerStorage.PartyTests.RunAll)()
```

Latest result: **132 passed, 0 failed**, including 20 festival tests and 112 existing tests.
Coverage includes all four local loops for 48 moves in both alignments, disconnected exits,
no bypass, graph cache invalidation, round timing, revision snapshots, Crown relocation,
item ownership/stage/cooldown, bots, invalid definitions, moving markers and recovery geometry.

Gameplay harness:

```sh
rojo build tests/festival/festival.project.json -o /tmp/FestivalSmoke.rbxlx
```

Play with one real Studio client for a three-round match with three bots. The harness selects
this board through the real lobby input, rolls, tries Moon Dial, submits invalid and valid
prompt answers, and reports final counters. It deliberately starts test pieces on bridge
space 34 to exercise riders and uses faster board timings. These overrides are **not mapped
into `place.project.json` or the playable `MemeParty.rbxlx`**.

For two clients, in the harness place's edit-mode command bar (keep the Mac awake and
unlocked, with the test server window in front: Studio throttles background test windows to a
crawl, and a locked screen throttles all of them):

```lua
task.spawn(function()
    print(game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, {}))
end)
```

The `[FestivalSmoke]` report and `Workspace.FestivalReports` contain each client's counters.
`Passed` requires final standings, at least three automatic rotations, at least one extra
rotation and an observed rider. The two-client run ends after both clients report.

## Integration

Review branch `astra/magical-festival-island` in `/Users/aaronlee/Projects/magical-festival-island`.
Do not merge by overwriting the other checkout. Preserve its uncommitted phone-camera changes:
commit or stash those there first, review conflicts (particularly BoardView and Config), then
merge this branch. Re-run the unit suite and the festival smoke project after resolving conflicts.
Rebuild with `rojo build place.project.json -o MemeParty.rbxlx`. No Roblox publishing is needed.

### Merge preview (checked 2026-10-16, not merged)

`git merge-tree` against `claude/optimistic-bohr-pcrxph` (4239833) shows two conflicts:
- `MemeParty.rbxlx`: take either side, then rebuild it from the merged source.
- `BoardView.luau`, camera block in `BoardView:show()`: main added a touch-only play offset
  (`TOUCH_CAMERA_OFFSET` + `UserInputService`, committed in 4910ed2 together with the shop
  REMOVE fix). Keep both: festival framing first, then main's touch offset for other boards:
  ```lua
  local offset = if self.MapOpen then MAP_OFFSET
      elseif UserInputService.TouchEnabled then TOUCH_CAMERA_OFFSET
      else CAMERA_OFFSET
  if festival then
      -- festival whole-board framing (unchanged from this branch)
  end
  camera.CFrame = CFrame.lookAt(self.Focus + offset, self.Focus)
  ```
  and keep main's `UserInputService` and `TOUCH_CAMERA_OFFSET` declarations.
After resolving: run the unit suite and the festival harness, then rebuild the place.

### Recorded Studio checks (2026-10-16)

- Complete unit suite: 132 passed / 0 failed; festival subset: 20 passed / 0 failed.
- One Studio player + three bots: three-round match reached final standings; five rotations
  total, three automatic, Moon Dial exercised, moving-platform riders observed; harness Passed=true.
- Forced recovery: server moved the anchored player 80 studs below the board; the watchdog
  restored the player to a valid height. No task-related game-script errors in the server log.
- Fresh Ready request returned 36-space layout, current revision/alignment, next alignment,
  all four dock states and cooldown, rather than resetting to the initial orientation.
- Desktop and iPhone 17 Pro landscape checked in play mode. Whole-board geometry and MAP
  were visible without clipping the near island. MAP showed closed local loops and the next
  alignment. Phone MAP button is approximately 48 points high; roll approximately 83 points.
  Studio device simulation was reset to the default viewport afterward.
- Two-client harness, first attempt: both client processes launched but only one joined the
  server; the run ended INCOMPLETE (see the 2026-10-16 review below for the cause and the pass).
- Lune is not installed in this environment. The mock-engine headless simulation was not run;
  real Studio unit tests and gameplay runs were used instead. No dependencies were installed.
- Studio emitted unrelated CorePackages/UIBlox and existing asset-type warnings. These are
  outside this board's source and were not changed.

Fixed during verification: camera framing was too distant; Crown/trap markers now follow
moving spaces throughout rotation; closed docks now have physical red barriers and tile text,
and the turn header explicitly identifies isolation. Sunny Loop regressions remained green.

### Review and two-client verification (2026-10-16)

Reviewed both Astra commits against the intended mechanic:
- One straight two-ended deck (33–36); only N–S (docks 1 + 17) and E–W (docks 9 + 25).
  `RotatingBridge.options` removes the closed docks' bridge edges in both directions, so
  rotation changes the live graph; `Bridge.validate` rejects any zone edge that bypasses the
  bridge; every dock keeps its local-loop edge, so no zone is a dead end.
- Pieces are anchored on this board and moved only by the server; the recovery watchdog
  restores misplaced pieces; riders are re-placed every frame of the rotation.
- Crown: a Crown in a zone about to close moves to bridge space 34 (35 if already there);
  relocation only picks connected zones or the bridge, so it is always reachable.
- Moon Dial goes through `Match:useItem` (turn, stage, one per turn, ownership, board) and
  `useMoonDial` (shared cooldown); a refused Dial is kept.

Fixed: on the two-way bridge a mover was offered the space they had just come from
(1 → 33 → 1, 33 → 34 → 33), letting them hover around the Crown and bots dither. Within one
move the previous space is no longer offered unless it is the only way on (new unit test).

Results:
- Unit suite: **133 passed, 0 failed** (21 festival tests).
- Two-client run (one local server, two real Studio clients, two bots, 3 board rounds):
  `TWO-CLIENT PASS: sameTimeline=true sameStandings=true bothAlignments=true gaps=0/0`.
  Both clients saw the same five rotations (E–W, N–S, E–W, N–S, E–W: Moon Dial in round 1 plus
  three automatic) with the same Crown space at each, identical final standings, riders on the
  moving deck, and zero dock-to-bridge hops through a closed dock. Server log: only the
  pre-existing asset-type warning. Client consoles weren't readable after the test closed
  them; the clients' own reports carried no errors.
- Why the first attempt failed: Studio throttles background test windows (and every window
  while the screen is locked) to a crawl. The match only advanced at full speed while the
  server window was in front or being queried. Not a project-code problem.
- iPhone 17 Pro landscape: whole board framed; header shows current → next alignment; MAP lists
  Crown space, alignment, next rotation, Moon Dial readiness and each dock OPEN / EXIT CLOSED;
  MAP panel (y 112–307) clears the CLOSE button (313–360) and the top bar (58). Desktop
  (1301×616): whole board framed, header and MAP usable.

Design notes: the Crown used to land on bridge space 34 at every rotation (fair but
repetitive); since the relocation change it moves into a newly opened zone instead. The board renders small on phones because the camera
frames the whole island.
