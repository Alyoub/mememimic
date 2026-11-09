# Meme Mimic

A pass-the-phone party game for iPhone and iPad. Each round everyone hears the same weird sound, takes a turn imitating it into the microphone, and gets an on-device score out of 100. Built with SwiftUI and a live RealityKit stage.

## Requirements

- Xcode 26 or later with the iOS 18+ SDK
- An iOS 18+ simulator or device (3D stage uses `RealityView`)
- Microphone access for live takes; a labeled demo take works without it

## Run

Open `Meme Mimic.xcodeproj`, pick the `Meme Mimic` scheme and a simulator or device, then press **Run**. On a simulator the first launch compiles RealityKit shaders, so the stage can take a few seconds to appear.

```sh
xcodebuild -project "Meme Mimic.xcodeproj" -scheme "Meme Mimic" \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Game loop

```
home → crew (1–8 players, unique characters, colors, 1/3/5 rounds) → sound packs
  → per round, per player:  handoff → listen (2 plays) → 3·2·1 → record → judged → reveal
  → round recap (rank changes) → … → podium
```

- Everyone in a round copies the same prompt, so scores are directly comparable.
- The starting player rotates each round.
- Recording stops automatically about a second after the player goes quiet, or at a time cap.
- A take that is too quiet to judge is not scored; the player just goes again.

## Scoring

`VoiceAnalyzer` compares the take with the prompt clip entirely on-device:

- **Pitch**: relative pitch contour (semitones around each sound's own median), so a deep voice copying a high whistle is judged on the shape, not the register.
- **Rhythm**: loudness envelope.
- **Length**: active duration.

Contours are aligned with banded dynamic time warping, so starting late or dragging a note is forgiven. Offline checks against synthetic takes: correct copies (any register, late or slow) score 83–99, a different prompt scores 3–65, noise 3–7. Real voices haven't been calibrated yet; the weights live in `VoiceAnalyzer.score`.

## Sounds

Prompts are meme clips from `mp3/` (21 files, three packs: Meme Reactions, Silly Voices, Worldwide & Wild). `art/prepare_clips.swift` turns each into a short game prompt in `EchoBloom/Sounds/`: mono 44.1 kHz AAC, silence trimmed, at most 4.5 s (longer clips keep their earliest, loudest stretch), faded and level-matched:

```sh
swiftc -O art/prepare_clips.swift -o /tmp/prepare_clips && /tmp/prepare_clips mp3 EchoBloom/Sounds
```

Pack names and hints live in `SoundLibrary.packs`. To add a meme, drop the mp3 in `mp3/`, re-run the script, and add a `meme(...)` line.

**Licensing:** many of these clips are third-party audio (TV, film, social media). They're fine for private play and testing, but need licensing or replacing before any public or App Store release.

## Project layout

```
EchoBloom/
  EchoBloomApp.swift        App entry
  Game/                     GameModel (state machine), models, sound packs, clip loading, cue synth
  Sounds/                   Prepared meme clips (.m4a), from mp3/ via art/prepare_clips.swift
  Audio/                    AudioEngine (playback, mic off the main thread), VoiceAnalyzer
  Stage/                    RealityKit stage: StageDirector, MascotRig (skeletal clips + springs), meshes
  Models/                   The 17 characters, exported from chars/ by art/export_mascot.py
  UI/                       Theme + components, RootView, one file per screen
EchoBloomUITests/           Full match, home lineup, character picker, quitting, live recording
```

The app group is folder-synchronized: new files under `EchoBloom/` are picked up automatically.

## Characters

The host picks a character by swiping the lineup on the home screen; every player can pick one on the crew screen. All 17 are Quaternius models (CC0 public domain, see `art/BaseCharacter-LICENSE.txt`) kept in `chars/`. They share one 23-bone skeleton and one set of animations.

| In app | Source file in `chars/` | In app | Source file in `chars/` |
|---|---|---|---|
| Sand Ninja | `Ninja_Sand_Female.blend` | Goblin | `Goblin_Male 14.50.40.blend` |
| Classy | `OldClassy_Female 14.50.40.blend` | Kimono Gal | `Kimono_Female 14.50.40.blend` |
| Wizard | `Wizard.blend` | Kimono Guy | `Kimono_Male 14.50.40.blend` |
| Witch | `Witch.blend` | Pirate Gal | `Pirate_Female 14.50.40.blend` |
| Zombie Gal | `Zombie_Female.blend` | Pirate Captain | `Pirate_Male 14.50.40.blend` |
| Zombie Guy | `Zombie_Male 14.50.40.blend` | Soldier | `Soldier_Female 14.50.40.blend` |
| Chef | `Chef_Male 14.50.40.blend` | Business Boss | `Suit_Female 14.50.40.blend` |
| Elf | `Elf 14.50.40.blend` | Horned Viking | `VikingHelmet 14.50.40.blend` |
| Viking | `Viking_Male 14.50.40.blend` | | |

`art/export_mascot.py` keeps each file's colors, lays the clips the game uses (Idle, Walk, Jump, Victory, Defeat, RecieveHit) end to end, and writes `EchoBloom/Models/<Asset>.usdz`, where `<Asset>` is the `CharacterKind` raw value capitalised (`pirateGuy` → `PirateGuy`):

```sh
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b "chars/Pirate_Male 14.50.40.blend" -P art/export_mascot.py -- EchoBloom/Models/PirateGuy.usdz
$B -b "chars/Pirate_Male 14.50.40.blend" -P art/character_preview.py -- \
   EchoBloom/Assets.xcassets/Character-PirateGuy.imageset/PirateGuy.png Idle 0 portrait
```

Every character gets big glossy icon-style eyes from `art/eyes.py`, added during export and preview.

To add a character: export it, render its portrait into a new imageset, and add a case to `CharacterKind` with its display name. The script prints each clip's time range; `MascotRig.Clip` must match them (identical for every character so far). In play, game state picks the clip (good score → Jump, winner → Victory, low score → Defeat, tap → RecieveHit, moving → Walk) and springs add hops, squash with the mic level, and leaning in to listen.

## Tests

```sh
xcodebuild test -project "Meme Mimic.xcodeproj" -scheme "Meme Mimic" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`-ui-testing` (set by the tests) shortens the count-in and skips saving the crew.

## Privacy

The app uses Google Mobile Ads and downloads its ad/audio switches from the remote JSON documented in `docs/ADS-REMOTE-CONFIG.md`. On first launch it requests Apple tracking authorization, then presents Google's consent form when UMP says one is required. A privacy-choices row appears in Settings when UMP requires an entry point.

Recordings stay in memory for the current turn only and are never written to disk or uploaded by the game.
