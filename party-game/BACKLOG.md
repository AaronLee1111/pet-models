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
- Cosmetics are data only: nothing is drawn (hats, trails, emotes), and there's no inventory/equip UI or equip remote yet.

## Mechanics to revisit

- Turn order is a random shuffle; Mario Party-style "everyone rolls for order" is not built.
- No board items (double dice etc.), no Crown-steal, no bonus awards at match end.
- Bots buy the Crown whenever they can afford it and pick forks at random; shop choices use a coin reserve scaled by skill.
- Late joiners watch until the next match; they can't take over a bot's seat mid-match.
- Players who leave are replaced by a bot permanently (rejoining doesn't get the seat back).
- `tests/sim.luau` (lune) predates the board game and still expects the old lobby → vote loop; lune isn't installed on this machine. Board rules are covered by `tests/unit` instead.
- No persistence: coins/Crowns are per match, cosmetics per session (by design for now).
