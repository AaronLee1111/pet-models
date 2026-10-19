# Sunny Loop medallions v1 — staged integration

Status: five-space slice, **not approved for all 40 spaces yet**. No experience was published.

## Assets and reproduction

Editable source: `art/blender/medallions_v1/SunnyLoop_Medallions_v1.blend`.
Authoring script: `build_medallions.py` beside it. Blender 4.5.1 LTS. The script refuses to overwrite an existing source; regenerate into a new destination/version. Fifteen original closed meshes: base, five inlays and nine symbols. Individual FBX/GLB exports and a combined import FBX live in `art/export/medallions_v1`. One 512×512 palette atlas is shared by the base; inserts and symbols use Roblox tint. UVs intentionally sample palette swatches, not unique texture unwraps.

Roblox import receipts are in `roblox-assets.json`; source templates are in `src/server/Board/MedallionAssets.rbxmx`. Rojo includes these through the existing Board folder mapping. Build with `rojo build place.project.json -o MemeParty.rbxlx`.

Meshes were authored in studs then exported at 0.28 metres/stud. Studio's import produced numerical sizes at 0.28 of the target. Templates retain that native `InitialSize`, with displayed `Size` divided by 0.28. **Do not set InitialSize equal to the resized Size**: that produces miniature visible geometry after reload. `scripts/validate_medallions.py` catches this regression. The integration rotates imported meshes 180° around Y so Blender +Y faces Roblox -Z. MeshPart centers are compensated from each mesh's bounds; the assembled origin remains the space origin.

## Dimensions and layers

The established invisible collider remains 10.5 studs across and 1 stud tall. Presentation top is unchanged at 1.2. Four existing ±2.5-stud standing slots and all route centers/elevations remain unchanged. Decorative mesh envelope is 11.68 studs. Meshes are anchored, noncollidable, nonqueryable and nontouchable.

| Surface | Studs above space origin |
|---|---:|
| Structural bottom | 0 |
| Recessed bed | 0.86 |
| Insert bottom / top | 0.91 / 1.20 |
| Carved rim top | 1.12 |
| Regular symbol bottom / top | 1.24 / 1.38 |
| Ring symbol bottom / top | 0.90 / 1.04 |
| Native value plate center / top | 1.42 / 1.445 |

Ring symbols are recessed by 0.34 studs into the exposed bed area. Other symbols have a 0.04-stud separation from their insert. Base is a single continuous radial solid, not stacked discs. Mesh topology was merged, normals recalculated and triangulated before export; all mesh edges are manifold. Render verification does not establish that the whole board is flicker-free during continuous camera movement.

## Integration

`MedallionMeshes.Mode = "Slice"` gates IDs 5 (fork), 6 (Gain), 7 (Shop), 8 (Lose), 30 (Event). Other spaces remain available for comparison. The call site explicitly requires board.Name `SunnyLoopV2`; other boards retain their previous presentation. `Gift` aliases `Reward`. Numeric values remain native text. Existing active/destination/route presentation code is retained. Assets preload before hiding the existing collider's visual; absent/failed templates return to existing visuals without a partial mesh assembly. Each clone reuses its variant's content ID.

## Validation evidence

- Full Studio suite: **236 passed, 0 failed**, including five new mesh tests. Covers collider/attributes/text, slice eligibility, missing-symbol fallback, Gift mapping and mesh duplicate auditing. Existing board tests cover four-piece slots, routes, fork decisions, shops, events and bot simulation.
- Offline validator passes: 15 FBX/GLB pairs, triangle receipts, origins, material count, serialized scale, collision flags and envelopes.
- Maximum conservative assembly: 380 base + 80 insert + 76 symbol = **536 triangles**, or **21,440 for 40 spaces**, below all requested ceilings. This is a geometry budget, not a measured device frame-rate result.
- Desktop edit-mode captures: `beforeActive.png`, `beforeFork.png`, `beforeMap.png`, `afterSlice.png`. New kit compared beside untouched spaces. Import orientation, native text aspect ratio and source serialization scale were corrected during review.
- SceneAudit now uses MeshId for MeshParts instead of reading the unsupported Shape property. It detects duplicate mesh placements; its flat-face coplanarity pass still applies only to primitive Parts.

## Outstanding rollout gates

- Landscape phone capture and device performance: not verified. Studio device selector did not respond reliably to automation; UI capture also intermittently failed.
- Live end-to-end roll, movement, fork, Shop/Event landing, route/destination highlights and MAP interaction: incomplete. Review play session remained at the lobby after Start input with no BoardState messages. Automated rule tests passed, but they are not a substitute for these visual interactions.
- Continuous orbit flicker check and all remaining symbol readability at MAP distance: pending.
- Final source rebuild is generated, but a fresh visual reload after the InitialSize correction remains to be checked.
- Only after these checks succeed, set Mode to `All`, rerun the suite and rebuild. Do not silently expand the rollout before validation.

Unrelated existing `docs/references/ui/` files were preserved and excluded from these commits. Studio also reported a pre-existing asset-type failure for asset 203785492 and core UI warnings; neither is a medallion mesh ID.
