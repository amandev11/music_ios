# Aurora (Flutter)

Apple Music-style player for YouTube Music, JioSaavn and local files.
Targets: Android (incl. Chromebook), iOS, macOS, Windows, Linux, web.

## Setup (once)

    flutter --version          # needs >= 3.29 (Kotlin-DSL Android template) and Dart >= 3.5
    python3 tool_setup.py      # flutter create + overlays the native Android engine
    flutter pub get

## Run

    flutter run -d android | ios | macos | windows | linux | chrome
    flutter build web --release        # host over HTTPS

## How playback works per platform

| Platform | Engine | Sources | Beat detection | Spatial audio |
|---|---|---|---|---|
| Android / ChromeOS (Android app) | native Media3 + ONNX (Kotlin, `native/android`) | JioSaavn + YouTube (NewPipe) + MediaStore | yes (Beat This!) | yes (system spatializer) |
| iPhone / iPad | native AVAudioEngine (Swift, `packages/aurora_pcm/ios/Classes`): 10-band EQ, time-pitch, DJ filters, HRTF spatial, peak limiter | JioSaavn + YouTube + picked files/folders | yes (offline analysis, AVAssetReader) | yes (binaural virtual speakers) |
| macOS | media_kit (mpv) | same | yes (offline analysis) | widening filter |
| Windows, Linux | media_kit (mpv) | same | yes (offline analysis) | widening filter |
| Web | HTML audio + YouTube IFrame player | YouTube via Invidious search; JioSaavn only through a CORS proxy | no | no |

iPhone falls back to the mpv engine automatically if the native engine cannot start; Settings has a
"Compatibility audio engine" switch.

**Speaker protection** (Settings, on by default): sub-bass high-pass (~30 Hz), peak limiter and ~3 dB of
headroom on every engine, so loud masters or EQ boosts never clip into a speaker or home-theatre receiver.

**YouTube quality** has an Auto mode that follows the measured download speed.

## Building iOS on GitHub (no Mac needed)
`.github/workflows/ios.yml` builds `Aurora-no-widget.ipa` and `Aurora-widget.ipa` on a macOS runner. Install
with AltStore or SideStore using a free Apple ID (they refresh the 7-day signature automatically).

## Web notes
- Set the proxy URL and Invidious hosts under Settings. `tools/cors_proxy_worker.js` is a ready Cloudflare Worker (allow-listed hosts only).
- Public Invidious hosts come and go; swap in one that works.
- Local files on web are held in memory for the session.

## macOS
The sandbox forgets folder access between launches unless the folder is re-picked. For a personal build, remove `com.apple.security.app-sandbox` from the entitlements.

## Licence
Derived from BitChord (GPL/AGPL) and links NewPipeExtractor (GPL-3) on Android: ship as GPL-3.


## v2 changes
- App name is **Music**; icon from `assets/icon/icon.png` (generated for every platform by `python tool_setup.py`).
  The icon is Apple's Music mark: personal use only, do not distribute.
- Apple Music iOS 26 layout: Home (Top Picks, Recently Played, shelves), New, Library, Search (artist on top), artist pages, floating tab bar that collapses on scroll.
- Equalizer: Settings > Equalizer (10 bands, presets). Works on Android and desktop/iOS (mpv). Not available on web.
- Automix: Settings > Automix (crossfade length slider) and a toggle in the queue. Not available for YouTube on web.
- YouTube silence fix: per-client googlevideo headers, one retry, error shown as a snackbar.

## Run (Windows)
    python tool_setup.py
    flutter pub get
    flutter run -d windows
(Enable Developer Mode in Windows settings.) Nothing here has been compiled by the author.

## v3: desktop-style layout everywhere
Sidebar + top transport bar + now-playing pill, queue/lyrics side panels, Explore moods, Library listening stats,
History, Local Music, user playlists (stored on this device), audio output picker, volume, audio quality.
Phones get a bottom tab bar. Not implemented: sign-in/Listen Together/Downloads/Discord/Last.fm.

## v4
Real artist pages (Deezer + MusicBrainz + Wikipedia), light/dark/system themes, 50% mist glass tinted by the
current artwork, particle grid background, word-by-word lyrics (estimated timing), playlist import
(Spotify / Apple Music / YouTube / Deezer links, CSV or pasted lists), multi-client YouTube stream resolver with
reachability check, new Home. Needs internet on first run for the Playfair Display wordmark font (google_fonts).

## Artist discography
Artist pages load Deezer first, then merge every MusicBrainz album/EP/single (cover art from Cover Art Archive). `mb:` ids open MusicBrainz releases.

## Taste, likes and Automix
- **Liked Songs**: heart on every row, the player and the ⋯ menu. A pinned "Liked Songs" playlist always sits first in the sidebar and Library.
- **Taste model** (`lib/core/recommender.dart`, on-device): plays, skips (<15 s) and likes build artist affinity with a 21-day half-life. It drives *Made for you* on Home, Shuffle on playlists, and **Autoplay** (Settings), which refills the queue when it is nearly done.
- **Automix**: equal-power smoothstep crossfade, length capped at 25 % of either song, shortened for consecutive tracks of the same album.
- **YouTube**: YouTube Music search (InnerTube WEB_REMIX, same endpoint as ytmusicapi), then stream clients (androidVr, ios, tv, safari), then Piped / Invidious fallbacks.

## Automix Pro (desktop, iOS, macOS)
`lib/engine/automix/`: a hidden mpv instance decodes each song to 11 kHz mono PCM (`pcm_decoder_io.dart`); `dsp.dart` finds BPM (comb search with sub-frame phase), the bar line, Camelot key (Krumhansl chroma), leading/trailing silence and loudness. `planner.dart` picks the blend (16 beats when keys are compatible, 8 otherwise, capped by "Max blend"), snaps it to A's bar line, starts B on its own bar line, time-stretches B to A's tempo (within 8 %) and eases it back. `queue_engine.dart` runs it with a bass swap (mpv `af-command` high-pass/low-pass), loudness trim and a one-shot phase correction. Android keeps its native engine (smoothstep + length caps only); browsers use the plain crossfade.

## Custom transitions and diagnostics
- Track ⋯ menu → **Custom transition…**: per-song mode (Auto, Crossfade, Beat-matched, No blend) and length up to 30 s. Applies on desktop/iOS/macOS; Android's native engine uses the global Automix settings.
- Settings → **YouTube diagnostics** tests YT Music search, the direct InnerTube clients, youtube_explode clients and the Piped/Invidious fallback in one run.
- Word-by-word lyrics and DJ filters are opt-in (Settings).

## YouTube on desktop (order of attempts)
1. InnerTube `player` with ANDROID_VR (1.65.10, then 1.60.19), then IOS. A candidate counts only after its audio is fully downloaded to a temp file (googlevideo refuses ranged transfers without a PO token for some clients).
2. youtube_explode clients, then Piped/Invidious.
3. The same song matched on JioSaavn.
4. Windows only: YouTube's embedded player in a hidden WebView2 (`engine/yt_desktop_io.dart`). Needs the WebView2 runtime (preinstalled on Windows 11). Videos whose owners disable embedding still fail.

## v5: crash fixes and widgets
- **Android startup crash fixed**: spatial audio was applied to ExoPlayer from a background thread
  ("Player is accessed on the wrong thread") on every launch. It now runs on the main thread; all native
  jobs have exception handlers, bridge replies can no longer throw, R8 keep rules cover NewPipe/Rhino/protobuf,
  and audio_service's Android components are removed from the manifest (they stole media buttons).
- **Dart startup is crash-proof**: error handlers, a splash screen, a 20 s startup timeout and a retry screen with the log.
  libmpv (media_kit) is no longer loaded on Android.
- **Android widget**: long-press the home screen > Widgets > Music (resizable, 1x1 compact or 4x1). Also flagged for
  lock-screen hosts that support widgets (Android 16 tablets). Phone lock screens show the media notification instead.
- **iOS widgets**: home screen (small, medium) and lock screen (inline, circular, rectangular).
  After `tool_setup.py` + `flutter pub get`, on a Mac run `ruby tool_setup_ios_widget.rb`, then set your Team on the
  Runner and AuroraWidget targets (App Group `group.com.aurora.music` must be enabled for both).
- Not included: macOS and Windows widgets (see notes in the chat).

## v6
- Recently played works again on Android: queue snapshots carry no stream address, so the native bridge now rebuilds it from the media id.
- Home greeting follows the time of day (night / morning / afternoon / evening) and updates while the app is open. Settings > Greeting > Time zone picks a fixed UTC offset or follows the device.
- Automix beat analysis on iPhone/iPad/Mac decodes with AVFoundation through the local plugin `packages/aurora_pcm` (falls back to mpv). Settings > Automix shows whether beat matching is active.

## v7
- Settings > Song transitions: Off / Crossfade / Automix. Crossfade is a plain fade of 1-12 s (no beat matching, no filters, no analysis).
  Automix picks its own length per song (about 16 beats, 6-18 s, on whole bars when the beat is known; 4-9 s otherwise) or a fixed maximum when "Pick the length for me" is off.
- Search plays a taste-based queue.
