import 'dart:typed_data';

import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../engine/ios_native_transport.dart';
import '../engine/queue_engine.dart';
import '../sources/jiosaavn.dart';
import '../sources/registry.dart';
import '../sources/stream_proxy_stub.dart' if (dart.library.io) '../sources/stream_proxy_io.dart' show nativeOnlyYoutube;
import '../sources/youtube_native.dart';
import '../sources/youtube_web.dart';
import '../engine/transport.dart' show AudioOutput;
import 'backend.dart';
import 'local_scanner.dart';

/// iOS, macOS, Windows, Linux and web. Playback runs in Dart (just_audio, or the YouTube IFrame on
/// web). There is no PCM access in these engines, so [frame] is a plain animation, not beat detection.
class DartBackend implements Backend {
  DartBackend(this.settings) {
    registry = SourceRegistry([
      if (settings.saavnEnabled) JioSaavnSource(settings),
      if (settings.youtubeEnabled) kIsWeb ? YouTubeWebSource(settings) : YouTubeNativeSource(settings),
    ]);
    engine = QueueEngine(registry, nativeIos: _useNativeIos);
    spatial.value = settings.spatialDsp;
    if (settings.spatialDsp) unawaited(engine.setSpatial(true));
  }

  final Settings settings;
  late final SourceRegistry registry;
  late final QueueEngine engine;
  final _scanner = LocalScanner();

  @override
  final ValueNotifier<LibraryData> library = ValueNotifier<LibraryData>(const LibraryData(state: LibraryState.scanning));
  @override
  final frame = AudioFrame();
  @override
  final ValueNotifier<bool> spatial = ValueNotifier<bool>(false);
  @override
  ValueListenable<PlaybackError?> get errors => engine.errors;

  @override
  ValueListenable<Snapshot> get snapshot => engine.snapshot;
  @override
  ValueListenable<Progress> get progress => engine.progress;
  @override
  bool get hasBeatEngine => false;
  @override
  bool get canAddMusic => true;
  @override
  bool get needsPermission => false;

  final List<Track> _local = [];
  /// iPhone/iPad play through the native AVAudioEngine; Settings can switch back to the mpv engine.
  bool get _useNativeIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !settings.iosCompatEngine;
  StreamSubscription<({double rms, double low})>? _levelSub;
  double _lvRms = 0, _lvLow = 0;
  DateTime _lvAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _frameTimer;
  double _phase = 0;
  _MediaSessionHandler? _session;

  @override
  Future<void> init() async {
    if (_useNativeIos) {
      if (!await IosNativeTransport.available()) {
        await engine.useMpvEngine();
      } else {
        nativeOnlyYoutube = true; // native downloads AAC straight from YouTube; no mpv, no proxy
        _levelSub = IosNativeTransport.levels.listen((l) {
          _lvRms = l.rms;
          _lvLow = l.low;
          _lvAt = DateTime.now();
        });
      }
    }
    _session = await _MediaSessionHandler.tryCreate(this);
    unawaited(_rescan());
  }

  Future<void> _rescan() async {
    library.value = LibraryData(state: LibraryState.scanning, tracks: library.value.tracks, albums: library.value.albums);
    _local.clear();
    if (_scanner.supportsFolders) {
      for (final f in settings.musicFolders) {
        _local.addAll(await _scanner.scanFolder(f));
      }
    }
    if (!kIsWeb) {
      for (final p in settings.musicFiles) {
        final t = await _scanner.readFile(p);
        if (t != null) _local.add(t);
      }
    }
    _publishLibrary();
  }

  void _publishLibrary() {
    final unique = <String, Track>{for (final t in _local) t.mediaId: t};
    final tracks = unique.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final byAlbum = <int, List<Track>>{};
    for (final t in tracks) {
      byAlbum.putIfAbsent(t.albumId, () => []).add(t);
    }
    final albums = [
      for (final e in byAlbum.entries)
        Album(
          id: e.key,
          title: e.value.first.album,
          artist: e.value.first.albumArtist ?? e.value.first.artist,
          artworkUri: e.value.first.artworkUri,
          artworkBytes: e.value.map((t) => t.artworkBytes).whereType<Uint8List>().firstOrNull,
          year: e.value.map((t) => t.year).fold(0, max),
          trackCount: e.value.length,
        )
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    library.value = LibraryData(state: LibraryState.ready, tracks: tracks, albums: albums);
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> refreshLibrary() => _rescan();

  @override
  Future<void> addMusic() async {
    if (_scanner.supportsFolders) {
      final folder = await _scanner.pickFolder();
      if (folder != null && !settings.musicFolders.contains(folder)) {
        settings.musicFolders = [...settings.musicFolders, folder];
        await _rescan();
      }
      return;
    }
    final (tracks, paths) = await _scanner.pickFiles();
    if (tracks.isEmpty) return;
    if (paths.isNotEmpty) settings.musicFiles = {...settings.musicFiles, ...paths}.toList();
    _local.addAll(tracks);
    _publishLibrary();
  }

  // ---- Playback ---------------------------------------------------------------------------------

  @override
  Future<void> playTracks(List<Track> tracks, int index, {bool shuffle = false}) =>
      engine.playTracks(tracks, index, shuffle: shuffle);
  @override
  Future<void> toggle() => engine.toggle();
  @override
  Future<void> next() => engine.next();
  @override
  Future<void> previous() => engine.previous();
  @override
  Future<void> seek(int ms) => engine.seek(ms);
  @override
  Future<void> skipTo(int index) => engine.skipTo(index);
  @override
  Future<void> move(int from, int to) async => engine.move(from, to);
  @override
  Future<void> remove(int index) async => engine.remove(index);
  @override
  Future<void> playNext(Track t) async => engine.playNext(t);
  @override
  Future<void> addToQueue(Track t) async => engine.addToQueue(t);
  @override
  Future<void> setShuffle(bool on) async => engine.setShuffle(on);
  @override
  Future<void> cycleRepeat() async => engine.cycleRepeat();
  @override
  Future<void> setSpeed(double speed) => engine.setSpeed(speed);

  // ---- Search -----------------------------------------------------------------------------------

  @override
  Future<List<Track>> searchLocal(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _local
        .where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Track>> searchRemote(String query) async {
    if (query.trim().isEmpty) return const [];
    return registry.search(query.trim());
  }

  @override
  Future<List<Track>> albumTracks(Album album) async {
    final l = _local.where((t) => t.albumId == album.id).toList()
      ..sort((a, b) {
        final d = a.discNumber.compareTo(b.discNumber);
        return d != 0 ? d : a.trackNumber.compareTo(b.trackNumber);
      });
    return l;
  }

  @override
  final ValueNotifier<double> volume = ValueNotifier<double>(1);
  @override
  Future<void> setOutputProtection(bool on) => engine.setProtection(on);

  @override
  Future<void> setVolume(double v) async {
    volume.value = v.clamp(0.0, 1.0);
    await engine.setMasterVolume(volume.value);
  }

  @override
  Future<List<AudioOutput>> outputs() => engine.outputs();
  @override
  Future<void> setOutput(String id) => engine.setOutput(id);

  @override
  bool get eqSupported => engine.eqSupported;
  @override
  Future<void> applyEq(bool enabled, List<double> gains) => engine.setEq(enabled, gains);
  @override
  Future<void> setAutomix(bool enabled, double seconds, {bool beatMix = true, bool auto = true}) async {
    engine.setAutomix(enabled, seconds, beatMix: beatMix, auto: auto);
  }

  // ---- Not available off Android ----------------------------------------------------------------

  @override
  Future<bool> spatialAvailable() async => engine.spatialSupported;
  @override
  Future<void> toggleSpatial() async {
    if (!engine.spatialSupported) return;
    final on = !spatial.value;
    spatial.value = on;
    settings.spatialDsp = on;
    await engine.setSpatial(on);
  }
  @override
  Future<({double bpm, double confidence})?> tempo() async => null;
  @override
  Future<TrackAnalysis?> analyze(Track t) async => null;

  /// Gentle procedural spectrum while playing. Honest placeholder: it does not follow the music.
  @override
  void setFrameActive(bool active) {
    if (!active) {
      _frameTimer?.cancel();
      _frameTimer = null;
      return;
    }
    if (_frameTimer != null) return;
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final playing = engine.snapshot.value.isPlaying;
      _phase += 0.045;
      final target = playing ? 1.0 : 0.0;
      for (var i = 0; i < frame.spectrum.length; i++) {
        final wave = 0.5 + 0.5 * sin(_phase * (1.2 + i * 0.09) + i * 0.7);
        final shape = 1.0 - i / (frame.spectrum.length * 1.6);
        final v = wave * shape * 0.8 * target;
        frame.spectrum[i] += (v - frame.spectrum[i]) * 0.25;
      }
      final live = DateTime.now().difference(_lvAt).inMilliseconds < 400;
      if (live && playing) {
        final level = (_lvRms * 4.0).clamp(0.0, 1.0);
        final bass = (_lvLow * 6.0).clamp(0.0, 1.0);
        for (var i = 0; i < frame.spectrum.length; i++) {
          final lowMix = 1.0 - i / frame.spectrum.length;
          final target = (bass * lowMix * 0.9 + level * 0.55 * (0.4 + 0.6 * sin(_phase * 2 + i))).clamp(0.0, 1.0);
          frame.spectrum[i] += (target - frame.spectrum[i]) * 0.45;
        }
        frame.rms = level;
      } else {
        frame.rms = playing ? 0.35 : 0;
      }
      frame.publish();
    });
  }

  @override
  Future<void> dispose() async {
    _frameTimer?.cancel();
    await _levelSub?.cancel();
    await engine.dispose();
  }
}

/// Lock-screen / media-key / browser media-session integration where audio_service supports it.
class _MediaSessionHandler extends svc.BaseAudioHandler with svc.SeekHandler {
  _MediaSessionHandler(this._b) {
    _b.snapshot.addListener(_sync);
    _b.progress.addListener(_sync);
  }

  final DartBackend _b;
  String? _lastId;

  static Future<_MediaSessionHandler?> tryCreate(DartBackend b) async {
    final supported = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!supported) return null;
    try {
      return await svc.AudioService.init(
        builder: () => _MediaSessionHandler(b),
        config: const svc.AudioServiceConfig(
          androidNotificationChannelId: 'com.aurora.music.playback',
          androidNotificationChannelName: 'Playback',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _sync() {
    final s = _b.snapshot.value;
    final p = _b.progress.value;
    final t = s.current;
    if (t != null && t.mediaId != _lastId) {
      _lastId = t.mediaId;
      mediaItem.add(svc.MediaItem(
        id: t.mediaId,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
        artUri: t.artworkUri != null && t.artworkUri!.startsWith('http') ? Uri.parse(t.artworkUri!) : null,
      ));
    }
    playbackState.add(svc.PlaybackState(
      controls: [
        svc.MediaControl.skipToPrevious,
        s.isPlaying ? svc.MediaControl.pause : svc.MediaControl.play,
        svc.MediaControl.skipToNext,
      ],
      systemActions: const {svc.MediaAction.seek},
      processingState: s.isBuffering ? svc.AudioProcessingState.buffering : svc.AudioProcessingState.ready,
      playing: s.isPlaying,
      updatePosition: Duration(milliseconds: p.positionMs),
      speed: s.speed,
    ));
  }

  @override
  Future<void> play() async {
    if (!_b.snapshot.value.isPlaying) await _b.toggle();
  }

  @override
  Future<void> pause() async {
    if (_b.snapshot.value.isPlaying) await _b.toggle();
  }

  @override
  Future<void> skipToNext() => _b.next();

  @override
  Future<void> skipToPrevious() => _b.previous();

  @override
  Future<void> seek(Duration position) => _b.seek(position.inMilliseconds);
}
