# Aurora (Flutter)

Apple Music-style player for YouTube Music, JioSaavn and local files.
Targets: Android (incl. Chromebook), iOS, macOS, Windows, Linux, web.

## v2 (ultimate)

- **Six looks, switchable any time** (Settings > Appearance, or Profile): Glass, Orbit, Sleeve, Sky Glass, Verdant Glass, Editorial. Each has its own backdrop, navigation bar, Home layout, shelf titles and card shapes. Style, accent colour (20), player layout and icon are stored in settings only, so playlists, history, likes and downloads are never touched.
- **Five player layouts**: Classic, Vinyl (spinning record), Orbit (round art in a progress ring), Poster (full-bleed art), Editorial. "Match style" follows the UI style.
- **Profile**: name, photo (stored on the device), listening hours, streak, top artists and songs, shortcuts.
- **App icons**: 24 icons built by `tools/build_icons.py` from the artwork folder (white backgrounds removed from the turntable and the halftone hands, everything squared and sized, third-party brand marks left out). Android switches the launcher icon (and optionally the launcher name) through activity-aliases written by `tool_setup.py`; iPhone uses alternate icons added by `tool_setup_ios_icons.rb` (iOS cannot change the home-screen name).
- **YouTube Music charts and playlists** on Home (`lib/sources/ytmusic_browse.dart`): top charts with rank, trending playlists, new albums; playlist and album pages load through the same pipeline. The shelves are cached and the pipeline is warmed at start-up (`Backend.warmUp`, `Catalog.preload`).
- **Downloads**: three-dot menu > Download; offline songs play from the file on every platform (`lib/core/downloads.dart`); Downloads page, auto-download for liked songs.
- **Automix / DJ**: DJ style (Smooth, Club, Quick cut), phrase-aligned starts (4-bar), short blends on key clashes, tape-stop on quick cut, live "Mixing into..." chip, **Mix now** button (Dart-driven engines: iOS, macOS, Windows, Linux). The Android Kotlin mixer keeps its own schedule.
- **Sleep timer** (15-90 min with a 15 s fade, or end of song).

Not verified by a real build: this version was type-checked with the Dart analyzer against the Flutter framework sources, never compiled for a device. Run the GitHub Action and report anything that breaks.

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
`.github/workflows/build-all.yml` (Android, iPhone, macOS, Windows, Linux/Chromebook) builds `Aurora-no-widget.ipa` and `Aurora-widget.ipa` on a macOS runner. Install
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
## v8: YouTube on iPhone
When direct extraction fails (bot check / 403), YouTube tracks on iOS/macOS fall back to YouTube's official embedded
player in a hidden WKWebView (`lib/engine/yt_mobile_transport.dart`, `webview_flutter`). Limits: videos with embedding
disabled fail, audio may pause when the app is backgrounded/locked, no EQ/Automix filters on this path. Not compiled in
the authoring sandbox.

## v9
- YouTube on iPhone: Dart downloads the AAC stream (or the muxed MP4's audio) through its own HTTP stack, the native engine plays the finished file; if every link fails the same song is found on another source, and finally YouTube's embedded player is used. Failures show a short trace in brackets.
- Automix: auto length is a full 30 s blend on whole bars (tempo-matched, easing back to B's tempo); a length you set is used exactly.
- Progress bar draws a loudness waveform (iPhone/desktop from the Automix analysis, Android from the native analyzer).
- Siri / Shortcuts: play <song>, play music (asks), liked songs, playlists, pause, resume, next, previous, like, what's playing.
- Native iPhone engine rebuilds itself after a long pause (cancelled reader / stopped engine).
- v9.1: library backup/restore (Settings), queues built around the played song (search, history, home), stronger speaker protection (-6 dB headroom, 24 dB/oct high-pass, limiter -6 dB on Android).
- v9.2: Automix keeps fetching the next online song from 20% into the current one, explains in Settings why a blend was skipped, waveform bar is optional (off by default).

## v10
- YouTube pipeline rebuilt: InnerTube (iOS client + BotGuard PO token minted in a hidden WKWebView, then ANDROID_VR clients), Dart downloads the audio, native engine plays the local file. Piped/Invidious removed. Run Settings -> YouTube diagnostics if a song fails and send the bracketed trace.
- Visualizer on iOS is now a real 32-band FFT of the live mix (vDSP), not an animation.

## v10.1 (pipeline re-based on Metrolist's live client benchmark, Nov 2026)
- Metrolist's `innertubex` shows IOS is now SABR-only and Android VR often 403s after the first range. The plan is now VISIONOS 0.1 (music.youtube.com player endpoint, tokenless, needs visitorData) first, Android VR as fallbacks. No BotGuard start-up in the normal path.
- visitorData comes from `youtube.com/sw.js_data`, then the music.youtube.com homepage, then visitor_id.
- Siri phrases use the app name ("Music"): "Play <song> on Music".

## v10.2
- iPhone: YouTube now resolves AND downloads in Swift (`AuroraYouTube.swift`, VisionOS-first, per-video client health), Dart pipeline remains as fallback.
- Seeking a downloaded YouTube (fragmented MP4) song no longer ends it: falls back to decode-and-skip.
- Lock screen / Control Centre handled natively (`AuroraNowPlaying.swift`): play/pause work with the app asleep.
- Visualizer: spectrum events now handled globally and the tap re-arms itself if it stops.
- v10.3: visualizer spectrum is computed from the decoded samples at the playback position (no mixer tap), 30 Hz.
- v10.4: round-thumb slider (Instagram/WhatsApp style) with time bubble; Settings -> Round slider.

## 2.1 changes

- **Apollo UI** (new default): Apollo-style home with chart hero, quick picks, chart songs, shelves, artists. Other UI styles keep their own homes. Sections can be hidden in Profile > Appearance > Backgrounds > Home layout.
- **Profile hub**: Appearance (App icon, Backgrounds, Themes, Mini player button, Widget Theme, Smooth animations), Account, Audio, Backup & Restore, Support.
- **Downloads**: songs and cover art are saved in the app folder, stored by relative file name (survives app updates / path changes), retried 3 times, and always played from the local file first, so they work offline.
- **Android automix** now analyses streamed songs (bpm, bar grid, intro/outro, loudness) and does beat-matched, bar-aligned, loudness-trimmed blends with DJ styles like the Dart mixer.
- **Audio output** picker on Android (device list + system switcher) and iPhone (AirPlay route picker).
- **iPhone add from library**: copies picked files into Documents/Music and rescans on launch; Music-library and Files pickers; the missing `NSAppleMusicUsageDescription` is injected.
- Recent searches (last 5), brand icons (Soundstar, Spotify, Apple Music), widget themes.

Nothing here was compiled on a device: the build environment had no Flutter/Xcode/Gradle, so expect a first-build fix-up pass.

## 2.1.1

- App is named **Keystone**; the Keystone icon is the default launcher icon (Aura is now an alternate).
- Downloads: saved at **Best** quality unless changed in Audio > Offline > Download quality; every attempt asks for a fresh link (up to 3 tries, 150 s to resolve); cut-off transfers are discarded and retried; iPhone's natively-downloaded YouTube files are copied into the app library (this was why iPhone downloads failed).
- Audio output button added to the phone full-player tool row (also: mini-player button, Profile > Audio, desktop sidebar).
- Removed the logo from the Library "listening experience" cards.

## Siri (iPhone)

Siri needs the app name in the phrase: "Play <song> on Keystone", "Play music by <artist> on Keystone", "Play music on Keystone" (Siri then asks which song, any song works), "Play Keystone", "Play my liked songs on Keystone", "Pause Keystone", "Next song on Keystone". Open the app once after installing so Siri can learn the phrases; song, artist and playlist names are refreshed from your library, liked songs, recents and downloads. Plain "Hey Siri, play <song>" (no app name) needs Apple's SiriKit media entitlement, which sideloaded apps cannot have.

## Visualizer & kinetic lyrics

Player toolbar > sparkle button. Code in `lib/visualizer/` (spectrum engine, kinetic lyrics, lyrics disk cache, screen) and `shaders/velour_voxel_engine.frag` (declared under `flutter: shaders:` in pubspec). Android reads the native engine's real spectrum and beat envelope; other platforms use a tempo-locked rhythmic fallback. If the shader cannot load, a gradient backdrop is shown.

## 2.3.0
- Keystone keycap logos, VoxelWall-style visualiser (5 GPU scenes, presets, intensity/speed), Live Activity lock-screen poster on iPhone.
- Windows-style desk player on phones (toggle in Appearance), real vinyl deck with tonearm, cassette and grain-poster players.
- Liquid Glass tab bar (Glass style), new Audius source.
