import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'backend/backend.dart';
import 'backend/dart_backend.dart';
import 'backend/native_backend.dart';
import 'core/models.dart';
import 'core/recommender.dart';
import 'core/settings.dart';
import 'engine/automix/planner.dart';
import 'sources/catalog.dart';
import 'sources/registry.dart' show TrackMatch;
import 'ui/widgets/artwork.dart' show ArtworkColors;
import 'sources/lyrics.dart';
import 'platform/siri.dart';
import 'platform/widget_sync.dart';

bool get isNativeAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class _Provider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Heard position, extrapolated between the engine's progress samples so the scrubber, lyrics and
/// mini-player move smoothly at display rate even when the engine reports at 5-20 Hz.
class PositionClock extends ChangeNotifier {
  PositionClock(this._backend) {
    _ticker = _Provider().createTicker(_tick);
    _backend.progress.addListener(_onSample);
    _backend.snapshot.addListener(_onSnapshot);
  }

  final Backend _backend;
  late final Ticker _ticker;
  Progress _sample = const Progress();
  Duration _sampleAt = Duration.zero;
  Duration _now = Duration.zero;
  bool _playing = false;
  double _speed = 1;

  void _onSample() {
    _sample = _backend.progress.value;
    _sampleAt = _now;
    notifyListeners();
  }

  void _onSnapshot() {
    final s = _backend.snapshot.value;
    _speed = s.speed;
    if (s.isPlaying != _playing) {
      _playing = s.isPlaying;
      _sampleAt = _now;
      if (_playing) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        _ticker.stop();
        _now = Duration.zero;
        _sampleAt = Duration.zero;
        notifyListeners();
      }
    }
  }

  Duration _lastNotify = Duration.zero;

  void _tick(Duration elapsed) {
    _now = elapsed;
    // ~30 Hz is plenty for a scrubber and lyrics; halves rebuild work.
    if ((elapsed - _lastNotify).inMilliseconds < 33) return;
    _lastNotify = elapsed;
    notifyListeners();
  }

  int get durationMs => _sample.durationMs;

  int get positionMs {
    final extra = _playing ? ((_now - _sampleAt).inMicroseconds / 1000.0 * _speed) : 0.0;
    final p = _sample.positionMs + extra.round();
    return durationMs > 0 ? p.clamp(0, durationMs) : (p < 0 ? 0 : p);
  }

  double get fraction => durationMs > 0 ? positionMs / durationMs : 0;

  @override
  void dispose() {
    _ticker.dispose();
    _backend.progress.removeListener(_onSample);
    _backend.snapshot.removeListener(_onSnapshot);
    super.dispose();
  }
}

class AppController {
  AppController._(this.settings, this.backend) {
    lyricsRepo = LyricsRepository(settings);
    catalog = Catalog(settings);
    catalog.songSearch = (q) => backend.searchRemote(q);
    clock = PositionClock(backend);
    backend.snapshot.addListener(_recordRecent);
    backend.snapshot.addListener(_updateTint);
    final _ = settings.firstRunMs;
    MixPlanner.overrideFor = (id) => settings.mixOverrides[id];
    MixPlanner.filtersEnabled = settings.mixFilters;
    settings.addListener(() => MixPlanner.filtersEnabled = settings.mixFilters);
    _listenTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (backend.snapshot.value.isPlaying) settings.listenedMs += 5000;
    });
  }

  Timer? _listenTimer;

  /// Dominant colour of the current artwork; null when nothing is playing. Glass, the particle grid
  /// and the page background all take their tint from this.
  final ValueNotifier<Color?> tint = ValueNotifier<Color?>(null);
  String? _tintKey;

  Future<void> _updateTint() async {
    final t = backend.snapshot.value.current;
    final key = t?.artKey;
    if (key == _tintKey) return;
    _tintKey = key;
    if (t == null) {
      tint.value = null;
      return;
    }
    final colors = await ArtworkColors.of(t);
    if (_tintKey != key) return;
    // Prefer a colourful swatch; lift very dark ones so the glass does not go muddy.
    var c = colors.first;
    final hsl = HSLColor.fromColor(c);
    c = hsl.withSaturation(hsl.saturation.clamp(0.35, 0.9)).withLightness(hsl.lightness.clamp(0.28, 0.6)).toColor();
    tint.value = c;
  }

  final Settings settings;
  final Backend backend;
  late final LyricsRepository lyricsRepo;
  late final Catalog catalog;
  String? _lastRecentId;
  late final PositionClock clock;
  WidgetSync? widgetSync;
  SiriBridge? siri;

  static late AppController I;

  static Future<AppController> create() async {
    final settings = await Settings.load();
    final backend = isNativeAndroid ? NativeBackend() : DartBackend(settings);
    final c = AppController._(settings, backend);
    I = c;
    await backend.init();
    try {
      await c.applyPrefs();
    } catch (e) {
      debugPrint('applyPrefs failed (engine not ready?): $e');
    }
    c.widgetSync = WidgetSync(backend);
    c.siri = SiriBridge(backend);
    return c;
  }

  Future<Lyrics?> lyricsFor(Track t) => lyricsRepo.fetch(t);

  /// Sends the chosen transition (off / crossfade / Automix) to the engine.
  Future<void> applyMix() {
    final cross = settings.crossfadeOnly;
    return backend.setAutomix(
      settings.automix,
      cross ? settings.crossfadeSeconds : settings.automixSeconds,
      beatMix: !cross,
      auto: settings.automixAuto,
    );
  }

  /// Pushes saved equalizer and Automix settings to the engine (also after it is recreated).
  Future<void> applyPrefs() async {
    await backend.applyEq(settings.eqEnabled, settings.eqGains);
    await backend.setOutputProtection(settings.outputProtection);
    await applyMix();
    await backend.setVolume(settings.volume);
  }

  List<Track> get recentTracks => [for (final m in settings.recent) Track.fromMap(m)];

  Track? _prev;
  int _prevListened = 0;
  bool _refilling = false;

  /// Learns from how the previous song ended: abandoned within a few seconds counts as a skip.
  void _learnFromPrevious() {
    final p = _prev;
    if (p == null || p.durationMs < 60000) return;
    final heard = settings.listenedMs - _prevListened;
    if (heard < 15000 && heard < p.durationMs * 0.3) {
      settings.addPlay({
        'id': p.mediaId,
        'title': p.title,
        'artist': p.artist,
        'album': p.album,
        'skip': true,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  int _searchPlayGen = 0;

  /// Plays a song picked from search and builds the queue after it from what this listener is likely to
  /// enjoy (taste profile, same artist, the other results, "For you"), instead of the raw result list.
  Future<void> playFromSearch(List<Track> results, int index) async {
    if (index < 0 || index >= results.length) return;
    final picked = results[index];
    final gen = ++_searchPlayGen;
    await backend.playTracks([picked], 0); // starts at once; the queue fills in behind it
    try {
      final rec = Recommender(settings);
      final pool = <Track>[
        ...results.where((t) => t.mediaId != picked.mediaId),
        ...await catalog.forYou().catchError((_) => <Track>[]),
        ...await backend.searchRemote('${picked.artist} songs').catchError((_) => <Track>[]),
      ];
      if (gen != _searchPlayGen || backend.snapshot.value.current?.mediaId != picked.mediaId) return; // user moved on
      final seen = <String>{picked.mediaId};
      final seenTitles = <String>{'${TrackMatch.normalize(picked.title)}|${TrackMatch.normalize(picked.artist)}'};
      final pickedArtist = TrackMatch.normalize(picked.artist);
      final rng = Random();
      final scored = <(Track, double)>[];
      for (final t in pool) {
        if (!t.isRemote || !seen.add(t.mediaId)) continue;
        if (!seenTitles.add('${TrackMatch.normalize(t.title)}|${TrackMatch.normalize(t.artist)}')) continue;
        final related = pickedArtist.isNotEmpty && TrackMatch.normalize(t.artist).contains(pickedArtist) ? 1.6 : 1.0;
        scored.add((t, rec.score(t) * related * (0.85 + 0.3 * rng.nextDouble())));
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      final perArtist = <String, int>{};
      final queue = <Track>[];
      for (final e in scored) {
        final a = TrackMatch.normalize(e.$1.artist);
        if ((perArtist[a] = (perArtist[a] ?? 0) + 1) > 4) continue; // keep the queue varied
        queue.add(e.$1);
        if (queue.length >= 15) break;
      }
      for (final t in queue) {
        if (gen != _searchPlayGen) return;
        await backend.addToQueue(t);
      }
    } catch (e) {
      debugPrint('search queue failed: $e');
    }
  }

  /// Autoplay: when the queue is nearly done, append songs the listener is likely to enjoy.
  Future<void> _maybeRefill() async {
    final snap = backend.snapshot.value;
    if (!settings.autoplay || _refilling || snap.queue.isEmpty) return;
    if (snap.repeat != RepeatMode.off || snap.queue.length - snap.currentIndex > 3) return;
    _refilling = true;
    try {
      var picks = await catalog.forYou();
      final have = {for (final q in snap.queue) q.mediaId};
      picks = [for (final t in picks) if (!have.contains(t.mediaId)) t];
      if (picks.length < 5 && snap.current != null) {
        final more = await backend.searchRemote('${snap.current!.artist} songs');
        final r = Recommender(settings).rank([for (final t in more) if (!have.contains(t.mediaId)) t]);
        picks = [...picks, ...r];
      }
      for (final t in picks.take(10)) {
        await backend.addToQueue(t);
      }
    } catch (e) {
      debugPrint('autoplay refill failed: $e');
    } finally {
      _refilling = false;
    }
  }

  void _recordRecent() {
    final t = backend.snapshot.value.current;
    if (t == null) return;
    if (t.mediaId == _lastRecentId) {
      unawaited(_maybeRefill());
      return;
    }
    _learnFromPrevious();
    _prev = t;
    _prevListened = settings.listenedMs;
    unawaited(_maybeRefill());
    _lastRecentId = t.mediaId;
    final list = settings.recent..removeWhere((m) => m['mediaId'] == t.mediaId);
    list.insert(0, t.toMap().map((k, v) => MapEntry(k, v)));
    settings.addPlay({
      'id': t.mediaId,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'art': t.artworkUri,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    settings.recent = list;
  }
}
