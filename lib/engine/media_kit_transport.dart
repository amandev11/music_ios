import 'dart:async';

import 'package:media_kit/media_kit.dart' hide Playable;

import '../sources/source.dart';
import 'eq.dart';
import 'transport.dart';

/// mpv through media_kit: Windows, Linux, macOS and iOS. Supports request headers (googlevideo needs
/// them), per-instance volume for crossfades, and a real equalizer through mpv's audio filters.
class MediaKitTransport implements Transport {
  MediaKitTransport() {
    _player = Player(configuration: const PlayerConfiguration(title: 'Music'));
    _subs.addAll([
      _player.stream.playing.listen(_playing.add),
      _player.stream.buffering.listen(_buffering.add),
      _player.stream.completed.listen((done) {
        if (done && !_completedFired) {
          _completedFired = true;
          _completed.add(null);
        }
      }),
      _player.stream.position.listen((d) => _position.add(d.inMilliseconds)),
      _player.stream.error.listen((e) {
        if (e.isEmpty) return;
        // An audio-filter graph this mpv build rejects (equalizer, spatial, DJ filters) must never stop
        // playback: drop the culprit for good, restore the stream and swallow the error.
        if (_looksLikeFilterError(e) && (_mixChain || _eqFilter.isNotEmpty || _spatialOn || _protectActive)) {
          unawaited(_recoverFromFilterError());
          return;
        }
        _errors.add(e);
      }),
    ]);
  }

  late final Player _player;
  final _subs = <StreamSubscription<dynamic>>[];
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _position = StreamController<int>.broadcast();
  bool _completedFired = false;
  String _lastFilter = '';

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<int> get positionMs => _position.stream;
  @override
  int get durationMs => _player.state.duration.inMilliseconds;
  @override
  int get currentPositionMs => _player.state.position.inMilliseconds;
  @override
  bool get supportsEq => !_eqBroken;

  @override
  bool canPlay(Playable p) => p.url != null;

  @override
  Future<void> open(Playable p, {int startMs = 0}) async {
    _completedFired = false;
    final headers = Map<String, String>.of(p.headers);
    final ua = headers.remove('User-Agent');
    final native = _player.platform;
    if (native is NativePlayer) {
      // mpv keeps its own User-Agent setting separate from custom header fields.
      await native.setProperty('user-agent', ua ?? 'Mozilla/5.0');
    }
    await _player.open(
      Media(p.url!, httpHeaders: headers.isEmpty ? null : headers, start: startMs > 0 ? Duration(milliseconds: startMs) : null),
      play: false,
    );
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(int ms) => _player.seek(Duration(milliseconds: ms));
  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);
  @override
  Future<void> setVolume(double volume) => _player.setVolume((volume.clamp(0.0, 1.0)) * 100);

  String _eqFilter = '';
  bool _mixChain = false;
  bool _mixBroken = false;
  bool _eqBroken = false;
  bool _spatialOn = false;
  bool _spatialBroken = false;
  Timer? _afDebounce;
  bool _recovering = false;

  bool _protectOn = true;
  bool _protectBroken = false;
  bool get _protectActive => _protectOn && !_protectBroken;

  // Sub-bass cut, headroom and a peak limiter as the last stage (see Transport.setProtection).
  static const _protectFilter = 'lavfi=[highpass=f=30,volume=-3dB,alimiter=limit=0.9:attack=2:release=50:level=disabled]';

  static const _spatialFilter = 'lavfi=[stereowiden=delay=22:feedback=0.32:crossfeed=0.28:drymix=0.85]';

  static bool _looksLikeFilterError(String e) {
    final l = e.toLowerCase();
    return l.contains('filter') || l.contains('lavfi') || l.contains('af ') || l.contains('audio chain') || l.contains('audio output');
  }

  Future<void> _applyAf() async {
    final parts = [
      if (_eqFilter.isNotEmpty && !_eqBroken) _eqFilter,
      if (_spatialOn && !_spatialBroken) _spatialFilter,
      if (_mixChain && !_mixBroken) '@mix:lavfi=[highpass@hp=f=20,lowpass@lp=f=18000]',
      if (_protectActive) _protectFilter,
    ];
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('af', parts.join(','));
      } catch (_) {}
    }
  }

  /// Slider drags fire many updates; every change rebuilds mpv's filter chain, so apply only the last one.
  void _applyAfSoon() {
    _afDebounce?.cancel();
    _afDebounce = Timer(const Duration(milliseconds: 220), () => unawaited(_applyAf()));
  }

  /// Drops the filter that broke the audio chain (DJ filters first, then spatial, then the equalizer),
  /// reapplies the rest and resumes the song where it was.
  Future<void> _recoverFromFilterError() async {
    if (_recovering) return;
    _recovering = true;
    try {
      final wasPlaying = _player.state.playing;
      final pos = _player.state.position;
      if (_mixChain && !_mixBroken) {
        _mixBroken = true;
        _mixChain = false;
      } else if (_protectActive) {
        _protectBroken = true;
      } else if (_spatialOn && !_spatialBroken) {
        _spatialBroken = true;
      } else {
        _eqBroken = true;
        _eqFilter = '';
        _lastFilter = '';
      }
      await _applyAf();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _player.seek(pos);
      if (wasPlaying) await _player.play();
    } catch (_) {
    } finally {
      _recovering = false;
    }
  }

  @override
  Future<void> setEq(bool enabled, List<double> gainsDb) async {
    if (_eqBroken) return;
    final filter = mpvEqFilter(enabled, gainsDb);
    if (filter == _lastFilter) return;
    _lastFilter = filter;
    _eqFilter = filter;
    _applyAfSoon();
  }

  @override
  Future<void> setProtection(bool on) async {
    if (_protectOn == on) return;
    _protectOn = on;
    _applyAfSoon();
  }

  @override
  bool get supportsSpatial => !_spatialBroken;

  @override
  Future<void> setSpatial(bool on) async {
    if (_spatialBroken || _spatialOn == on) return;
    _spatialOn = on;
    _applyAfSoon();
  }

  @override
  bool get supportsMixFilter => !_mixBroken;

  @override
  Future<void> setMixChain(bool on) async {
    if (_mixBroken || _mixChain == on) return;
    _mixChain = on;
    await _applyAf();
  }

  @override
  Future<void> setMixFilter(double highpassHz, double lowpassHz) async {
    if (!_mixChain) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.command(['af-command', 'mix', 'frequency', highpassHz.toStringAsFixed(1), 'hp']);
      await platform.command(['af-command', 'mix', 'frequency', lowpassHz.toStringAsFixed(1), 'lp']);
    } catch (_) {}
  }

  @override
  Future<List<AudioOutput>> outputs() async =>
      [for (final d in _player.state.audioDevices) AudioOutput(d.name, d.description.isEmpty ? d.name : d.description)];

  @override
  Future<void> setOutput(String id) async {
    final d = _player.state.audioDevices.where((e) => e.name == id).firstOrNull;
    if (d != null) await _player.setAudioDevice(d);
  }

  @override
  Future<void> dispose() async {
    _afDebounce?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
