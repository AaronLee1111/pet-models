# Icon sources (phase 1: licensed utility icons)

Status: **candidate only**. Nothing here is used by the game or uploaded to Roblox. Review sheet:
`review/utility-icons-candidate-v1.png` (regenerate with `review/make_candidate_sheet.py`).

Downloaded 2026-10-20. The ZIPs stay outside the repo (scratchpad cache); only the selected files
below and each pack's `License.txt` are copied, unmodified, into `art/vendor/kenney/selected/<pack>/`
at their original relative paths.

## Packages

| Pack | Version | Page | ZIP | SHA-256 | License (verified in ZIP) |
|---|---|---|---|---|---|
| Board Game Icons | 1.1 (License.txt creation date 22-07-2024) | https://kenney.nl/assets/board-game-icons | [kenney_board-game-icons.zip](https://kenney.nl/media/pages/assets/board-game-icons/19cae04050-1721645690/kenney_board-game-icons.zip) | `05f4358381d8b16b303b2f056393b76ce3f6a58228599e88caa2eab11d4c2946` | CC0 1.0 (`board-game-icons/License.txt`) |
| Input Prompts | 1.5A (License.txt creation date 11-07-2026) | https://kenney.nl/assets/input-prompts | [kenney_input-prompts_1.5.zip](https://kenney.nl/media/pages/assets/input-prompts/8de120163f-1783763952/kenney_input-prompts_1.5.zip) | `ac2fcf599080b0f3ba2d174c9474db6df1a0e96ff0662580e2da79a122ab78a1` | CC0 1.0 (`input-prompts/License.txt`) |
| UI Pack | 2.0 (License.txt creation date 12-06-2024) | https://kenney.nl/assets/ui-pack | [kenney_ui-pack.zip](https://kenney.nl/media/pages/assets/ui-pack/f651646eab-1718203990/kenney_ui-pack.zip) | `a8a14a234911eb648c062622915c93e79e94e97cb7f9f375a70f6617f1174318` | CC0 1.0 (`ui-pack/License.txt`) |

CC0: no attribution required; Kenney asks for optional credit ("Kenney, www.kenney.nl").

## Selected files and intended use

Modifications: none to any file. "tint" = Roblox `ImageColor3` at runtime; "rasterise SVG" = a new
128 px PNG generated from the SVG at atlas time (the source PNG is only 36-68 px); originals stay as-is.

| Semantic name | Pack | Source PNG | Source SVG | Screen | Min px | Modification | PNG SHA-256 |
|---|---|---|---|---|---|---|---|
| Map (A) | board-game-icons | `PNG/Double (128px)/pawn_table.png` | `Vector/Icons/pawn_table.svg` | turn menu MAP row, MAP panel title | 36 | tint only | `507596734b4011b6…` |
| Map (B) | board-game-icons | `PNG/Double (128px)/direction_n.png` | `Vector/Icons/direction_n.svg` | turn menu MAP row | 36 | tint only | `4b39961055ba5c94…` |
| Map (C) | board-game-icons | `PNG/Double (128px)/notepad.png` | `Vector/Icons/notepad.svg` | turn menu MAP row | 36 | tint only | `2af1610dec2612b9…` |
| Back | ui-pack | `PNG/Grey/Double/arrow_basic_w.png` | `Vector/Grey/arrow_basic_w.svg` | item list Back, shop | 24 | tint; rasterise SVG at 128 (PNG is 64 px) | `4b2294f347d5e6b7…` |
| Back (board-family alt) | board-game-icons | `PNG/Double (128px)/arrow_right.png` | `Vector/Icons/arrow_right.svg` | item list Back, shop | 24 | tint; mirror horizontally at runtime (Rotation 180) | `410e00482b9071c7…` |
| Close | ui-pack | `PNG/Grey/Double/icon_cross.png` | `Vector/Grey/icon_cross.svg` | MAP CLOSE, shop CLOSE | 24 | tint; rasterise SVG at 128 | `74b5c4cdaddb6733…` |
| Check | ui-pack | `PNG/Grey/Double/icon_checkmark.png` | `Vector/Grey/icon_checkmark.svg` | shop confirm, wear | 24 | tint; rasterise SVG at 128 | `d4f9f407a6875382…` |
| Previous | ui-pack | `PNG/Grey/Double/arrow_decorative_w.png` | `Vector/Grey/arrow_decorative_w.svg` | spectator bar | 24 | tint; rasterise SVG at 128 | `0bc0cba0fb4a907a…` |
| Next | ui-pack | `PNG/Grey/Double/arrow_decorative_e.png` | `Vector/Grey/arrow_decorative_e.svg` | spectator bar | 24 | tint; rasterise SVG at 128 | `966c60935c250d76…` |
| Route/Fork (A) | board-game-icons | `PNG/Double (128px)/arrow_right_curve.png` | `Vector/Icons/arrow_right_curve.svg` | fork prompt, MAP routes | 24 | tint only | `9c0203cdcee91bcd…` |
| Route/Fork (B) | board-game-icons | `PNG/Double (128px)/arrow_cross.png` | `Vector/Icons/arrow_cross.svg` | fork prompt, MAP routes | 24 | tint only | `8b9a9f8ab313e993…` |
| Gate | board-game-icons | `PNG/Double (128px)/structure_gate.png` | `Vector/Icons/structure_gate.svg` | MAP gates, toll prompt | 24 | tint only | `e8f8278a770b49db…` |
| Locked | board-game-icons | `PNG/Double (128px)/lock_closed.png` | `Vector/Icons/lock_closed.svg` | closed gate / exit, cosmetics | 20 | tint only | `cb242cecafabfd15…` |
| Timer | board-game-icons | `PNG/Double (128px)/hourglass.png` | `Vector/Icons/hourglass.svg` | vote card, roll countdown | 20 | tint only | `69693c139c4e3c12…` |
| Placement/Trophy | board-game-icons | `PNG/Double (128px)/award.png` | `Vector/Icons/award.svg` | results, final standings | 24 | tint per place (gold/silver/bronze/muted) | `24f68efde2acaf5d…` |
| Select arrow | ui-pack | `PNG/Extra/Double/icon_play_light.png` | `Vector/Extra/icon_play_light.svg` | turn menu selected row | 20 | tint gold; rasterise SVG at 128 (PNG is 60x68) | `60b1a1812e2263e0…` |
| Onboarding pointer | input-prompts | `Touch/Double/touch_finger_one.png` | `Touch/Vector/touch_finger_one.svg` | GuidePointer hand | 40 | rotate per side at runtime; no tint (has outline) | `8c15dc271eb356c1…` |
| Keyboard Space | input-prompts | `Keyboard & Mouse/Double/keyboard_space.png` | `Keyboard & Mouse/Vector/keyboard_space.svg` | die hint, minigame cards | 24 | none | `7f25e4d93c3589ef…` |
| Keyboard arrows | input-prompts | `Keyboard & Mouse/Double/keyboard_arrows.png` | `Keyboard & Mouse/Vector/keyboard_arrows.svg` | menu navigation, minigame cards | 24 | none | `60acb8da97448648…` |
| Keyboard W (WASD set) | input-prompts | `Keyboard & Mouse/Double/keyboard_w.png` | `Keyboard & Mouse/Vector/keyboard_w.svg` | minigame cards (W/A/S/D each) | 24 | none | `80afe8ada6813562…` |
| Generic gamepad action | input-prompts | `Generic/Double/generic_button_circle_fill.png` | `Generic/Vector/generic_button_circle_fill.svg` | fallback controller prompt | 24 | none | `9c33ead51ada00ef…` |
| Xbox action (A) | input-prompts | `Xbox Series/Double/xbox_button_color_a.png` | `Xbox Series/Vector/xbox_button_color_a.svg` | controller prompts (Xbox) | 24 | none (colour is the button identity) | `c180cd5f062017a6…` |
| PlayStation action (Cross) | input-prompts | `PlayStation Series/Double/playstation_button_color_cross.png` | `PlayStation Series/Vector/playstation_button_color_cross.svg` | controller prompts (PlayStation) | 24 | none | `24de33a24451add4…` |
| Touch/tap | input-prompts | `Touch/Double/touch_tap.png` | `Touch/Vector/touch_tap.svg` | Tap the die, minigame cards | 24 | none | `917768452844406b…` |
| Move | input-prompts | `Generic/Double/generic_stick.png` | `Generic/Vector/generic_stick.svg` | minigame instruction card | 24 | none | `80e364649fa402f9…` |
| Jump | board-game-icons | `PNG/Double (128px)/pawn_up.png` | `Vector/Icons/pawn_up.svg` | minigame instruction card | 24 | tint only | `ed1f005ef5f2feba…` |
| Movement disabled (overlay) | input-prompts | `Flairs/Double/flair_disabled.png` | `Flairs/Vector/flair_disabled.svg` | can't walk = Move + this overlay | 24 | layered over Move at runtime | `f858d1c51609fcc8…` |
| Race finish flag (A) | board-game-icons | `PNG/Double (128px)/flag_square.png` | `Vector/Icons/flag_square.svg` | race progress bar | 20 | tint only | `f023eb0b9f75c4ae…` |
| Race finish flag (B) | board-game-icons | `PNG/Double (128px)/flag_triangle.png` | `Vector/Icons/flag_triangle.svg` | race progress bar | 20 | tint only | `194e91cf4ea25e94…` |
| Shop (optional) | board-game-icons | `PNG/Double (128px)/structure_house.png` | `Vector/Icons/structure_house.svg` | lobby SHOP, shop space | 24 | tint only | `822beba594bf1b88…` |
| Items (optional) | board-game-icons | `PNG/Double (128px)/pouch.png` | `Vector/Icons/pouch.svg` | turn menu ITEMS row | 36 | tint only | `998a152ce808c195…` |
| Crown (optional A) | board-game-icons | `PNG/Double (128px)/crown_a.png` | `Vector/Icons/crown_a.svg` | standings, MAP | 14 | tint gold | `67cfe50c77f2120e…` |
| Crown (optional B) | board-game-icons | `PNG/Double (128px)/crown_b.png` | `Vector/Icons/crown_b.svg` | standings, MAP | 14 | tint gold | `afeb4fe9bb3b92d3…` |
| Coin (optional A) | board-game-icons | `PNG/Double (128px)/token.png` | `Vector/Icons/token.svg` | standings, results | 14 | tint gold | `3101368d116ba8f0…` |
| Coin (optional B) | board-game-icons | `PNG/Double (128px)/dollar.png` | `Vector/Icons/dollar.svg` | standings, results | 14 | tint gold | `729677f8ce07738d…` |

Full hashes of every copied file (PNG and SVG): `file_hashes.tsv`.
