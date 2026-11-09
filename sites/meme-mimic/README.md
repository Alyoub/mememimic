# Meme Mimic for the web

The iOS game (`EchoBloom/`) rebuilt as a static website in `dist/`. No build step: plain ES modules, three.js for the 3D stage, Preact for the screens. Everything is vendored, so nothing loads from a CDN except the Nunito font.

## Run locally

```sh
cd sites/meme-mimic/dist
python3 -m http.server 8080      # or any static server
```

Open http://localhost:8080. The microphone only works on `localhost` or `https://`. Add `?debug` to the URL to get `window.__mm` (game, stage, audio) in the console.

## Deploy

Upload the contents of `dist/` to any static host. `.openai/hosting.json` already points at `dist`.

After changing files, bump `VERSION` in `dist/sw.js` (and the `?v=` on `css/app.css` in the HTML files) so returning players get the new build instead of their offline copy.

## What's where

```
dist/
  index.html          Game shell, splash, and the about/FAQ section below the game
  css/app.css         Theme (from UI/Theme.swift), every screen, the about pages
  js/main.js          Boot, layout (phone / tablet / side panel), keyboard, splash
  js/game.js          GameModel.swift: crew, packs, rounds, turns, recording, scoring flow
  js/analyzer.js      VoiceAnalyzer.swift: pitch contour + rhythm + length, DTW-aligned
  js/audio.js         Clip playback (Web Audio), synthesized UI cues, mic via AudioWorklet
  js/stage.js         StageDirector.swift + MascotRig.swift in three.js
  js/ui.js            Every SwiftUI screen as a Preact component
  js/library.js       Characters, colors, the 5 packs of real meme clips, APP_STORE_URL
  sounds/             The prepared meme clips from EchoBloom/Sounds (.m4a)
  models/             The 17 characters as compressed GLB
  privacy/, support/  Web privacy policy and help pages
```

## Characters

`art/export_web_glb.py` exports a character from `chars/` with the same color pass, big eyes and six clips as the iOS export. Then compress it with meshopt:

```sh
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b "chars/Wizard.blend" -P art/export_web_glb.py -- /tmp/Wizard.glb
npx @gltf-transform/cli meshopt /tmp/Wizard.glb sites/meme-mimic/dist/models/Wizard.glb
```

The file name is the `asset` value in `js/library.js`.

## App Store link

Set `APP_STORE_URL` in `dist/js/library.js` once the iPhone app is live. Settings then shows "Get the iPhone app". It stays hidden while the value is empty.
