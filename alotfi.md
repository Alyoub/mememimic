# Echo Bloom — Product Notes

## Product

An original party game for iOS 18+. One device, 1–8 players. Each round everyone imitates the same synthesized sound and gets a score out of 100. The visual identity is original: a night-sky stage, a neon ring that takes the active player's color, and procedurally built 3D "Bloom" mascots with a sprout on top. No third-party code, assets, or audio.

## Experience principles

- **The stage never reloads.** One RealityKit scene lives for the whole session. Screens move the camera and the cast instead of swapping views, so every transition is continuous.
- **Every player is a character.** Each player picks one of eight colors and gets their own mascot. The active player stands in the spotlight; everyone else watches from the wings and reacts to the score.
- **The mascot mirrors the game.** It puts on headphones to listen, bounces on the count-in, opens its mouth with your voice while you record, and cheers or slumps at the score. Tap it to make it hop and spin.
- **Feedback is physical.** Chunky buttons press down, the count-in ticks with haptics, the score counts up with a final thump, and loud moments ripple shockwaves across the stage.
- **Honest scoring.** Demo takes are always labeled. A take that is too quiet isn't scored; the player just goes again.

## Rules (current)

- 1–8 players, 1/3/5 rounds, one or more of three packs (12 prompts).
- Same prompt for everyone in a round; the starting player rotates each round.
- Two listens per turn, one scored take; auto-stop on silence.
- Ties share a rank; ties for first show "It's a tie!".

## Open items

- Calibrate scoring weights against real voices (synthetic checks pass; see README).
- Pick a reverse-DNS bundle identifier before shipping (`partygameios` today).
- More packs, and a custom-pack recorder.
