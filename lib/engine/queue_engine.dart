import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../sources/registry.dart';
import '../sources/source.dart';
import '../sources/stream_proxy_stub.dart'
    if (dart.library.io) '../sources/stream_proxy_io.dart'
    show localCopyFor;
import 'automix/analyzer.dart';
import 'automix/planner.dart';
import 'ios_native_transport.dart';
import 'just_audio_transport.dart';
import 'media_kit_transport.dart';
import '../sources/yt_trace.dart';
import 'transport.dart';
import 'yt_desktop_stub.dart' if (dart.library.io) 'yt_desktop_io.dart';
import 'youtube_web_transport.dart';

/// Queue, shuffle/repeat, Automix crossfades and track-to-track logic over two interchangeable
/// transports (so one can fade in while the other fades out) plus, on web, the YouTube IFrame player.
/// Remote URLs are resolved lazily when a track starts; the next one is resolved in the background.
class QueueEngine {
  QueueEngine(this._registry, {bool nativeIos = false}) {
    _pool = kIsWeb
        ? [JustAudioTransport(), JustAudioTransport()]
        : nativeIos
        ? [IosNativeTransport(0), IosNativeTransport(1)]
        : [MediaKitTransport(), MediaKitTransport()];
    _yt = kIsWeb ? YouTubeIframeTransport() : createDesktopYt();
    for (final t in _all) {
      _attach(t);
    }
  }

  final SourceRegistry _registry;

  /// Swaps the native iOS engine for mpv (when the plugin is missing or the user chose compatibility mode).
  /// Only valid before anything has played.
  Future<void> useMpvEngine() async {
    final old = _pool;
    _pool = [MediaKitTransport(), MediaKitTransport()];
    for (final t in _pool) {
      _attach(t);
    }
    for (final t in old) {
      await t.dispose();
    }
  }

  late List<Transport> _pool;
  Transport? _yt;
  Transport? _active;
  Transport? _fadingOut;
  Transport? _fadeIn;

  /// mpv transports created on demand next to the native iPhone engine, for streams it cannot decode (webm/opus)
  /// or when a native open fails. They are only built the first time they are needed.
  final List<Transport> _alt = [];

  bool get _nativePool =>
      !kIsWeb && _pool.isNotEmpty && _pool.first is IosNativeTransport;

  /// Everything plays on the native engine; mpv is never started unless this is switched on.
  bool allowMpvFallback = false;

  Future<void> _ensureAlt() async {
    if (!allowMpvFallback || !_nativePool || _alt.isNotEmpty) return;
    for (var i = 0; i < 2; i++) {
      final t = MediaKitTransport();
      _alt.add(t);
      _attach(t);
      await t.setProtection(_protect);
    }
  }

  Iterable<Transport> get _all => [..._pool, ..._alt, if (_yt != null) _yt!];

  final snapshot = ValueNotifier<Snapshot>(const Snapshot());
  final progress = ValueNotifier<Progress>(const Progress());
  final errors = ValueNotifier<PlaybackError?>(null);

  List<Track> _queue = [];
  List<Track> _original = [];
  int _index = -1;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  double _speed = 1.0;
  bool _playing = false;
  bool _buffering = false;
  bool _resolving = false;
  int _gen = 0;
  int _consecutiveErrors = 0;
  final Set<String> _retried = {};
  final _rng = Random();

  bool automix = false;

  /// What the DJ is doing right now ("Mixing into ... · beat-matched"); null when nothing is blending.
  final ValueNotifier<String?> mixInfo = ValueNotifier<String?>(null);
  double automixSeconds = 8;
  bool _fading = false;
  Timer? _fadeTimer;

  double _master = 1;
  Future<void> _vol(Transport? t, double v) =>
      t == null ? Future.value() : t.setVolume((v * _master).clamp(0.0, 1.0));

  /// Master output volume 0..1, applied on top of any crossfade gain.
  Future<void> setMasterVolume(double v) async {
    _master = v.clamp(0.0, 1.0);
    if (_fading) return;
    await _vol(_active, 1);
  }

  Future<List<AudioOutput>> outputs() async => _pool.first.outputs();

  Future<void> setOutput(String id) async {
    for (final t in _pool) {
      await t.setOutput(id);
    }
  }

  bool _eqOn = false;
  List<double> _eq = List.filled(10, 0.0);

  void _attach(Transport t) {
    t.playing.listen((v) {
      if (identical(t, _active)) _update(isPlaying: v);
    });
    t.buffering.listen((v) {
      if (identical(t, _active)) _update(isBuffering: v || _resolving);
    });
    t.positionMs.listen((p) {
      if (!identical(t, _active)) return;
      final d = _trustedDuration(t.durationMs);
      _publishProgress(p, d);
      _maybeCrossfade(p, d);
    });
    t.completed.listen((_) {
      if (identical(t, _active)) unawaited(_onCompleted());
    });
    t.errors.listen((e) {
      if (identical(t, _active) && !_fading) unawaited(_onError(e));
    });
  }

  // ---- Public API ------------------------------------------------------------------------------

  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    _original = List.of(tracks);
    _queue = List.of(tracks);
    _index = index.clamp(0, tracks.length - 1);
    _shuffle = false;
    if (shuffle) _applyShuffle(true);
    await _start(_index);
  }

  Future<void> toggle() async {
    _abortFade();
    final t = _active;
    if (t == null) {
      if (_index >= 0) await _start(_index);
      return;
    }
    _playing ? await t.pause() : await t.play();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_index + 1 < _queue.length) {
      await _start(_index + 1);
    } else if (_repeat == RepeatMode.all) {
      await _start(0);
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if ((_active?.currentPositionMs ?? 0) > 3000 || _index == 0) {
      await seek(0);
    } else {
      await _start(_index - 1);
    }
  }

  Future<void> seek(int ms) async {
    _abortFade();
    await _active?.seek(max(0, ms));
    _publishProgress(
      max(0, ms),
      _active?.durationMs ?? progress.value.durationMs,
    );
  }

  Future<void> skipTo(int index) async {
    if (index >= 0 && index < _queue.length) await _start(index);
  }

  void move(int from, int to) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= _queue.length ||
        to >= _queue.length)
      return;
    final current = _index >= 0 ? _queue[_index] : null;
    final item = _queue.removeAt(from);
    _queue.insert(to, item);
    _index = current == null ? -1 : _queue.indexOf(current);
    _original = List.of(_queue);
    _publish();
  }

  void remove(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _index;
    final current = _index >= 0 ? _queue[_index] : null;
    final gone = _queue.removeAt(index);
    _original.remove(gone);
    if (removingCurrent) {
      if (_queue.isEmpty) {
        _index = -1;
        unawaited(_active?.pause());
        _publish();
      } else {
        _index = min(index, _queue.length - 1);
        unawaited(_start(_index));
      }
    } else {
      _index = current == null ? -1 : _queue.indexOf(current);
      _publish();
    }
  }

  void playNext(Track t) {
    if (_queue.isEmpty) {
      unawaited(playTracks([t], 0));
      return;
    }
    _queue.insert(_index + 1, t);
    _original.add(t);
    _publish();
  }

  void addToQueue(Track t) {
    if (_queue.isEmpty) {
      unawaited(playTracks([t], 0));
      return;
    }
    _queue.add(t);
    _original.add(t);
    _publish();
  }

  void setShuffle(bool on) {
    if (on == _shuffle) return;
    _applyShuffle(on);
    _publish();
  }

  void cycleRepeat() {
    _repeat = switch (_repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    _publish();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 2.0);
    for (final t in _all) {
      await t.setSpeed(_speed);
    }
    _publish();
  }

  /// Plain crossfade (beatMix false) or DJ-style Automix; [auto] lets Automix choose the length per song.
  bool beatMix = true;
  bool autoLength = true;

  void setAutomix(
    bool enabled,
    double seconds, {
    bool beatMix = true,
    bool auto = true,
  }) {
    automix = enabled;
    this.beatMix = beatMix;
    autoLength = auto;
    automixSeconds = seconds.clamp(1.0, 30.0);
    if (!enabled) _abortFade();
    if (enabled && _index >= 0 && _index < _queue.length) {
      unawaited(_analyzeTrack(_queue[_index]));
      unawaited(_prefetch(_nextIndex()));
    }
    _publish();
  }

  Future<void> setEq(bool enabled, List<double> gains) async {
    _eqOn = enabled;
    _eq = List.of(gains);
    for (final t in _pool) {
      if (t.supportsEq) await t.setEq(enabled, gains);
    }
  }

  bool get eqSupported => _pool.first.supportsEq;

  bool _protect = true;

  Future<void> setProtection(bool on) async {
    _protect = on;
    for (final t in _all) {
      await t.setProtection(on);
    }
  }

  bool _spatialOn = false;
  bool get spatialSupported => !kIsWeb && _pool.first.supportsSpatial;

  Future<void> setSpatial(bool on) async {
    _spatialOn = on;
    for (final t in _pool) {
      if (t.supportsSpatial) await t.setSpatial(on);
    }
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    for (final t in _all) {
      await t.dispose();
    }
  }

  // ---- Core ------------------------------------------------------------------------------------

  void _applyShuffle(bool on) {
    final current = _index >= 0 && _index < _queue.length
        ? _queue[_index]
        : null;
    if (on) {
      final rest = List.of(_queue)..remove(current);
      rest.shuffle(_rng);
      _queue = [if (current != null) current, ...rest];
      _index = current == null ? -1 : 0;
    } else {
      _queue = List.of(_original);
      _index = current == null ? -1 : max(0, _queue.indexOf(current));
    }
    _shuffle = on;
  }

  Future<void> _start(int index, {bool fresh = false}) async {
    _abortFade();
    final gen = ++_gen;
    _index = index;
    final track = _queue[index];
    _resolving = true;
    _playing = false;
    _buffering = true;
    _publish();
    _publishProgress(0, track.durationMs);

    if (fresh) _registry.forget(track.mediaId);
    final playable = await _playableFor(track);
    if (gen != _gen) return;
    _resolving = false;

    if (playable == null) {
      await _onError(
        'No source could provide this track (it may be blocked or unavailable).',
      );
      return;
    }
    var t0 = _transportFor(playable);
    if (t0 == null && _nativePool) {
      await _ensureAlt();
      t0 = _transportFor(playable);
    }
    if (t0 == null) {
      await _onError('This source cannot be played on this platform.');
      return;
    }
    Transport transport = t0;
    for (final t in _all) {
      if (!identical(t, transport)) unawaited(t.pause());
    }
    _active = transport;
    try {
      await _vol(transport, 1);
      try {
        await transport.open(playable);
      } catch (first) {
        if (gen != _gen) return;
        YtTrace.log(
          'open:${'$first'.split('\n').first.replaceAll('Exception: ', '')}',
        );
        // 1) the native engine / proxy failed: try a downloaded copy; 2) still failing: the old mpv method.
        var done = false;
        final local = await localCopyFor(playable);
        try {
          // No proxied copy (native downloads directly): simply try the native download once more.
          await transport.open(local ?? playable);
          done = true;
        } catch (_) {}
        if (!done && track.isRemote) {
          // The stream resolved but will not download: play the same recording from another source.
          final other = await _registry.resolveElsewhere(track);
          if (gen != _gen) return;
          if (other == null) YtTrace.log('no-other-source');
          if (other != null && transport.canPlay(other)) {
            try {
              await transport.open(other);
              done = true;
            } catch (_) {}
          }
        }
        if (!done &&
            track.kind == SourceKind.youtube &&
            _yt != null &&
            !identical(transport, _yt)) {
          // Last resort at any cost: YouTube's own embedded player, which needs no stream extraction.
          final embed = Playable.youtube(TrackKeys.rawId(track.mediaId));
          if (_yt!.canPlay(embed)) {
            try {
              YtTrace.log('embed');
              unawaited(transport.pause());
              transport = _yt!;
              _active = transport;
              await _vol(transport, 1);
              await transport.open(embed);
              done = true;
            } catch (_) {}
          }
        }
        if (!done && _nativePool && _pool.contains(transport)) {
          await _ensureAlt();
          if (gen != _gen) return;
          if (_alt.isEmpty) throw first;
          final alt = _alt.firstWhere(
            (t) => t.canPlay(playable),
            orElse: () => _alt.first,
          );
          unawaited(transport.pause());
          transport = alt;
          _active = alt;
          await _vol(alt, 1);
          await alt.open(playable);
          done = true;
        }
        if (!done) throw first;
      }
      if (gen != _gen) return;
      await transport.setSpeed(_speed);
      if (transport.supportsEq) await transport.setEq(_eqOn, _eq);
      if (transport.supportsSpatial) await transport.setSpatial(_spatialOn);
      await transport.setProtection(_protect);
      _consecutiveErrors = 0;
      unawaited(transport.play());
    } catch (e) {
      if (gen == _gen) await _onError('$e');
      return;
    }
    _buffering = false;
    _publish();
    unawaited(_analyzeTrack(track, playable));
    unawaited(_prefetch(_nextIndex()));
  }

  int _nextIndex() {
    if (_queue.isEmpty) return -1;
    if (_index + 1 < _queue.length) return _index + 1;
    return _repeat == RepeatMode.all ? 0 : -1;
  }

  Future<Playable?> _playableFor(Track t) async {
    if (!t.isRemote) return t.uri.isEmpty ? null : Playable.url(t.uri);
    return _registry.resolve(t);
  }

  Transport? _transportFor(Playable p, {Transport? exclude}) {
    // Prefer the transport that is already active, to avoid needless hand-offs.
    final candidates = <Transport>[
      if (_active != null &&
          (_pool.contains(_active) || _alt.contains(_active)))
        _active!,
      ..._pool,
      ..._alt,
      if (_yt != null) _yt!,
    ];
    for (final t in candidates) {
      if (identical(t, exclude)) continue;
      if (t.canPlay(p)) return t;
    }
    return null;
  }

  Future<void> _prefetch(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final t = _queue[index];
    final p = t.isRemote ? await _registry.resolve(t) : await _playableFor(t);
    if (p != null) unawaited(_analyzeTrack(t, p));
  }

  /// Loudness bars for the progress bar (shares the Automix analysis, which decodes the song once).
  Future<List<double>?> waveformFor(Track t) async {
    if (!AutomixAnalyzer.supported) return null;
    final cached = AutomixAnalyzer.I.cached(t.mediaId);
    if (cached != null) return cached.waveform;
    final playable = await _playableFor(t);
    if (playable == null) return null;
    final profile = await AutomixAnalyzer.I.analyze(t, playable);
    return profile?.waveform;
  }

  /// Background tempo/key/silence analysis for Automix (desktop and iOS).
  Future<void> _analyzeTrack(Track t, [Playable? p]) async {
    if (!automix ||
        !beatMix ||
        !AutomixAnalyzer.supported ||
        AutomixAnalyzer.I.known(t.mediaId))
      return;
    final playable = p ?? await _playableFor(t);
    if (playable != null) await AutomixAnalyzer.I.analyze(t, playable);
  }

  // ---- Automix ---------------------------------------------------------------------------------

  DateTime _lastPrefetchTry = DateTime.fromMillisecondsSinceEpoch(0);

  void _maybeCrossfade(int pos, int dur) {
    if (!automix || _fading || !_playing || dur <= 0) return;
    if (_active != null && identical(_active, _yt)) {
      AutomixAnalyzer.note(
        'This song plays through YouTube\'s embedded player, which cannot be mixed',
      );
      return;
    }
    if (!_pool.contains(_active) || _repeat == RepeatMode.one) return;
    final next = _nextIndex();
    if (next < 0 || _index < 0 || _index >= _queue.length) return;
    final a = _queue[_index], b = _queue[next];
    // The next online song must already be downloaded and analysed when the blend begins. Keep asking for it
    // (every few seconds) from a quarter of the way into this song instead of trusting a single early attempt.
    if (b.isRemote && _registry.peek(b) == null) {
      if (pos > dur * 0.2 &&
          DateTime.now().difference(_lastPrefetchTry) >
              const Duration(seconds: 8)) {
        _lastPrefetchTry = DateTime.now();
        unawaited(_prefetch(next));
      }
      if (dur - pos > 6000) {
        AutomixAnalyzer.note('Getting the next song ready for mixing');
        return; // too early to give up; the blend must not start before the song is in hand
      }
    }
    if (!beatMix) {
      // Plain crossfade: fixed length, starts so that it ends with the song. No analysis, no DJ filters.
      final plain = MixPlanner.crossfade(
        aDurMs: dur,
        bDurMs: b.durationMs,
        seconds: automixSeconds,
      );
      if (plain != null &&
          dur >= plain.fadeMs * 2 + 2000 &&
          pos >= plain.mixStartMs &&
          pos < dur - 600) {
        unawaited(_crossfade(next, plain));
      }
      return;
    }
    final analyzer = AutomixAnalyzer.I;
    final pa = analyzer.cached(a.mediaId), pb = analyzer.cached(b.mediaId);
    var plan = MixPlanner.plan(
      a: a,
      b: b,
      pa: pa,
      pb: pb,
      aDurMs: dur,
      maxSeconds: automixSeconds,
      auto: autoLength,
    );
    if (plan == null) return;
    if (plan.beatMatched && pos > plan.mixStartMs - 300) {
      // Analysis arrived too late to line up the bar: use a plain blend instead.
      plan = MixPlanner.plan(
        a: a,
        b: b,
        pa: null,
        pb: null,
        aDurMs: dur,
        maxSeconds: automixSeconds,
        auto: autoLength,
      );
      if (plan == null) return;
    }
    if (dur < plan.fadeMs * 2 + 2000) return;
    // Analysis of the next song is still running and there is time to wait: hold off a little.
    final waiting =
        AutomixAnalyzer.supported &&
        (pa == null || pb == null) &&
        (!analyzer.known(a.mediaId) || !analyzer.known(b.mediaId));
    final lead = plan.beatMatched ? 3500 : 0;
    final remaining = dur - pos;
    if (waiting && remaining > plan.fadeMs + 1500) return;
    if (pos >= plan.mixStartMs - lead && pos < dur - 600) {
      unawaited(_crossfade(next, plan));
    }
  }

  Future<void> _crossfade(int nextIndex, MixPlan plan) async {
    _fading = true;
    try {
      await _crossfadeInner(nextIndex, plan);
    } catch (e) {
      mixInfo.value = null;
      // Never leave the engine stuck in "fading": the song would never advance.
      debugPrint('Automix failed: $e');
      final i = _fadeIn;
      if (i != null && !identical(i, _active)) _cleanupIncoming(i);
      _fading = false;
    }
  }

  Future<void> _crossfadeInner(int nextIndex, MixPlan plan) async {
    final gen = _gen;
    final out = _active!;
    final playable = await _playableFor(_queue[nextIndex]);
    if (gen != _gen || playable == null) {
      _fading = false;
      return;
    }
    var inc0 = _transportFor(playable, exclude: out);
    if (inc0 == null && _nativePool) {
      await _ensureAlt();
      inc0 = _transportFor(playable, exclude: out);
    }
    if (inc0 == null || !(_pool.contains(inc0) || _alt.contains(inc0))) {
      _fading = false;
      return;
    }
    final incoming = inc0;
    _fadeIn = incoming;
    debugPrint('Automix: ${plan.describe()}');
    mixInfo.value =
        'Mixing into ${_queue[nextIndex].title} \u00B7 ${plan.beatMatched ? 'beat-matched' : 'crossfade'}';
    // The DJ-filter chain is installed only now, and dropped for good if mpv rejects it.
    if (beatMix &&
        MixPlanner.filtersEnabled &&
        out.supportsMixFilter &&
        incoming.supportsMixFilter) {
      await incoming.setMixChain(true);
      await out.setMixChain(true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!out.supportsMixFilter)
        await out.play(); // chain rejected: resume plain playback
    }
    final filters =
        beatMix &&
        MixPlanner.filtersEnabled &&
        MixPlanner.djStyle != 0 &&
        out.supportsMixFilter &&
        incoming.supportsMixFilter;
    try {
      await _vol(incoming, 0);
      await incoming.setSpeed(plan.bSpeed * _speed);
      if (incoming.supportsEq) await incoming.setEq(_eqOn, _eq);
      if (incoming.supportsSpatial) await incoming.setSpatial(_spatialOn);
      await incoming.setProtection(_protect);
      if (filters)
        await incoming.setMixFilter(plan.beatMatched ? 900 : 20, 18000);
      await incoming.open(playable, startMs: plan.bSeekMs);
      if (gen != _gen) {
        _cleanupIncoming(incoming);
        return;
      }
      // Wait for the bar line in A: B starts exactly on it.
      if (plan.beatMatched) {
        while (gen == _gen && out.currentPositionMs < plan.mixStartMs - 25) {
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
        if (gen != _gen) {
          _cleanupIncoming(incoming);
          return;
        }
      }
      await incoming.play();
      if (filters)
        await incoming.setMixFilter(plan.beatMatched ? 900 : 20, 18000);
    } catch (_) {
      _cleanupIncoming(incoming);
      return;
    }
    if (gen != _gen) {
      _cleanupIncoming(incoming);
      return;
    }

    final remaining = out.durationMs - out.currentPositionMs;
    final total = min(plan.fadeMs, remaining - 300);
    if (total < 800) {
      _cleanupIncoming(incoming);
      return;
    }

    final clock = Stopwatch()..start();
    final startedAtA = out.currentPositionMs;
    var swapped = false;
    var corrected = false;
    var tick = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (gen != _gen) {
        timer.cancel();
        return;
      }
      tick++;
      final lin = (clock.elapsedMilliseconds / total).clamp(0.0, 1.0);
      final x = lin * lin * lin * (lin * (lin * 6 - 15) + 10); // smootherstep: very gentle start and finish, equal power between
      final trim = plan.bTrim + (1 - plan.bTrim) * lin;
      unawaited(_vol(out, cos(x * pi / 2)));
      unawaited(_vol(incoming, sin(x * pi / 2) * trim));

      // One-off phase correction for beat-matched blends: measure how far B's grid is from A's
      // after both have been playing for a moment, and nudge B if it is off by more than 25 ms.
      if (plan.beatMatched && !corrected && clock.elapsedMilliseconds > 450) {
        corrected = true;
        final aElapsed = out.currentPositionMs - startedAtA;
        final expectedB = plan.bSeekMs + aElapsed * plan.bSpeed;
        final err = incoming.currentPositionMs - expectedB;
        if (err.abs() > 25 && err.abs() < 400)
          unawaited(incoming.seek((incoming.currentPositionMs - err).round()));
      }

      // Tempo eases back to B's natural speed over the second half.
      if (plan.bSpeed != 1 && tick % 2 == 0) {
        final e = ((lin - 0.5) / 0.5).clamp(0.0, 1.0);
        final k = e * e * (3 - 2 * e);
        unawaited(
          incoming.setSpeed((plan.bSpeed + (1 - plan.bSpeed) * k) * _speed),
        );
      }

      // DJ filters: A loses its low end and brightness; B's lows come in at the midpoint (bass swap).
      if (filters && tick % 2 == 0) {
        // The quick-cut style runs the same sweeps in the first 60% of the blend.
        final fl = plan.dj == 2 ? (lin * 1.65).clamp(0.0, 1.0) : lin;
        final sweepA = ((fl - 0.2) / 0.8).clamp(0.0, 1.0);
        final hpA = 20 * pow(60, sweepA).toDouble(); // 20 Hz -> 1.2 kHz
        final lpA =
            18000 *
            pow(
              0.22,
              ((fl - 0.5) / 0.5).clamp(0.0, 1.0),
            ).toDouble(); // 20 kHz -> 4 kHz
        unawaited(out.setMixFilter(hpA, lpA));
        final hpB = fl < 0.4
            ? 900.0
            : 900 *
                  pow(20 / 900, ((fl - 0.4) / 0.25).clamp(0.0, 1.0)).toDouble();
        unawaited(incoming.setMixFilter(hpB < 25 ? 20 : hpB, 18000));
      }

      // Quick cut: the outgoing record slows down like a hand on the platter over the last quarter.
      if (plan.dj == 2 && tick % 2 == 0 && lin > 0.75) {
        final e = ((lin - 0.75) / 0.25).clamp(0.0, 1.0);
        unawaited(out.setSpeed(_speed * (1 - 0.55 * e * e)));
      }

      if (!swapped && lin >= 0.5) {
        // Past the midpoint the next track is "now playing": UI, progress and events follow it.
        swapped = true;
        _index = nextIndex;
        _active = incoming;
        _fadingOut = out;
        _consecutiveErrors = 0;
        _publish();
        _publishProgress(incoming.currentPositionMs, incoming.durationMs);
        unawaited(_prefetch(_nextIndex()));
      }
      if (lin >= 1) {
        timer.cancel();
        unawaited(out.pause());
        unawaited(_vol(out, 1));
        unawaited(_resetTransport(out));
        unawaited(_resetTransport(incoming));
        _fadingOut = null;
        _fadeIn = null;
        _fading = false;
        mixInfo.value = null;
      }
    });
  }

  /// DJ button: start blending into the next song right away (on the next bar line when both songs are analysed).
  Future<bool> mixNow() async {
    if (_fading ||
        !_playing ||
        _index < 0 ||
        !_pool.contains(_active) ||
        _repeat == RepeatMode.one)
      return false;
    final next = _nextIndex();
    if (next < 0) return false;
    final a = _queue[_index], b = _queue[next];
    final pos = _active!.currentPositionMs;
    final dur = _trustedDuration(_active!.durationMs);
    if (dur <= 0) return false;
    if (b.isRemote && _registry.peek(b) == null) {
      await _prefetch(next);
    }
    final plan = MixPlanner.now(
      a: a,
      b: b,
      pa: AutomixAnalyzer.I.cached(a.mediaId),
      pb: AutomixAnalyzer.I.cached(b.mediaId),
      posMs: pos,
      aDurMs: dur,
    );
    if (plan == null) return false;
    unawaited(_crossfade(next, plan));
    return true;
  }

  /// Back to normal: user speed, transparent filters.
  Future<void> _resetTransport(Transport t) async {
    await t.setSpeed(_speed);
    if (t.supportsMixFilter) await t.setMixFilter(20, 18000);
  }

  void _cleanupIncoming(Transport incoming) {
    unawaited(incoming.pause());
    unawaited(_vol(incoming, 1));
    unawaited(_resetTransport(incoming));
    _fadeIn = null;
    _fading = false;
    mixInfo.value = null;
  }

  /// Stops an in-flight crossfade (seek, pause, manual skip) and leaves exactly one track audible.
  void _abortFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (!_fading) return;
    final a = _active;
    final o = _fadingOut;
    final i = _fadeIn;
    if (o != null) {
      unawaited(o.pause());
      unawaited(_vol(o, 1));
      unawaited(_resetTransport(o));
    } else if (i != null && !identical(i, a)) {
      unawaited(i.pause());
      unawaited(_vol(i, 1));
      unawaited(_resetTransport(i));
    }
    if (a != null) unawaited(_resetTransport(a));
    unawaited(_vol(a, 1));
    _fadingOut = null;
    _fadeIn = null;
    _fading = false;
    mixInfo.value = null;
  }

  // ---- Completion and errors -------------------------------------------------------------------

  Future<void> _onCompleted() async {
    if (_fading) return;
    if (_repeat == RepeatMode.one) {
      await seek(0);
      await _active?.play();
    } else if (_index + 1 < _queue.length) {
      await _start(_index + 1);
    } else if (_repeat == RepeatMode.all && _queue.isNotEmpty) {
      await _start(0);
    } else {
      _playing = false;
      _publish();
    }
  }

  Future<void> _onError(String message) async {
    final track = _index >= 0 && _index < _queue.length ? _queue[_index] : null;
    debugPrint('playback error: $message');
    _resolving = false;
    if (track != null && track.isRemote && _retried.add(track.mediaId)) {
      // One fresh attempt: stream URLs expire and a cached one may simply be stale.
      await _start(_index, fresh: true);
      return;
    }
    final trace = YtTrace.take();
    errors.value = PlaybackError(
      'Couldn\'t play ${track?.title ?? 'this track'}: $message${trace.isEmpty ? '' : ' [$trace]'}',
    );
    _consecutiveErrors++;
    if (_consecutiveErrors < 4 && _index + 1 < _queue.length) {
      await _start(_index + 1);
    } else {
      _consecutiveErrors = 0;
      _playing = false;
      _buffering = false;
      _publish();
    }
  }

  void _update({bool? isPlaying, bool? isBuffering}) {
    if (isPlaying != null) _playing = isPlaying;
    if (isBuffering != null) _buffering = isBuffering;
    _publish();
  }

  /// Streamed (fragmented MP4) files can carry a wrong header length; for online tracks the catalogue length is
  /// right, so a reported length that disagrees with it by more than 8% is replaced by it.
  int _trustedDuration(int reported) {
    final track = _index >= 0 && _index < _queue.length ? _queue[_index] : null;
    final meta = track?.durationMs ?? 0;
    if (track == null || meta <= 0 || !TrackKeys.isRemote(track.mediaId))
      return reported;
    if (reported <= 0) return meta;
    return (reported - meta).abs() > meta * 0.08 ? meta : reported;
  }

  void _publishProgress(int pos, int dur) {
    final track = _index >= 0 && _index < _queue.length ? _queue[_index] : null;
    final d = _trustedDuration(dur > 0 ? dur : (track?.durationMs ?? 0));
    progress.value = Progress(pos, d, 0);
  }

  void _publish() {
    snapshot.value = Snapshot(
      isPlaying: _playing,
      isBuffering: _buffering || _resolving,
      queue: List.unmodifiable(_queue),
      currentIndex: _index,
      shuffle: _shuffle,
      repeat: _repeat,
      speed: _speed,
      hasNext: _index + 1 < _queue.length || _repeat == RepeatMode.all,
      hasPrevious: _index > 0,
      automix: automix,
    );
  }
}
