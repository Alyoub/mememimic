# Ads and remote configuration

The app reads `https://alyoub.github.io/mimic-config.json` at launch and keeps the last valid response as an offline fallback.

Recommended JSON:

```json
{
  "adsEnabled": true,
  "appOpen": true,
  "interstitial": true,
  "rewarded": true,
  "interstitialInterval": 5,
  "realSound": false,
  "link": "https://apps.apple.com/app/idYOUR_APP_ID"
}
```

- `adsEnabled`: master switch for ad loading and presentation.
- `appOpen`, `interstitial`, `rewarded`: turn each ad format on or off. A missing key leaves that format on. Turning `rewarded` off makes Settings and the winner reveal open with no ad.
- `interstitialInterval` (alias `interstitialEvery`): preload the normal interstitial on tap `N - 1` and present it at the next safe break on tap `N`. Values below `2` disable tap-count interstitials.
- `realSound`: when `true`, use the bundled MP3 prompts; when `false`, use the original runtime-synthesized alternatives documented in `AUDIO-SOURCES.md`.
- `link`: the URL passed to the iOS share sheet when the user taps **Share the app**. The last valid HTTP or HTTPS URL is cached for offline use.

Key matching is case-insensitive and ignores punctuation. The decoder also accepts legacy aliases such as `normalAdTaps`, `tapCount`, `showAds`, and `useRealSounds`, including when the values are nested in another JSON object.

A rewarded ad plays before Settings opens and before the winner reveal. The app continues whether or not the player watches to the end.

Debug builds use Google's test unit IDs for rewarded, app-open, and interstitial ads. Release builds use the production unit IDs configured in `AdsManager`.

## Debugging

Run the Debug scheme from Xcode and filter the console for `[MemeMimic Ads]`. The log reports remote configuration, ATT and UMP status, SDK initialization, every load attempt and error, tap counters, presentation decisions, impressions, clicks, and dismissals. These diagnostics are compiled out of Release builds.
