# Backlog

Things deliberately left for later. Newest notes go at the bottom of each section.

## Theme leftovers (internal names kept to avoid risk)

- Place file is still `MemeParty.rbxlx`, and the Rojo project name is `MemeParty`. Renaming the file means everyone's Studio shortcuts and the lag harness paths change, so do it together with the first publish.
- `Kernel Catch` (popcorn), `Hot Potato` (potato) and the 🍿 🥔 🔔 emoji in minigame copy are placeholder flavour, not meme references, but will need restyling once the game has its own visual identity.
- Bot names (`Config.BotNames`) are neutral placeholders.

## Visual / polish phase (follow `UI & Visual Style.md`)

- Everything from the Step 1 style audit (glass panels, gradients, icons, sounds, coin bursts, onboarding pointers, safe areas, centre-clear banners, arena dressing).
- Board, lobby-settings, turn and final-standings UI are functional placeholders only.
- Board look is placeholder: flat coloured tiles on a grass slab, a neon ball for the Crown, no space icons, no dice model or roll animation, pieces teleport hop-to-hop instead of walking or jumping.
- No space legend on screen; tile text (+3, -3, ?, SHOP, GIFT) is the only explanation of spaces.
- The landing/event feed reuses the minigame toast feed. A board needs its own clearer "what just happened" panel.
- Board standings rows use text ("0 Crowns · 10 coins"). Swap in Crown and coin icons and player headshots in the visual pass.
- Prompt buttons are plain; the shop prompt doesn't show item pictures or rarity.
- Final standings card has no podium, confetti or reward moment.
- Waiting room: no explanation of the rules, no "how to play" for new players, and no pointer on START or ROLL for first-timers (style guide onboarding rule).
- Cosmetics are placeholder shapes (a coloured part on the head, a trail, sparkles for emotes). Emotes don't play an animation. The wardrobe is a plain row of buttons in the waiting room with no previews.

## Mechanics to revisit

- ~~No Crown-steal item or event yet.~~ Done: Crown Heist item (with a fee; Coin Shield counters it).
- Bot item use plans around the Crown, its own coins and opponents' Coin Shields (it won't rob a shielded seat). It still doesn't plan around other players' held items.
- New late joiners (no reserved seat) watch until the next match; they can't take over a lobby-fill bot's seat mid-match. By design for now.
- ~~Players who leave are replaced by a bot permanently.~~ Done (seat reclaim): the seat is reserved for their UserId and handed back when they rejoin.
- Seat reclaim was smoke-tested in Studio by running the real leave and rejoin handlers on a live match; a true disconnect and reconnect of the same account on a live server is still untested.
- `tests/sim.luau` (lune) predates the board game and still expects the old lobby → vote loop; lune isn't installed on this machine. Board rules are covered by `tests/unit` instead.
- ~~Persistence stubbed.~~ Done: DataStore backend with retries, session lock, autosave and shutdown save (Studio uses the memory backend).
- ~~Bank coins have nothing to spend on yet.~~ Done: permanent Cosmetics Shop.

## Seen during the mechanics pass (presentation only)

- Pieces sometimes lie down on the board after a minigame (seen at final standings). Bots are stood up when placed; players' clients stand themselves up while the board is shown. Still happens occasionally.
- During the turn-order roll the camera frames the board centre, so the pieces at Start are off-screen.
- Order-roll results are only text in the standings rows ("Rolled 5, then 3"). There's no dice.
- Item buttons are plain text tiles above ROLL. There are no item icons, no description tooltip, and the swap-target prompt is a list of names.
- The bonus card has no reveal animation, and the three standings stages are the same plain card.
- Bank coins only show in the waiting-room info line and on the final card.

## Seen during the mechanics foundation pass (2026-10-15)

- ~~Action-button key hints ("[One]") still show on phones when the emulator reports a keyboard.~~ Fixed: no key hints on any touch screen.
- Duel spaces use dice when no Duel minigame is registered. There's only one Duel minigame (Quick Draw) so far.
- Bullseye's marker moves via server-side part CFrames, so it can look steppy at 20 Hz replication. A client-side sweep would be smoother. Scoring is unaffected (server clock).
- Reaction and timing minigames (Quick Draw, Bullseye) judge presses on the server clock, so high-ping players are slightly late. Consider latency compensation later.
- Fork prompt labels are two lines ("Main road / Crown in 9 · -3 +3 GIFT"). They work, but want icons.
- MAP panel is a text list. A minimap with tile colours and piece markers would be clearer.
- ~~No board picker until there's a second board.~~ Done: Magical Festival Island is the second board and the picker shows both.
- ~~Bank coins still have nothing to spend on.~~ Done: Cosmetics Shop.
- Leaving and rejoining with a real player wasn't tested with real DataStores (Studio uses memory; the DataStore layer is covered by fake-store unit tests).

## Cosmetics Shop (2026-10-16)

- Card "hero" is a flat colour swatch. Needs a real rendered image per item (style guide: one big clear hero image per card).
- Client preview (`ShopScreen`) duplicates the server's cosmetic drawing code (`CosmeticService`). Move both to one shared drawer when cosmetics get real models.
- The shop's bank balance refreshes on purchases, equips and end-of-match payouts only (no live push for other changes).
- The BUY → PAY confirmation lasts 3 s; fine on touch but untested with a gamepad.

## Trail Tangle (2026-10-16)

- Rounds in Studio ended by last-rider-standing at 20–31 s (Normal/Hard bots, one player); none reached the 35 s limit. Fine by the rules, but if rounds should run longer, try a 28×28 grid or a gentler ramp.
- Riders are small from the steep overhead camera (on phones especially). The colour highlight helps; a bigger head marker or arrow showing heading would read better in the visual pass.
- The speed-up warning is the normal toast. A short on-screen pulse or sound would be clearer.
- No pickups yet (optional in the brief; the core game stands without them).
- The lune headless sim (`tests/sim.luau`) still can't run here (lune not installed); Trail Tangle's rules are covered by `tests/unit/TrailTangleTests`.

## Bumper Bout (2026-10-16)

- Bot-vs-bot bouts ran 10–11 s with frequent bumps before the dash cooldown went from 1.6 s to 2.0 s; a time-limit bout ran the full 18 s. A player who stands still is pushed off by a bot in 4–8 s. Watch real players' bout lengths against the 12–20 s target.
- Characters are small from the overhead camera, especially on phones (the platform is fully framed). The dash cue is an outline and the impact flash a short white fill; a clearer dash trail would read better in the visual pass.
- The round timer reads 0:00 during sudden death (the status line says "Sudden death!"); there's no countdown for those extra seconds.
- Hit detection uses the server's view of player positions, so on a laggy connection a lunge can connect or miss slightly differently from what the attacker saw. Lag compensation is a later improvement.

## Waiting room (2026-10-18)

- ~~SHOP button off-screen and unreachable on short screens.~~ Fixed: the card is now a header (title, countdown, SHOP), a scrolling settings body and a fixed START / waiting column, sized to the screen. Measured: iPhone 17 Pro landscape card y 67–368, x 119–629 (between thumbstick and jump), SHOP 107×44; iPhone 7 card y 66–361, SHOP 89×44; 1301×616 window card y 257–603, SHOP 115×44, no scroll; HD 1080 card y 660–1064, SHOP 135×52, no scroll. Bounds are checked in `tests/unit/ModeTests` ("waiting-room card fits every landscape screen").
- The settings scrollbar track shows even when nothing needs scrolling (desktop). Cosmetic only.
- Phone taps can't be injected under Studio's device emulator, so the phone check was by measured bounds, mouse-wheel scrolling and screenshots; real SHOP / START / BUY / wear clicks were done in the plain desktop window. The non-host view (waiting note instead of START) was checked by logic only.
