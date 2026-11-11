import 'dart:async';

import 'package:flutter/services.dart';

import '../core/network_quality.dart';
import '../sources/source.dart';
import 'transport.dart';

/// iPhone/iPad playback on the native AVAudioEngine engine (packages/aurora_pcm/ios/Classes/AuroraAudioEngine.swift):
/// a real 10-band equaliser, HRTF spatial audio, tempo changes for beat matching and DJ filters.
/// Two instances (ids 0 and 1) share one native engine so Automix can crossfade between them.
class IosNativeTransport implements Transport {
  IosNativeTransport(this.id) {
    _sub = _events.listen(_onEvent, onError: (Object e) => _errors.add('$e'));
  }

  final int id;
  static const _ch = MethodChannel('aurora/ios_audio');
  static final Stream<dynamic> _events = const EventChannel('aurora/ios_audio/events').receiveBroadcastStream();
  static final _levelCtl = StreamController<({double rms, double low})>.broadcast();

  /// Live loudness of the mix (rms) and its low-frequency energy, for the visualiser.
  static Stream<({double rms, double low})> get levels => _levelCtl.stream;

  /// True once the native engine answered; false when the plugin is missing (then use the mpv engine).
  static Future<bool> available() async {
    try {
      return (await _ch.invokeMethod<bool>('init', {'id': 0}).timeout(const Duration(seconds: 6))) ?? false;
    } catch (_) {
      return false;
    }
  }

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _position = StreamController<int>.broadcast();
  StreamSubscription<dynamic>? _sub;

  int _duration = 0;
  int _anchorMs = 0;
  DateTime _anchorAt = DateTime.now();
  bool _isPlaying = false;
  double _speed = 1;

  void _anchor(int ms) {
    _anchorMs = ms;
    _anchorAt = DateTime.now();
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final e = raw['e'];
    if (e == 'level') {
      if (id == 0) _levelCtl.add((rms: (raw['rms'] as num).toDouble(), low: (raw['low'] as num).toDouble()));
      return;
    }
    final v = raw['v'];
    if (v != id && v != -1) return;
    switch (e) {
      case 'state':
        final playing = raw['playing'] == true;
        if (playing != _isPlaying) {
          _anchor(currentPositionMs);
          _isPlaying = playing;
        }
        _playing.add(playing);
      case 'pos':
        _anchor((raw['ms'] as num).toInt());
        final dur = (raw['dur'] as num?)?.toInt() ?? 0;
        if (dur > 0) _duration = dur;
        _position.add(_anchorMs);
      case 'done':
        _isPlaying = false;
        _playing.add(false);
        _completed.add(null);
      case 'error':
        _errors.add('${raw['msg']}');
    }
  }

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
  int get durationMs => _duration;

  /// Native position is reported every 100 ms; between reports it is extrapolated so beat-aligned starts stay tight.
  @override
  int get currentPositionMs {
    if (!_isPlaying) return _anchorMs;
    final ms = _anchorMs + (DateTime.now().difference(_anchorAt).inMicroseconds * _speed / 1000).round();
    return _duration > 0 && ms > _duration ? _duration : ms;
  }

  @override
  bool get supportsEq => true;
  @override
  bool get supportsSpatial => true;
  @override
  bool get supportsMixFilter => true;

  @override
  bool canPlay(Playable p) {
    final u = p.url;
    if (u == null || u.isEmpty) return false;
    final l = u.toLowerCase();
    return !(l.endsWith('.webm') || l.endsWith('.ogg') || l.endsWith('.opus') || l.contains('mime=audio%2fwebm'));
  }

  @override
  Future<void> open(Playable p, {int startMs = 0}) async {
    _buffering.add(true);
    _isPlaying = false;
    _anchor(startMs);
    try {
      final info = await _ch.invokeMapMethod<String, dynamic>('open', {
        'id': id,
        'url': p.url,
        'headers': p.headers,
        'startMs': startMs,
      });
      _duration = (info?['dur'] as num?)?.toInt() ?? 0;
      final bytes = (info?['bytes'] as num?)?.toInt() ?? 0;
      final ms = (info?['ms'] as num?)?.toInt() ?? 0;
      if (bytes > 0 && ms > 0) NetworkQuality.record(bytes, Duration(milliseconds: ms));
    } on PlatformException catch (e) {
      throw Exception(e.message ?? e.code);
    } finally {
      _buffering.add(false);
    }
  }

  @override
  Future<void> play() async {
    _anchor(currentPositionMs);
    _isPlaying = true;
    _playing.add(true);
    await _ch.invokeMethod<void>('play', {'id': id});
  }

  @override
  Future<void> pause() async {
    _anchor(currentPositionMs);
    _isPlaying = false;
    _playing.add(false);
    await _ch.invokeMethod<void>('pause', {'id': id});
  }

  @override
  Future<void> seek(int ms) async {
    _anchor(ms);
    await _ch.invokeMethod<void>('seek', {'id': id, 'ms': ms});
  }

  @override
  Future<void> setSpeed(double speed) async {
    _anchor(currentPositionMs);
    _speed = speed;
    await _ch.invokeMethod<void>('speed', {'id': id, 'v': speed});
  }

  @override
  Future<void> setVolume(double volume) => _ch.invokeMethod<void>('volume', {'id': id, 'v': volume});

  @override
  Future<void> setEq(bool enabled, List<double> gainsDb) =>
      _ch.invokeMethod<void>('eq', {'id': id, 'enabled': enabled, 'gains': gainsDb});

  @override
  Future<void> setSpatial(bool on) => _ch.invokeMethod<void>('spatial', {'id': id, 'on': on});

  @override
  Future<void> setMixChain(bool on) => _ch.invokeMethod<void>('mixChain', {'id': id, 'on': on});

  @override
  Future<void> setMixFilter(double highpassHz, double lowpassHz) =>
      _ch.invokeMethod<void>('mixFilter', {'id': id, 'hp': highpassHz, 'lp': lowpassHz});

  @override
  Future<void> setProtection(bool on) => _ch.invokeMethod<void>('protect', {'id': id, 'on': on});

  @override
  Future<List<AudioOutput>> outputs() async => const [];
  @override
  Future<void> setOutput(String id) async {}

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _playing.close();
    await _buffering.close();
    await _completed.close();
    await _errors.close();
    await _position.close();
  }
}
