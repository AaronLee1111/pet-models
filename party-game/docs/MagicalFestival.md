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
Before a rotation, a Crown in a zone that will close moves to configured bridge space 34
(or 35 when appropriate). A Crown in a zone that stays connected is preserved. Disconnected
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

Latest result: **132 passed, 0 failed**, including 21 festival tests and 111 existing tests.
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

For two clients, in the harness place's edit-mode command bar:

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
