# Sunny Loop v2 — design and pre-production

Status: **pre-production + vertical slice (preview board)**. Not approved, not released.
Board module: `src/server/Board/Boards/SunnyLoopV2.luau` (id `SunnyLoopV2`). The original Sunny Loop
(`Classic.luau`) is unchanged and remains the default; v2 is only offered in Studio when
`Config.Match.ShowPreviewBoards = true`.

Reference: `docs/references/sunny-loop-board-concept-v1.png` (direction only, not geometry).
Route plan: `docs/sunny-loop-v2/route-plan.svg` (drawn from the board data by
`tools/route_plan_svg.py`; rerun it after any route change).

## 1. Direction

A compact floating **sky-garden festival** on one island, around a radiant **Sundial Pavilion**:

| Area | Mood | Signature features |
|---|---|---|
| Orchard (west) | warm, leafy, low | orchard trees, Orchard Market shop, raised Hillside terrace with steps |
| Hilltop Fairground (north) | highest, festive | event stage, Crown Pavilion, fair kiosk, Bell Switch |
| Waterwheel Village (east) | cosy, wet | waterwheel mill, mill dock, terraced descent |
| Stream walk (south) + centre | open, sparkling | stream pool, Sun Gate (start), Sundial Bridge across the middle |

Kept from the reference: curved routes, three areas, central landmark, elevation, integrated round
spaces, physical shops, bright magical sky, complete-world feeling.
Simplified: vegetation density, small props, waterfalls (one, at the stream outlet), secondary
buildings, floating mini-islands (backdrop only, two or three at most).
Not copied: no layout, landmark design or iconography is traced from any existing game; the
concept image's route is reinterpreted as an original 40-space graph.

## 2. Route graph (40 spaces, clockwise)

Main loop: Sun Gate 1 → Stream 2–3 → Orchard 4–12 → Fairground 13–19 → Village 20–26 → Stream 27–29 → 1.

| Fork | At | Routes | Rejoin | Purpose |
|---|---|---|---|---|
| A | 5 (Orchard signpost) | **Market Lane** 6–9 (past Orchard Market shop) / **Hillside Steps** 30–32 (raised terrace: Event, Gift, Duel) | 10 | safe+shop vs risky reward, equal length |
| B | 12 (Bridge gate) | **Fairground Road** 13–24 (12 spaces) / **Sundial Bridge** 33–37 (elevated, toll 3, closable) | 25 | gated shortcut: saves 7 spaces |
| C | 15 (Fair signpost) | **Fair Midway** 16–18 (event stage) / **Crown Terrace** 38–40 (Crown Pavilion, fair kiosk) | 19 | Crown-hunting detour vs Item/Event |

Every space (ID · type · next · area · landmark; h = height in studs):

| ID | Type | Next | Area | h | Landmark |
|---|---|---|---|---|---|
| 1 | Neutral | 2 | Stream | 0 | Sun Gate (Start) |
| 2 | Gain | 3 | Stream | 0 | |
| 3 | Item | 4 | Stream | 0 | |
| 4 | Gain | 5 | Orchard | 0 | |
| 5 | Neutral | 6, 30 | Orchard | 0 | Orchard signpost (fork A) |
| 6 | Gain | 7 | Orchard | 0 | |
| 7 | Shop | 8 | Orchard | 0 | Orchard Market |
| 8 | Lose | 9 | Orchard | 0 | |
| 9 | Gain ♛ | 10 | Orchard | 0 | |
| 10 | Gain | 11 | Orchard | 1 | |
| 11 | Lose | 12 | Orchard | 2 | |
| 12 | Neutral | 13, 33 | Orchard | 3 | Bridge gate (fork B, toll) |
| 13 | Gain | 14 | Fair | 4 | |
| 14 | Chaos | 15 | Fair | 5 | |
| 15 | Neutral | 16, 38 | Fair | 6 | Fair signpost (fork C) |
| 16 | Event | 17 | Fair | 6 | Event Stage |
| 17 | Gain ♛ | 18 | Fair | 6 | |
| 18 | Item | 19 | Fair | 6 | |
| 19 | Switch | 20 | Fair | 6 | Bell Switch |
| 20 | Gain | 21 | Village | 5 | |
| 21 | Lose | 22 | Village | 4 | |
| 22 | Gain ♛ | 23 | Village | 3 | |
| 23 | Gift | 24 | Village | 2 | Waterwheel |
| 24 | Event | 25 | Village | 1 | |
| 25 | Gain | 26 | Village | 0 | (bridge rejoin) |
| 26 | Item ♛ | 27 | Village | 0 | Mill Dock |
| 27 | Lose | 28 | Stream | 0 | |
| 28 | Gain ♛ | 29 | Stream | 0 | |
| 29 | Chaos | 1 | Stream | 0 | |
| 30 | Event | 31 | Orchard | 4 | Orchard steps |
| 31 | Gift ♛ | 32 | Orchard | 6 | Orchard Grove |
| 32 | Duel | 10 | Orchard | 6 | |
| 33 | Lose | 34 | Stream | 6 | Sundial Bridge |
| 34 | Gain | 35 | Stream | 8 | Sundial Bridge |
| 35 | Event | 36 | Stream | 10 | Sundial Pavilion (bridge crown) |
| 36 | Gift | 37 | Stream | 8 | Sundial Bridge |
| 37 | Neutral | 25 | Village | 4 | Sundial Bridge (landing) |
| 38 | Gain | 39 | Fair | 9 | |
| 39 | Neutral ♛ | 40 | Fair | 10 | Crown Pavilion |
| 40 | Shop | 19 | Fair | 9 | Fair Kiosk |

♛ = Crown space (`CrownSpaces = 9, 17, 22, 26, 28, 31, 39`). Gate `SundialBridge`: 12→33, toll 3,
starts open, flipped by the Bell Switch (19) or the Gate Key item.

Type counts: Gain 13, Lose 5, Event 4, Item 3, Gift 3, Chaos 2, Shop 2, Duel 1, Switch 1, Neutral 6 (= 40)
(close to Classic's mix, scaled to 40 spaces).

### Checks (automated: `tests/unit/SunnyLoopV2Tests.luau`, 10 tests, all pass)

- Valid loops: every space reachable from Start and back (BoardLayout validation); one-way edges only.
- Fork reconnection: each fork's two routes meet again before Start (A at 10, B at 25, C at 19).
- Crown reachability: every Crown space reachable from every space with the gate open **and** closed;
  no Crown on a fork or shop.
- Gate: closed → one way on; open → both; Switch and Gate Key flip it; toll charged on the edge.
- Bots: 4 bots × 3 seeds × 12 rounds take **every** fork route, buy Crowns, never get stuck;
  Hard bots take the bridge toward a Crown beyond it and the road toward one before it.
- Geometry: no medallions overlap (except stacked heights ≥ 6 studs), hops 11–26 studs, **no path
  crossings** in plan view, four pieces fit on every medallion without overlap, every slot passes
  the misplaced-piece check (recovery points).
- Movement direction: clockwise; forks present 2 labelled choices with route info (existing UI).
- Camera visibility: checked in Studio (section 6); recovery uses the existing watchdog.

## 3. Landmarks (physical locations)

| Landmark | Spaces | Role | Production |
|---|---|---|---|
| Sundial Pavilion | centre; 35 | hero landmark; the bridge arcs over its dais | Blender hero (Stage 6) |
| Orchard Market | 7 | physical item shop; storefront faces the route | **slice: Studio blockout** → Blender |
| Crown Pavilion | 39 | Crown presentation stage on the upper fair | Blender |
| Waterwheel + Mill Dock | 23, 26 | Gift at the wheel, Item at the dock | Blender |
| Fairground Event Stage | 16 | Event space = stage moment | Blender |
| Fair Kiosk | 40 | second shop (Crown Terrace) | Blender (reuses market kit) |
| Sundial Bridge (gated shortcut) | 33–37 | elevated toll route over the stream | Blender (bridge kit) |
| Bridge Gate | 12 | toll arch with open/closed states | Blender (gate kit) |
| Bell Switch | 19 | Switch landmark: ring the bell to flip the bridge gate | Blender |
| Signposts | 5, 12, 15 | one arrow board per route, pointing at each route's first space | **slice: Studio** |
| Sun Gate | 1 | start arch | Blender |

## 4. Board-space kit (medallion)

| Part | Size (studs) | Owner | Notes |
|---|---|---|---|
| Base | Ø10.5 × 1.2 (top at +1.2) | Blender `PG_Space_Base` (1 mesh, all types; material variants per board) | ceramic + gold rim; only collidable part |
| Inlay | circle Ø7.4 / dot Ø3.2 / ring Ø7.6–4.6 / diamond 5.6 / rounded square 6 | Blender `PG_Space_Inlay_<Shape>` ×5 | **colour set by code** from SpaceTypes |
| Icon insert | 6 × 6 top plate | Blender `PG_Space_Icon_<Type>` ×11 (embossed) | slice uses a SurfaceGui glyph |
| Highlights | ring Ø12 | Roblox (dynamic) | current space, destination, route preview |

Type → shape: Gain circle +3 · Lose diamond −3 · Event circle ? · Item square ITEM · Shop square SHOP ·
Gift ring GIFT · Duel ring VS · Switch ring ⇄ · Chaos diamond ! · Neutral dot. Colour + shape + icon all
differ, so the board stays readable for colour-blind players. Four corner slots at ±2.5 studs fit four
characters (tested). Glyphs face the board camera (south).

Dynamic in Roblox (never baked): inlay colour, highlights, Crown marker, trap/shield markers, gate
state, labels/billboards, SurfaceGuis, piece placement.

## 5. Turn presentation (Presentation = "Diorama")

| Step | What happens | Desktop | Phone |
|---|---|---|---|
| 1 Turn start | camera eases to the active piece, leaning 35% toward the next space | offset (0, 20, 23) | (0, 23, 27) |
| 2 Choices | items + ROLL as today | — | — |
| 3 Roll | player presses ROLL / Space / A | — | — |
| 4 Action | the piece hops (0.3 s) and throws the die toward the camera | — | — |
| 5 Die | tumbles in a 5-stud arc (0.75 s), wobbles until the server's number arrives, settles with the rolled face up and its number upright to the camera | — | — |
| 6 Result | number pops above the die (Back ease), "= total" for multiple dice; dice fade | — | — |
| 7 Movement | camera follows the piece hop by hop | — | — |
| 8 Fork / choice | pull back ×1.45 to frame both routes; aim 9 studs south so the subject sits above the prompt card | — | — |
| 9 Shops, events, gates, Crown | prompt framing ×1.2 + same shift (shop storefront in shot) | — | — |
| 10 After landing | stays on the piece, then the next player's turn eases over | — | — |

MAP stays the whole-board view (higher camera, panned so the board sits right of the MAP panel).
Server timing: `Config.Board.DiceReveal` 1.9 s (players), `DiceRevealBot` 1.25 s (bots, short throw).
Always plays: the die landing and the number. Can be shortened later: the arc (0.75 → 0.5 s), the
hop, and hop time (`HopTime`). Reduced motion: dice appear settled, no hop or tumble.
Turn-order rolls stay instant (four simultaneous rolls).

## 6. Vertical slice (built, preview only)

Built in Studio blockout (`MedallionKit.luau`, `SkyGardenScene.luau`), using the real v2 route:
- whole board as medallions + sandy paths; height changes as chunky stairs (0.8-stud steps);
- placeholder island ground at real heights (terrace columns, rock skirts), stream pool, sundial blockout, bridge piers;
- **orchard slice**: Market Lane + Hillside Steps fork (5 → 6–9 / 30–32 → 10), signpost, raised terrace with rock face, fence between the routes, orchard trees, lamps, and the **Orchard Market** shop (counter, crates, striped awning, sign) facing the shop space;
- Sunny-day lighting preset while the board is shown;
- diorama turn camera, fork/prompt framing, MAP framing, thrown-dice sequence.

Studio results (desktop HD 1080 + iPhone 17 Pro landscape): route reads at a glance; four characters
share a medallion; the fork view shows both routes, the signpost and the market above the prompt; the
shop moment frames the storefront; the die sequence plays for the player and for bots; MAP shows the
whole board beside the panel. Not yet: Blender meshes, icons, the other landmarks, sounds.

## 7. Blender asset plan (Sunny Loop production)

Units 1 stud = 0.28 m; FBX `axis_forward=-Z`, `axis_up=Y`, triangulated; Studio importer turns FBX 180° about Y.
Decor: `CanCollide/CanQuery/CanTouch = false`, `CollisionFidelity = Box`; gameplay positions stay code-driven.
Snapping: 12-stud plan grid (Config.Board.SpaceSpacing); heights in whole studs; path sockets at medallion edges (r = 4.85).

| Group | Size (studs) | Variants | Pivot | Collision | Tris (each) | Material / texture | Owner | Reuse |
|---|---|---|---|---|---|---|---|---|
| Path straight | 4.5 w × 12 / 6 / 3 long | 3 | start-socket centre, top face | none | 150–250 | palette atlas (sand + edging) | Blender | all boards (material swap) |
| Path curve | 4.5 w, 30° / 45° / 90°, r 12 | 3 | start socket | none | 300–500 | palette | Blender | all boards |
| Fork / junction | Y-split, 2 sockets out | 2 | in-socket | none | 400–600 | palette | Blender | all boards |
| Stairs / ramp | 4.5 w, rise 1–4, 0.8 steps | 4 | bottom socket | none | 300–600 | palette (stone) | Blender | all boards |
| Bridge span | 5 w × 12 / 24, arch rise 0–4 | 3 + pier | span centre, deck top | none | 1.5–3k | palette + 512 stone | Blender | festival + future |
| Cliffs / island edge | 12-unit segments, 6–12 tall | 6 (edge, corner in/out, tall, short, cap) | top-outer edge | none | 400–900 | 1024 rock atlas (shared) | Blender | all boards |
| Water / waterfall | pool sheets, 1 fall 6 w × 12 | 3 | top centre | none | 100–400 | Glass/water + Beam foam | Studio + Blender lip | all boards |
| Space base + inserts | §4 | 1 + 5 inlays + 11 icons | top-face centre | base only | 600 / 100 / 300 | palette; tint by code | Blender | **all boards** |
| Fences, lamps, signposts | fence 4-stud bay; lamp 7 tall; sign 8 tall | 2 / 2 / 1 + arrow boards | base centre | none | 150–600 | palette (wood, cream) | Blender | all boards |
| Orchard trees + market props | tree 12–15 tall; crates 2.6 | 3 trees, 4 props | base centre | none | 1.2–2k / 150 | palette (leaf atlas) | Blender | Sunny + lobby |
| Orchard Market shop | 14 × 12 × 11 | 1 | front-floor centre | none | 4–6k | 1024 own | Blender | kiosk variant |
| Waterwheel mill | 18 × 16 × 14 + wheel Ø10 | 1 | floor centre | none | 6–8k | 1024 own | Blender (wheel spins in code) | — |
| Fairground stage + tents | stage 16 × 10; tent 10 Ø | 1 + 2 tents | floor centre | none | 3–5k | palette + fabric | Blender | lobby |
| Sundial Pavilion | Ø22 dais, gnomon 10 tall | 1 hero | dais centre | none | 8–10k | 1024 own (gold, marble) | Blender | — |
| Crown Pavilion | 12 × 12 × 14 | 1 | floor centre | none | 4–6k | palette + gold | Blender | — |
| Gate + Switch props | arch 8 × 7; bell post 7 tall | 2 states / 1 | base centre | none | 1.2k / 1k | palette | Blender | all boards |
| Foliage + rocks | bush 3–5, rock 2–8 | 4 bushes, 4 rocks | base centre | none | 200–800 | palette / rock atlas | Blender | all boards |

Budget for the finished board (phone): ≤ 80k visible tris, ≤ 700 parts, ≤ 6 × 1024 textures + atlases.
Source scripts: `party-game/art/blender/<kit>/*.py` (headless `Blender -b -P`); exports `party-game/art/export/`.

## 8. Next steps

1. Review the slice + route (decisions below), then Blender: space base + inlays + icons, path kit, stairs.
2. Replace slice blockouts with the Blender kit, then build the Orchard area to final.
3. Fairground, Village, Sundial, Crown Pavilion; lighting, sound and dice/hop audio.
4. Swap Classic → v2 only after approval; keep Classic in the repo until then.
