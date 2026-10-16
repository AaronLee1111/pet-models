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

- No Crown-steal item or event yet.
- Bot item use only looks at the Crown and the bot's own coins. It doesn't plan around other players' items or shields.
- Late joiners watch until the next match; they can't take over a bot's seat mid-match.
- Players who leave are replaced by a bot permanently (rejoining doesn't get the seat back).
- `tests/sim.luau` (lune) predates the board game and still expects the old lobby → vote loop; lune isn't installed on this machine. Board rules are covered by `tests/unit` instead.
- Persistence: profiles use the in-memory backend (lost when the server shuts down). DataStoreBackend is a documented stub. Session locking and autosave are still to build.
- Bank coins have nothing to spend on yet.

## Seen during the mechanics pass (presentation only)

- Pieces sometimes lie down on the board after a minigame (seen at final standings). Bots are stood up when placed; players' clients stand themselves up while the board is shown. Still happens occasionally.
- During the turn-order roll the camera frames the board centre, so the pieces at Start are off-screen.
- Order-roll results are only text in the standings rows ("Rolled 5, then 3"). There's no dice.
- Item buttons are plain text tiles above ROLL. There are no item icons, no description tooltip, and the swap-target prompt is a list of names.
- The bonus card has no reveal animation, and the three standings stages are the same plain card.
- Bank coins only show in the waiting-room info line and on the final card.

## Seen during the mechanics foundation pass (2026-10-15)

- Action-button key hints ("[One]") still show on phones when the emulator reports a keyboard.
- Duel spaces use dice when no Duel minigame is registered. There's only one Duel minigame (Quick Draw) so far.
- Bullseye's marker moves via server-side part CFrames, so it can look steppy at 20 Hz replication. A client-side sweep would be smoother. Scoring is unaffected (server clock).
- Reaction and timing minigames (Quick Draw, Bullseye) judge presses on the server clock, so high-ping players are slightly late. Consider latency compensation later.
- Fork prompt labels are two lines ("Main road / Crown in 9 · -3 +3 GIFT"). They work, but want icons.
- MAP panel is a text list. A minimap with tile colours and piece markers would be clearer.
- No board picker until there's a second board (picker appears automatically when `Config.Match.Boards` has more than one).
- Bank coins still have nothing to spend on (permanent cosmetics shop planned for the polish phase).
- Leaving and rejoining with a real player wasn't tested with real DataStores (Studio uses memory; the DataStore layer is covered by fake-store unit tests).
