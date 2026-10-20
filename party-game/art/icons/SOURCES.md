# Icon sources

Status: **production utility atlas candidate v1 - not approved, not uploaded, not used by the game.**

## Packages (downloaded 2026-10-20; ZIPs kept outside the repo)

| Pack | Version | Page | ZIP SHA-256 | License (verified inside the ZIP) |
|---|---|---|---|---|
| Board Game Icons | 1.1 (22-07-2024) | https://kenney.nl/assets/board-game-icons | `05f4358381d8b16b303b2f056393b76ce3f6a58228599e88caa2eab11d4c2946` | CC0 1.0 - `selected/board-game-icons/License.txt` |
| Input Prompts | 1.5A (11-07-2026) | https://kenney.nl/assets/input-prompts | `ac2fcf599080b0f3ba2d174c9474db6df1a0e96ff0662580e2da79a122ab78a1` | CC0 1.0 - `selected/input-prompts/License.txt` |
| UI Pack | 2.0 (12-06-2024) | https://kenney.nl/assets/ui-pack | `a8a14a234911eb648c062622915c93e79e94e97cb7f9f375a70f6617f1174318` | CC0 1.0 - `selected/ui-pack/License.txt` |

Download URLs: `https://kenney.nl/media/pages/assets/board-game-icons/19cae04050-1721645690/kenney_board-game-icons.zip`,
`.../input-prompts/8de120163f-1783763952/kenney_input-prompts_1.5.zip`, `.../ui-pack/f651646eab-1718203990/kenney_ui-pack.zip`.

CC0: attribution not required; Kenney asks for optional credit ("Kenney, www.kenney.nl").

## How files get here

`vendor_sync.py <extracted packs> [--write]` copies exactly the sources listed in `atlas_v1.tsv` (plus each PNG's SVG and the
licenses) into `art/vendor/kenney/selected/<pack>/<original relative path>`, unmodified, and writes `file_hashes.tsv`
(SHA-256 of every copied file, 166 files). It dry-runs unless `--write` is given and refuses packs whose license is not CC0.

## Atlas v1 (`build_atlas.py` -> `export/v1/`)

Source files are never modified. Generated cells only:
- **Rendered:** UI Pack and Input Prompts icons from their SVG (4x oversampled, then fitted); Board Game icons from their official 128 px PNG (their SVGs carry no size).
- **Fitted:** trimmed to the drawn shape, scaled down (never up) into a centred 104 px box in a 128 px cell.
- **Flattened to white** (tinted in game with ImageColor3): every `tint = yes` icon and every light-panel outline cell.
- **Edge bleed:** transparent pixels take the neighbouring colour so texture filtering / mipmaps show no dark fringes.

| Semantic | Atlas | Pack | Source used (dark panel) | Light-panel source | Tint | Min px | Use | SHA-256 (source) |
|---|---|---|---|---|---|---|---|---|
| Arrow | utility | board-game-icons | `PNG/Double (128px)/arrow_right.png` | tinted dark | yes | 24 | Next; Back and Previous use the same cell rotated 180 | `410e00482b9071c7…` |
| Close | utility | ui-pack | `Vector/Grey/icon_cross.svg` | tinted dark | yes | 24 | MAP CLOSE, shop CLOSE (SVG rendered, flattened to white for tinting) | `52dbc06653a03cbb…` |
| Check | utility | ui-pack | `Vector/Grey/icon_checkmark.svg` | tinted dark | yes | 24 | shop confirm, wear (SVG rendered, flattened to white) | `86c4df4a58ac1f8c…` |
| Route | utility | board-game-icons | `PNG/Double (128px)/arrow_cross.png` | tinted dark | yes | 24 | fork prompt, MAP routes | `8b9a9f8ab313e993…` |
| Gate | utility | board-game-icons | `PNG/Double (128px)/structure_gate.png` | tinted dark | yes | 24 | MAP gates, toll prompt | `e8f8278a770b49db…` |
| Locked | utility | board-game-icons | `PNG/Double (128px)/lock_closed.png` | tinted dark | yes | 20 | closed gate / exit, locked cosmetics | `cb242cecafabfd15…` |
| Timer | utility | board-game-icons | `PNG/Double (128px)/hourglass.png` | tinted dark | yes | 20 | vote countdown, roll countdown | `69693c139c4e3c12…` |
| Placement | utility | board-game-icons | `PNG/Double (128px)/award.png` | tinted dark | yes | 24 | results, final standings (tint per place) | `24f68efde2acaf5d…` |
| Select | utility | ui-pack | `Vector/Extra/icon_play_light.svg` | tinted dark | yes | 20 | selected menu row (SVG rendered) | `a22d50c1b783e79f…` |
| Finish | utility | board-game-icons | `PNG/Double (128px)/flag_triangle.png` | tinted dark | yes | 20 | race progress bar finish | `194e91cf4ea25e94…` |
| Items | utility | board-game-icons | `PNG/Double (128px)/pouch.png` | tinted dark | yes | 36 | turn menu ITEMS row | `998a152ce808c195…` |
| Pointer | utility | input-prompts | `Touch/Vector/touch_finger_one.svg` | tinted dark | yes | 40 | onboarding hand (rotated per side) | `9005ce64e8d029a7…` |
| Tap | utility | input-prompts | `Touch/Vector/touch_tap.svg` | tinted dark | yes | 24 | Tap the die, touch instructions | `d566023aa71460f8…` |
| Move | utility | input-prompts | `Generic/Vector/generic_stick.svg` | tinted dark | yes | 24 | instruction card: Move | `ff75824af0d21eb9…` |
| NoMove | utility | input-prompts | `Flairs/Vector/flair_disabled.svg` | same cell | no | 24 | drawn over Move: "can't walk this round" | `4eea14c3fa73a9ac…` |
| KeySpace | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_space.svg` | `Keyboard & Mouse/Vector/keyboard_space_outline.svg` | no | 24 | roll, Ice/Kernel actions | `e6c3941bfae3a1db…` |
| KeyEnter | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_enter.svg` | `Keyboard & Mouse/Vector/keyboard_enter_outline.svg` | no | 24 | turn menu activate | `e592001ec1dd482e…` |
| KeyBackspace | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_backspace.svg` | `Keyboard & Mouse/Vector/keyboard_backspace_outline.svg` | no | 24 | item list back | `cd0277567c71928b…` |
| KeyM | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_m.svg` | `Keyboard & Mouse/Vector/keyboard_m_outline.svg` | no | 24 | MAP | `dfeaa0a33f6cc559…` |
| KeyE | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_e.svg` | `Keyboard & Mouse/Vector/keyboard_e_outline.svg` | no | 24 | spectate next / actions | `58fc78c36761512b…` |
| KeyQ | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_q.svg` | `Keyboard & Mouse/Vector/keyboard_q_outline.svg` | no | 24 | spectate previous | `1b99f67c6d1f6385…` |
| KeyB | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_b.svg` | `Keyboard & Mouse/Vector/keyboard_b_outline.svg` | no | 24 | shop toggle | `a253fad3be47ae40…` |
| KeyW | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_w.svg` | `Keyboard & Mouse/Vector/keyboard_w_outline.svg` | no | 24 | menu up, minigames | `689d533faf0cf531…` |
| KeyA | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_a.svg` | `Keyboard & Mouse/Vector/keyboard_a_outline.svg` | no | 24 | left actions | `3ecc3176cd7361e4…` |
| KeyS | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_s.svg` | `Keyboard & Mouse/Vector/keyboard_s_outline.svg` | no | 24 | menu down | `56cbeb694c9bb9a5…` |
| KeyD | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_d.svg` | `Keyboard & Mouse/Vector/keyboard_d_outline.svg` | no | 24 | right actions | `009b3768692869e5…` |
| KeyLeft | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_arrow_left.svg` | `Keyboard & Mouse/Vector/keyboard_arrow_left_outline.svg` | no | 24 | left actions | `fad7a5ba6edec708…` |
| KeyRight | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_arrow_right.svg` | `Keyboard & Mouse/Vector/keyboard_arrow_right_outline.svg` | no | 24 | right actions | `8c04a9866e43a48b…` |
| KeyUp | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_arrow_up.svg` | `Keyboard & Mouse/Vector/keyboard_arrow_up_outline.svg` | no | 24 | menu up | `87c8e11038c200a9…` |
| KeyDown | keyboard | input-prompts | `Keyboard & Mouse/Vector/keyboard_arrow_down.svg` | `Keyboard & Mouse/Vector/keyboard_arrow_down_outline.svg` | no | 24 | menu down | `cc1e186f25a9ff4b…` |
| XboxA | gamepad | input-prompts | `Xbox Series/Vector/xbox_button_color_a.svg` | same cell | no | 24 | coloured: same cell on light panels | `63d1a6d0798c09c7…` |
| XboxB | gamepad | input-prompts | `Xbox Series/Vector/xbox_button_color_b.svg` | same cell | no | 24 | coloured | `1a50644b6cb5a595…` |
| XboxX | gamepad | input-prompts | `Xbox Series/Vector/xbox_button_color_x.svg` | same cell | no | 24 | coloured | `49840e42f7aa78d1…` |
| XboxY | gamepad | input-prompts | `Xbox Series/Vector/xbox_button_color_y.svg` | same cell | no | 24 | coloured | `27436f37e982d0e2…` |
| XboxLB | gamepad | input-prompts | `Xbox Series/Vector/xbox_lb.svg` | `Xbox Series/Vector/xbox_lb_outline.svg` | no | 24 | spectate previous | `6463d4c86715f144…` |
| XboxRB | gamepad | input-prompts | `Xbox Series/Vector/xbox_rb.svg` | `Xbox Series/Vector/xbox_rb_outline.svg` | no | 24 | spectate next | `066ac893d3baa92d…` |
| XboxView | gamepad | input-prompts | `Xbox Series/Vector/xbox_button_view.svg` | `Xbox Series/Vector/xbox_button_view_outline.svg` | no | 24 | shop toggle (ButtonSelect) | `d9f3bd3869469d00…` |
| XboxUp | gamepad | input-prompts | `Xbox Series/Vector/xbox_dpad_up.svg` | `Xbox Series/Vector/xbox_dpad_up_outline.svg` | no | 24 | menu up | `1eb952dcac0a986a…` |
| XboxDown | gamepad | input-prompts | `Xbox Series/Vector/xbox_dpad_down.svg` | `Xbox Series/Vector/xbox_dpad_down_outline.svg` | no | 24 | menu down | `d7a0d403e36c4112…` |
| XboxLeft | gamepad | input-prompts | `Xbox Series/Vector/xbox_dpad_left.svg` | `Xbox Series/Vector/xbox_dpad_left_outline.svg` | no | 24 | left actions | `6fc565008a474f3c…` |
| XboxRight | gamepad | input-prompts | `Xbox Series/Vector/xbox_dpad_right.svg` | `Xbox Series/Vector/xbox_dpad_right_outline.svg` | no | 24 | right actions | `5e3e358a70aaa5ea…` |
| PSCross | gamepad | input-prompts | `PlayStation Series/Vector/playstation_button_color_cross.svg` | same cell | no | 24 | coloured (needs real-hardware detection check) | `c9feef98bfd29797…` |
| PSCircle | gamepad | input-prompts | `PlayStation Series/Vector/playstation_button_color_circle.svg` | same cell | no | 24 | coloured | `7749fe0886d9d832…` |
| PSSquare | gamepad | input-prompts | `PlayStation Series/Vector/playstation_button_color_square.svg` | same cell | no | 24 | coloured | `2ad7d59334648b82…` |
| PSTriangle | gamepad | input-prompts | `PlayStation Series/Vector/playstation_button_color_triangle.svg` | same cell | no | 24 | coloured | `c8af09238e5c3820…` |
| PSL1 | gamepad | input-prompts | `PlayStation Series/Vector/playstation_trigger_l1.svg` | `PlayStation Series/Vector/playstation_trigger_l1_outline.svg` | no | 24 | spectate previous | `ae444563986badef…` |
| PSR1 | gamepad | input-prompts | `PlayStation Series/Vector/playstation_trigger_r1.svg` | `PlayStation Series/Vector/playstation_trigger_r1_outline.svg` | no | 24 | spectate next | `387a37176b86facb…` |
| PSCreate | gamepad | input-prompts | `PlayStation Series/Vector/playstation5_button_create.svg` | `PlayStation Series/Vector/playstation5_button_create_outline.svg` | no | 24 | shop toggle (ButtonSelect) | `4ec964bb271ba0d3…` |
| PSUp | gamepad | input-prompts | `PlayStation Series/Vector/playstation_dpad_up.svg` | `PlayStation Series/Vector/playstation_dpad_up_outline.svg` | no | 24 | menu up | `e61c695f420ac22f…` |
| PSDown | gamepad | input-prompts | `PlayStation Series/Vector/playstation_dpad_down.svg` | `PlayStation Series/Vector/playstation_dpad_down_outline.svg` | no | 24 | menu down | `c06abfab82a6e264…` |
| PSLeft | gamepad | input-prompts | `PlayStation Series/Vector/playstation_dpad_left.svg` | `PlayStation Series/Vector/playstation_dpad_left_outline.svg` | no | 24 | left actions | `5c81b1632941d5d2…` |
| PSRight | gamepad | input-prompts | `PlayStation Series/Vector/playstation_dpad_right.svg` | `PlayStation Series/Vector/playstation_dpad_right_outline.svg` | no | 24 | right actions | `32d64ec2639ef291…` |
| GamepadAction | gamepad | input-prompts | `Generic/Vector/generic_button_circle_fill.svg` | `Generic/Vector/generic_button_circle_outline.svg` | no | 24 | neutral fallback; the button letter stays native text on top | `926d47cb41390c6f…` |

Excluded until custom icons exist: Map, Shop, Crown, Coin, Warning, Spectate, Bot, Roll/die, the 11 board items.
