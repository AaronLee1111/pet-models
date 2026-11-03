# Party Game Item Kit: review stage 1

This is the first review set of a reusable 3D item kit for the Roblox party game. It covers three representative items that set the shared visual language for physical shop and inventory items:

| Item | Root / pivot | Meshes | Triangles | Size (studs, W × D × H) |
|---|---|---|---|---|
| Party Dice Block | `PartyDiceBlock`: geometric centre | Body, Faces, Pips | 7,860 | 3.53 × 3.53 × 3.56 |
| Coin Shield | `CoinShield`: centre of the coin boss | Body, Coin | 4,316 | 2.98 × 1.05 × 3.66 |
| Warp Token | `WarpToken`: portal centre | Ring, Portal | 4,828 | 3.29 × 0.62 × 3.29 (incl. spikes) |

All three are under the 8,000-triangle preference, well under Roblox's 20,000 limit, and use 2–3 meshes each. They share **one material and one 1024² atlas**.

> **Status:** this is review stage 1 only. Nothing has been imported, uploaded or published, and no game files were touched. **Remaining items are on hold until these three get visual approval.**

## Layout

```
PartyGameItemKit/
  source/build_item_kit.py            procedural Blender build (single source of truth)
  source/PartyGameItemKit_v001.blend  versioned Blender source (items + review helpers)
  export/PartyDiceBlock_v001.fbx      candidate FBXs (root Empty + mesh children, atlas embedded)
  export/CoinShield_v001.fbx
  export/WarpToken_v001.fbx
  textures/PGK_Atlas_Color.png        sRGB  -> SurfaceAppearance.ColorMap
  textures/PGK_Atlas_Roughness.png    linear -> RoughnessMap
  textures/PGK_Atlas_Metalness.png    linear -> MetalnessMap
  textures/PGK_Atlas_Emissive.png     linear mask -> EmissiveMaskContent (tint = white, see below)
  textures/PGK_Atlas_Legend.png       atlas cells labelled
  manifest.json                       mesh/material manifest, tri + mesh counts, bounds, checks
  validation/fbx_roundtrip.json       FBX re-import validation
  renders/01..10_*.png                review renders
```

To rebuild everything (deterministic), run `python3 PartyGameItemKit/source/build_item_kit.py` with `pip install bpy`, or `blender -b -P ...`. Setting `KIT_STAGE=geo` skips the renders.

## Shared kit language

Every item is built from the same layered recipe, from the outside in:

1. **Warm-gold structure.** The outer frame is metal gold (roughness ≈ 0.25) with chunky rounded bevels. Recessed walls use a darker **satin gold** so the layers separate.
2. **Cream enamel step.** A cream band sits one step below the gold: the rims on the die faces, the band on the shield, and the keystones on the token.
3. **Saturated enamel inset.** The colour field sits one more step down: cobalt for dice, teal-to-cobalt for the shield, violet for the token.
4. **Hero detail.** Pips, the coin boss or the portal sits proud of the enamel inside a gold bezel.
5. **Gem accents.** Small faceted diamonds in gold settings: coral on dice, aqua (softly emissive) on the protective and magic items.

The step heights are shared across all three items, so bevels and detail density match: gold ≈ +4.5 cm, cream ≈ +3 cm, enamel ≈ +1.8 cm. Every layer is its own closed shell, offset from its neighbours. No decal sits flat on another surface, and the build checks this automatically (`coplanar_overlap_pairs: 0` for every item).

### Item notes

- **Party Dice Block.** A bevelled cube (not a sphere) wears a gold bezel frame on each face around a cream rim and cobalt enamel. The pips are pearl domes in gold bezels, and opposite faces sum to 7. A teal four-point star sits under each centre pip on the 1, 3 and 5 faces. Coral gems on the 12 edges and cream caps on the 8 corners give the die a lumpy, readable silhouette while it tumbles.
- **Coin Shield.** Recognition comes from the silhouette alone, with no text. A gold frame surrounds a cream band and a teal-to-cobalt field. A reeded gold coin with a raised eight-point star and an aqua heart is seated in a cream collar, and four gold straps tie the coin into the frame. That makes the coin the shield's boss rather than a sticker. Aqua gems sit at the four frame points. The back is cream with a gold grip and brackets. It is about 1 stud thick, so it reads from gameplay distance.
- **Warp Token.** It stands upright and is deliberately not coin-like: four gold compass spikes break the circle. Stepped gold rings surround a violet band with cream keystones. The front portal is a recessed bowl with an emissive spiral, four gold-edged teal vanes and a glowing core. The back has a gold cross with aqua light strips. The `Portal` mesh is separate, so it can counter-spin.

## Atlas, materials, texel density

- One material, `PGK_KitAtlas`, which maps to one `SurfaceAppearance` per MeshPart. All items reuse the same four maps.
- The atlas is a 4×4 grid of 256 px **material cells**, listed below. The last row is reserved for variant enamels:

  | | col 0 | col 1 | col 2 | col 3 |
  |---|---|---|---|---|
  | row 0 | GOLD | GOLD_SATIN | CREAM | PEARL |
  | row 1 | COBALT | TEAL | VIOLET | FIELD (shield gradient) |
  | row 2 | CORAL gem | AQUA gem | PORTAL spiral | CORE glow |
  | row 3 | RUBY *(reserved)* | EMERALD *(reserved)* | SUN *(reserved)* | ROSE *(reserved)* |

- **UVs.** Each face is box-projected in its item's root space into its class cell, using a 10 px gutter. FIELD, PORTAL and CORE are projected through the item front, so the shield gradient and the portal spiral line up with the model. Because many faces share texels inside a cell, this works like a trim or palette atlas. It is intentional: it keeps the mottling consistent and lets any item recolour by moving UVs to another cell. Crisp detail (pips, bezels, gems) is modelled geometry, not texture.
- **Texel density.** It is identical for every item: 210.7 px/m (59.0 px/stud).
- **Emissive.** `PGK_Atlas_Emissive.png` is a restrained mask: portal arms and core reach about 1.0, aqua gems about 0.6, coral gems 0.15, the shield field 0.05, and everything else 0. In Roblox, use it as `EmissiveMaskContent` with `EmissiveTint` white (the colour comes from the ColorMap) and a modest `EmissiveStrength` (about 1–2).
- The FBXs embed the colour map only. Apply the full PBR set through SurfaceAppearance.

## Scale and pivots

Scale is 1 stud = 0.28 m in Blender, the same convention as the rest of this repo. FBXs are exported with `FBX_SCALE_UNITS`, −Z forward and Y up.

| Item | Pivot (root Empty) | Animation guidance |
|---|---|---|
| PartyDiceBlock | Geometric centre (bbox centre offset ≈ 0) | Tumble on any axis. For a rest pose, put a face up and rest at half-height (≈ 1.78 studs) above the surface. |
| CoinShield | Centre of the coin boss, slightly above the bbox centre | Hover-spin about world up. Bob around 2.5–3 studs above the pickup space. |
| WarpToken | Portal centre = bbox centre | Spin about world up. Optional counter-spin of `WarpToken_Portal` about the token's facing axis. Both meshes share the root pivot, so no offset is needed. |

All mesh children have **identity local transforms** relative to their root. In the `.blend`, the roots are moved onto the review pedestals. The build script zeroes each root before export, so every FBX root sits at the origin with no rotation or scale.

The `Review_Helpers` collection holds the R15 reference figure (5.2-stud blocky R15) and the shop pedestals (4.5 studs Ø × 1.6 studs). It is **never exported**, and the round-trip check confirms that no helpers are present.

## Validation (see `manifest.json`, `validation/fbx_roundtrip.json`)

The checks run per mesh on every build:

- Closed-shell orientation (signed volume > 0 per shell) gives **0 inverted shells**, so normals are correct.
- Non-manifold edges: **0**. Degenerate triangles: **0**.
- Same-facing coplanar faces between different shells within 4 mm (z-fight risk): **0**.
- The FBX round trip re-imports each FBX into an empty scene. The triangle counts match the source, the bounds match within 2 mm, there is one root, every mesh has a UV layer, there is exactly one material, the mesh local transforms are identity and no helpers are present. Result: **pass for all three**.

## Future variants (not built yet; waiting on approval)

These reuse the dice construction with no new modelling of the base:

- **Double Dice:** the same body and faces with enamel moved to the RUBY or ROSE cell. Add one extra gold band (a second bezel step) or swap the edge gems to the larger shield setting so it feels physically heavier. Can be shown as a pair.
- **Triple Dice:** SUN enamel with gold-on-gold faces and a cream "×3" pip arrangement (pip layout only, no text). Scale about 1.05× to feel more powerful.
- **Lucky Die:** EMERALD enamel, with the corner caps swapped for aqua glowing gems (AQUA cell) and a restrained emissive pulse.
- **Controlled-roll dice:** the face meshes are separate, so specific faces can carry custom pip layouts (`PIP_LAYOUT`) or a single highlighted face in TEAL.
- **Shield and token tiers:** move FIELD/VIOLET to a reserved enamel cell and add a third gem tier.

Recolouring is a UV offset into another cell (or a duplicated cell), so the kit stays on one atlas.

## Review stage 2: dice family (v002)

Built by `source/build_dice_family_v002.py`, which imports `build_item_kit.py` as a library. It does **not** re-run the v001 build. Every v001 file (sources, FBXs, atlas, manifest, round-trip report, renders) is hash-checked at the end of each v002 build and is byte-identical (`manifest_v002.json → v001_files_unchanged: true`).

### Items

| Item | FBX hierarchy | Triangles per mesh | Total | Size (studs, W × D × H) |
|---|---|---|---|---|
| Double Dice | `DoubleDice_Root` → `Die_A`, `Die_B`, `Connector` | 6,556 / 6,556 / 1,080 | 14,192 | 4.47 × 5.15 × 4.31 |
| Triple Dice | `TripleDice_Root` → `Die_A`, `Die_B`, `Die_C`, `Connectors` | 6,556 ×3 / 1,896 | 21,564 | 5.12 × 2.89 × 5.05 |
| Lucky Die | `LuckyDie_Root` → `LuckyDie` | 7,876 | 7,876 | 3.55 × 3.55 × 3.57 |

- Every die mesh is under 8,000 triangles, and no mesh is near the 20,000 limit. Triple Dice exceeds 20k only as a package of four valid meshes.
- One material slot per mesh. UVs are inside 0–1.
- Each Blender object is named `<Item>_<Part>` (for example `DoubleDice_Die_A`). The export renames them to the hierarchy names above, which are what the FBX contains.

### Reused vs new geometry

- **Family die (new, optimised):** the exact v001 Party Dice Block recipe and dimensions (bevelled gold cube, gold bezel, cream rim, inset enamel, pearl pips in gold bezels, star under the centre pips, 12 coral edge gems, 8 cream corner caps), with fewer segments:
  - bevel: 3 segments
  - bezel and rim corners: 3 segments
  - pips: 10 segments (the big 1-pip keeps 14)
  - corner caps: 10 segments

  This takes the die from 7,860 to 6,556 triangles (−17%). The die is built once per enamel colour and placed in Double and Triple. The v001 Party Dice Block export is untouched.
- **Lucky Die:** the family die at the Party Dice scale (0.90) with premium options:
  - a taller, wider gold bezel (+1.2 cm high, +1.3 cm wide)
  - emerald enamel and mint stars
  - mint edge gems, plus faceted mint gems replacing the cream corner caps
  - a gold **fortune medallion** set into the bottom of every face frame, with four emerald leaf lobes. It is an original motif: no text, nothing copied.
  - two glowing gold flourishes along the cream rim on each face
  - 9-segment pips to stay under 8k
- **New connectors:**
  - Double: two tapered gold orbit arcs with aqua diamond nodes.
  - Triple: a three-arc gold ring just behind the dice, with coral nodes, a teal-and-gold star hub with a pearl, and one bar up to the ring top. A three-spoke hub was avoided because it reads as a car logo.
  - The arc spans are computed from the real die geometry, so the connectors never touch a die.

### Pivots

All dice and connector objects carry **translation only**. Rotation and scale are applied into the mesh, so each object origin is the die's tumble pivot.

| Item | Root pivot | Die pivots (m, root space; 1 stud = 0.28 m) | Rest pose baked into mesh |
|---|---|---|---|
| Double Dice | Midpoint of the two dice (bbox centre ±3 mm) | A (−0.25, 0.34, 0.25), B (0.25, −0.34, −0.25) | A Rz 12° Rx −6° (5 forward); B Rz −14° Rx 6° + face turn −90° (3 forward) |
| Triple Dice | Triangle centroid (bbox centre is 13 cm higher because of the top die) | A (0, 0.03, 0.50), B (−0.38, 0, −0.25), C (0.38, 0, −0.25) | A Rx −8°; B Rz 8° Rx −4° (coral, 3 forward); C Rz −8° Rx −4° (turquoise, 4 forward) |
| Lucky Die | Die centre (same as Party Dice Block) | (0, 0, 0) | none |

Clearances are measured vertex-to-surface between meshes:

- Double: die–die 8.2 cm, connector–die ≥ 6.9 cm.
- Triple: die–die ≥ 8.5 cm, connector–die ≥ 5.4 cm.
- Mesh-pair intersections: 0.

So dice can separate, tumble on their own pivots and reunite without passing through the connectors at rest.

### Atlas v002

`textures/PGK_Atlas_v002_{Color,Roughness,Metalness,Emissive,Legend}.png`: same 1024² size, 256 px cells, gutter, projection and texel density (210.7 px/m, 59 px/stud).

- Cells 0–11 and EMERALD are regenerated from the v001 code and seeds, and are **pixel-identical** to the v001 atlas (checked for all four maps).
- The reserved v001 row is now used:

  | row 3 | col 0 | col 1 | col 2 | col 3 |
  |---|---|---|---|---|
  | v001 | RUBY *(reserved)* | EMERALD *(reserved)* | SUN *(reserved)* | ROSE *(reserved)* |
  | v002 | **CORAL_ENAMEL** | EMERALD | **MINT** gem (emissive ≈ 0.45) | **GOLD_GLOW** (metal, emissive 0.35) |

- Turquoise uses the existing TEAL cell, and the turquoise die's centre stars use COBALT for contrast.
- v001 items never sample row 3, so the v002 maps are a drop-in replacement for the whole kit. One SurfaceAppearance set covers all six items.

### Validation (`manifest_v002.json`, `validation/fbx_roundtrip_v002.json`)

| Check | Result |
|---|---|
| FBX round trip, all three files | **Pass**: hierarchy and names, mesh count, per-mesh triangles, bounds within 2 mm, pivots within 2 mm, local rotation and scale identity, one UV layer in 0–1, one material slot, no helpers |
| Inside-out shells | 0 |
| Open edges | 0 |
| Degenerate triangles | 0 |
| Coplanar overlaps | 0 |
| Mesh intersections | 0 |
| Missing files / renders | 0 |
| Atlas v001 cells identical | yes |
| v001 files unchanged | yes |

### Renders (`renders/v002_dice_family/`)

1. `01_dice_family_together.png`
2. `02_doubledice_front_back_side.png`
3. `03_tripledice_front_back_side.png`
4. `04_luckydie_front_back_side.png`
5. `05_pivot_visualisation.png`
6. `06_shop_pedestal_comparison.png`
7. `07_r15_scale_comparison.png`
8. `08_gameplay_distance_comparison.png`
9. `09_material_closeup.png`
10. `10_wireframe_triangle_counts.png`
11. `11_party_dice_beside_family.png`
12. `12_neutral_contact_sheet.png`

### Known compromises

- The family die keeps the v001 construction exactly. The teal corner inlays and wider cream frame from the concept turnarounds are **not** added, because the brief said not to revise the Party Dice Block. Add them to the family die and the Party Dice Block together in a later pass if wanted.
- Double Dice is offset in depth (5.15 studs deep) so the two dice never intersect. From the front, Die_B covers part of Die_A's lower-right corner, as in the concept.
- The Triple ring sits behind the dice. From the front only the arcs between the dice show, but from the back the ring crosses the dice faces.
- The Lucky medallion's leaf lobes are 7-sided to stay under 8k triangles. They are crisp at shop distance; at gameplay distance the Lucky Die reads by its emerald and mint colours and gold glow rather than the leaf shape.
- Item names and effects still come only from the brief. The vault and the game's item definitions were not available to this cloud session.

## Review stage 3: Swap Ticket (v003)

Built by `source/build_swap_ticket_v003.py`, which imports the v001 and v002 build scripts as libraries and doesn't re-run them. All 46 v001/v002 files are hash-checked before and after the build and are byte-identical (`manifest_v003.json → v001_v002_files_unchanged: true`).

| | |
|---|---|
| FBX | `export/SwapTicket_v003.fbx` |
| Hierarchy | `SwapTicket_Root` → `SwapTicket` (one mesh, 19 closed shells) |
| Triangles | 5,996 (target 4,000–6,000; hard max 8,000) |
| Size | 3.95 W × 0.46 D × 2.41 H studs (1.106 × 0.128 × 0.675 m) |
| Pivot | Root and mesh origin at the bounding-box centre; spin or hover about world Z |
| Material | One slot, `PGK_KitAtlas`, using the **v002 atlas unchanged**; no new cells |

**Construction:** this is an all-new mesh built with the kit's existing tools (outline sweeps, bevelled profiles, dome rivets, box-projected atlas UVs).

- **Body:** a single bevelled sweep, 8 cm thick, following a ticket outline:
  - rounded corners
  - concave top and bottom edges
  - three smooth scallops on each short side (the perforation)

  The sweep profile is a rolled gold trim wrapping both faces, then a cobalt band, then a raised cream panel on each side. The short ends lean back 2 cm, so the ticket bows toward the viewer.
- **Front, in enamel relief 2.2–3.4 cm above the panel:**
  - a teal arrow arcing over the top to the right and a coral arrow arcing underneath to the left (point-symmetric twins)
  - gold-bezelled cobalt medallions at each end, with a teal pawn (left) and a coral pawn (right)
  - four gold rivets
- **Back:** a low-relief cream copy of the two arrows (82% size) and four rivets. The colourful front versus the plain back makes the facing obvious.
- **Seating:** every decorative shell is seated 12 mm into the panel, so nothing floats and no meshes intersect. This is the same convention as the dice pips.

**Validation** (`validation/fbx_roundtrip_v003.json`):

- FBX round trip passes:
  - hierarchy and names match
  - size within 2 mm
  - root-to-geometric-centre distance 0.0 mm
  - one UV layer, inside 0.011–0.943
  - one material slot, local transform identity
  - no helpers exported
- Geometry: 0 open edges, 0 inside-out shells, 0 degenerate triangles, 0 same-facing coplanar overlaps.

**Renders** in `renders/v003_swap_ticket/`:
1. `01_turnaround_front_back_side.png`
2. `02_front_three_quarter_hero.png`
3. `03_back_three_quarter.png`
4. `04_shop_pedestals_with_dice_family.png`
5. `05_r15_scale_comparison.png`
6. `06_gameplay_distance_comparison.png`
7. `07_material_bevel_closeup.png`
8. `08_pivot_visualisation.png`
9. `09_wireframe_triangle_count.png`
10. `10_neutral_contact_sheet.png`

**Compromises:**

- **No dark navy.** The atlas is full, and adding a cell would mean resizing or replacing a region that v001/v002 items use. The kit's COBALT is used for the contrast band and medallion insets, so it reads brighter than the navy in the concept.
- **Pawn figures.** The players are generic board-game pawns (round head on a tapered base) rather than the concept's person icons.
- **One mesh.** With the decorations as separate meshes, the "no floating parts" and "no intersecting meshes" requirements would conflict. A single mesh with seated shells satisfies both.

## Review stage 4: Custom Dice Block (v004)

Built by `source/build_custom_dice_v004.py`, which imports the v001 and v002 build scripts as libraries and doesn't re-run them. It uses the **v002 atlas unchanged**. All 61 v001–v003 files are hash-checked before and after the build and are byte-identical (`manifest_v004.json → v001_v003_files_unchanged: true`).

| | |
|---|---|
| FBX | `export/CustomDice_v004.fbx` |
| Hierarchy | `CustomDice_Root` → `CustomDice_Body`, `CustomDice_SelectorRing`, `CustomDice_Pointer` |
| Triangles | Body 6,840 · Ring 1,380 · Pointer 270 · **total 8,490** |
| Size | Assembly 4.39 W × 3.65 D × 4.57 H studs; body 3.38 studs (family die at 0.86 scale) |
| Pivots | All three meshes and the root sit at the die centre with identity local transforms |
| Dial axis | Blender +Y (front-to-back); ring and pointer rotate together about it, and only about it |

**The selector is a dial:**

- The gold ring lies in the die's front-to-back mid-plane and rides 8 mm above four gold rollers set into the die's front-to-back edges.
- Its inner radius (566 mm) clears the die's largest radius about the dial axis (544 mm). The clearance is therefore the same at every angle, and the ring never needs to leave its plane.
- A gimbal pivoting on the side faces was rejected. To clear the die's 3D corners it would need a ring about 4.9 studs across, over the 4.4-stud limit.
- The **pointer** clips onto the ring top. Its gold arm reaches forward over the die, and a coral arrowhead hangs in front of the selected face's top edge, carrying the teal control button. The arrowhead sits wholly in front of the die's front-most point, so it clears the die at every dial angle.
- The ring carries 11 cobalt tick marks; the pointer covers the 12th position.

**The die:**

- Same construction and proportions as the family die (optimised v002 build).
- The body and raised frames are **cream** with a gold inner lip, the faces are teal enamel, the pips are pearl in gold settings, and cobalt corner studs carry gold rivets.
- The **selected face is 5** (front), and its lip uses GOLD_GLOW.
- Opposite faces sum to 7: 5/2, 1/6, 3/4.

**Validation** (`validation/fbx_roundtrip_v004.json`, `manifest_v004.json → selector.rotation_test`):

- **Rest pose:** 0 intersections between any pair of meshes.
  - Ring–body: 7.9 mm.
  - Pointer–body: 136 mm.
  - Pointer–ring: 5.6 mm measured (1.5 mm designed seat gap under the arm).
- **Rotation test:** ring and pointer turned through 24 angles (every 15°). Minimum clearance to the body is **7.2 mm**, with **0 intersections**.
- **Geometry:** 0 open edges, 0 inside-out shells, 0 degenerate triangles, 0 same-facing coplanar overlaps. UVs are inside 0–1, with one material slot per mesh.
- **FBX round trip passes:** hierarchy and names, size within 2 mm, every pivot within 2 mm of the root, local transforms identity, and no helpers exported.

**Renders** in `renders/v004_custom_dice/`:
1. `01_turnaround_front_back_side.png`
2. `02_front_three_quarter_hero.png`
3. `03_selector_mechanism_closeup.png`
4. `04_selector_three_positions.png`
5. `05_shop_pedestals_with_dice_family.png`
6. `06_r15_scale_comparison.png`
7. `07_gameplay_distance_comparison.png`
8. `08_pivot_rotation_axis.png`
9. `09_material_closeup.png`
10. `10_wireframe_triangle_counts.png`
11. `11_neutral_contact_sheet.png`

**Compromises:**

- The body is 3.38 studs rather than 3.5. That keeps the dial ring at 4.39 studs across, inside the 4.4 limit.
- Height is 4.57 studs because the pointer's arm and button sit on top of the ring.
- The ring's outermost ~5 cm falls just outside the atlas projection range. Its UVs clamp to the edge of the GOLD cell: still valid and inside 0–1, with no visible difference.
- The cream cloud-shaped bracket from the concept is replaced by the edge rollers, so the ring is visibly carried by the die.

## Review stage 5: Pickpocket (v005)

Built by `source/build_pickpocket_v005.py` from the Pickpocket turnaround supplied with the v005 brief. It imports the v001 and v002 build scripts as libraries, doesn't re-run them, and uses the **v002 atlas unchanged**. All 77 v001–v004 files are hash-checked before and after the build and are byte-identical (`manifest_v005.json → v001_v004_files_unchanged: true`).

| | |
|---|---|
| FBX | `export/Pickpocket_v005.fbx` |
| Hierarchy | `Pickpocket_Root` → `Pickpocket_Glove` (27 seated shells), `Pickpocket_Coin` |
| Triangles | Glove 6,624 · Coin 852 · **total 7,476** |
| Size | 3.03 W × 1.78 D × 3.59 H studs (0.850 × 0.498 × 1.005 m) |
| Root pivot | Bounding-box (visual) centre of the whole item; the glove is aligned with it |
| Coin | Local transform: location (0.288, −0.019, 0.128) m, rotation 0, scale 1. The face points along local −Y (the item front); spin axis is local +Z |

**Reading of the reference:** the coin lies in the plane of the finger curl.

- **Front:** the C-shaped pinch, with the index tip above the coin and the thumb tip below, and the coin face toward the viewer.
- **Palm side (+X):** the coin edge-on in front of the fingers.
- **Back of the hand (−X):** the faceted sea-glass gem (AQUA) in a gold bezel and cobalt ring, a gold strap and rivets.
- **Opposite profile (+Y):** the coin's back, which carries a second star.

**Construction:** this is new geometry built with kit tools (sweeps, domes, atlas UVs) plus a new tapered-tube builder for the fingers.

- **Cuff (oval, wider than deep):** gold rims, a coral band, a cobalt stripe, a cream roll and three gold buttons.
- **Palm:** a rounded teal block.
- **Fingers:** three teal tube fingers (index, middle, thumb) with gold joint bands, gold knuckle bosses and cream fingertip pads.
- **Coin:** a gold coin with a raised rim and a four-point star on each face.
- **Seating:** every glove shell is seated into another, with 0 floating shells.

**Validation** (`validation/fbx_roundtrip_v005.json`, `manifest_v005.json`):

- **Coin:** clearance at rest is 3.7 mm with 0 intersections. A full spin at 36 angles (every 10°) gives a minimum of **3.5 mm** and **0 intersections**. Both fingertips are centred on the spin axis, so the gap stays the same.
- **Finger-to-finger clearance:** index–middle 27.5 mm, index–thumb 120 mm, middle–thumb 234 mm; 0 intersections.
- **Geometry:** 0 open edges, 0 inside-out shells, 0 degenerate triangles, 0 same-facing coplanar overlaps. UVs are inside 0–1, with one material slot per mesh.
- **FBX round trip passes:** hierarchy and names, size within 2 mm, root at the visual centre (0.0 mm), coin pivot within 2 mm, local rotation and scale identity, and no helpers exported.

**Renders** in `renders/v005_pickpocket/`:
1. `01_turnaround_front_back_side.png` (front, back, palm side, back-of-hand side)
2. `02_front_three_quarter_hero.png`
3. `03_back_three_quarter.png`
4. `04_coin_finger_clearance_closeup.png`
5. `05_coin_three_spin_angles.png`
6. `06_shop_pedestals_with_shield_and_token.png`
7. `07_r15_scale_comparison.png`
8. `08_gameplay_distance_comparison.png`
9. `09_pivot_coin_axis.png`
10. `10_material_joint_closeup.png`
11. `11_wireframe_triangle_counts.png`
12. `12_neutral_contact_sheet.png`

**Compromises:**

- **Gem placement:** the brief asks for the gem on the "back". The reference places it on the back of the hand, which faces the item's left side when the coin faces front. The turnaround therefore adds a back-of-hand panel, and the back three-quarter view is aimed at the gem.
- **Fewer fingers:** the reference's fourth, small finger is folded into the middle finger, so there are three fingers.
- **Visible gap:** the coin is held with a 3.5 mm gap to each fingertip so it never touches the fingers. At close range a hairline gap shows.

## Open items for the reviewer

- This session ran in a cloud container, so the macOS paths in the brief (`/Users/aaronlee/...`) were not reachable. That includes the required reading (`UI & Visual Style.md`, `Roblox Dev Home.md`, `Party Games.md`), the LihFolk notes and the party-game repository. The item names and effects here are taken **only** from the brief (Party Dice Block, Coin Shield, Warp Token; future Double/Triple/Lucky/controlled-roll dice). No gameplay was invented, but the names still need checking against the real item definitions before the remaining set is modelled.
- The kit lives in `PartyGameItemKit/` in this repo instead of `~/Documents/Roblox Asset Tests/PartyGameItemKit/`. Copy the folder there if you want it alongside the other asset tests.
