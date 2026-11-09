# Mimic Party observation notes

Date observed: 2026-10-18

## Evidence boundary

These notes separate direct runtime observations from public listing claims and unresolved questions. The installed application was first launched as an iPhone-on-Mac app, then observed on a connected physical iPhone 13 Pro Max through Xcode's Device Hub. No packaged art, audio, source code, or extracted resources are used by the prototype.

### Directly observed

- The first interactive screen is titled **“PICK YOUR COLOR.”**
- Supporting text says the character represents the player in the room.
- A single animated 3D mascot stands on a lit stage and holds a microphone.
- Left/right circular arrow controls flank the mascot.
- Five color choices are visible: green, blue, red, yellow, and purple.
- Selecting a color changes the mascot body color and selected-state ring.
- A globe control appears near the heading, suggesting language selection.
- A green continue control is rendered beneath the color controls.
- On the macOS compatibility build, the five color controls overlap the continue control. The physical-iPhone layout does not have this overlap.
- Continue opens a required name-entry screen. Its supporting text says the name will appear on the player's card.
- Completing onboarding opens a home screen with the chosen mascot, a small profile card, and one prominent Play action.
- Play offers two modes: **Online** (everyone on their own phone) and **Pass the Phone** (everyone on one phone).
- Pass the Phone is labeled for **2 to 8 players** and says the phone goes around the group.
- The local setup begins with the onboarding player already present. Players can be added, removed, and reordered with up/down controls.
- A Packs control reports **36 of 36 packs selected** in the observed state.
- The pack selector has search, select-all/deselect-all controls, a create-your-own-pack action, per-pack selection, and a Ready action.
- Pressing Start after configuring two players presents a host-access subscription screen before any playable round is shown. The screen advertises friend access, unlimited games, and all categories.
- After the user completed the purchase, the game advanced to **Round 1/3** and displayed a private handoff screen: “Pass the phone to [player]” with a Let’s Go action.
- Pressing Let’s Go starts a visible countdown and triggers the system microphone-permission prompt before recording can continue.
- The permission explanation says the microphone is used to record voice imitations during the match.
- After permission is granted, the game displays the reference phrase with a **PLAYING** state and animated waveform.
- The recording state displays **REC**, a countdown, and an animated waveform while capturing the imitation.
- A completed take receives a score out of 100.
- After both observed players complete a round, a ranked round scoreboard appears with a **Next Round** action.
- Later captures confirm the same handoff, playback, recording, and scoreboard structure continuing into Round 2.
- The observed match ends on a **GAME OVER!** screen with a final ranking plus **Play Again** and **Leave** actions.

Mac-compatibility captures are stored in `captures/01-color-picker.png` through `captures/06-right-arrow.png`. Physical-device captures are stored in `captures/iphone-01-color-picker.png` through `captures/iphone-23-round2-flow.png`. REA runtime observations are retained in `captures/rea-evidence.json`; the successful color interaction is Evidence `ev_a4ca6a7496a81a39d616b5375bd07d1d929d133162799ab4dfbb3a45fa48cbd5`.

### Public App Store listing claims (background, not independently confirmed)

- The described loop is: choose a character, choose sound categories, hear a sound, imitate it, receive a match score, compare attempts, and rank on a leaderboard.
- The listing describes a prompt/listen/imitate/score loop. The local pass-the-phone version of that loop has now been observed directly through multiple rounds.
- Microphone use is required for recording imitations.

### Unresolved questions

- How are rounds, categories, and difficulty configured?
- Is every player given the same prompt in a round?
- Can the reference sound be replayed, and can a player retry a recording?
- What audio features drive the score, and how is silence/noise handled?
- Are recordings replayed to the group before or after scoring?
- How are ties resolved and how many rounds make a match?
- Does online mode use room codes, invitations, accounts, or a mixture of these?
- What can a custom pack contain, and can it be shared?
- Are there accessibility alternatives when microphone access is denied?

## Native implementation decisions

The native prototype deliberately makes its own choices where evidence is absent:

- 2–8 pass-and-play players, matching the now-observed local range.
- Three rounds by default; every player receives one prompt per round.
- Reference sounds are generated live from original `AVAudioEngine` recipes.
- One reference replay and one recorded attempt per turn.
- Local scoring compares energy contour, voice texture, and active duration; it does not perform speech recognition.
- A round recap appears after every player has taken a turn, followed by a final podium.
- Microphone denial enables a clearly labeled demo-take fallback so the full loop remains testable.
- Networking is limited to Google Mobile Ads consent/ad requests and the remote app configuration; online multiplayer is not included.

