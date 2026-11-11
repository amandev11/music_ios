import 'dart:async';

import '../sources/source.dart';
import 'transport.dart';
import 'yt_iframe.dart';

/// Plays YouTube audio through the official IFrame player (browser only).
class YouTubeIframeTransport implements Transport {
  YouTubeIframeTransport() {
    _yt.setCallback(_onEvent);
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_isPlaying) _position.add((_yt.time() * 1000).round());
    });
  }

  final YtIframe _yt = YtIframe();
  Timer? _poll;
  bool _isPlaying = false;

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _position = StreamController<int>.broadcast();

  void _onEvent(String type, num value) {
    if (type == 'state') {
      // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
      final s = value.toInt();
      _isPlaying = s == 1 || s == 3;
      _playing.add(s == 1);
      _buffering.add(s == 3 || s == -1);
      if (s == 0) _completed.add(null);
    } else if (type == 'error') {
      _errors.add('YouTube player error ${value.toInt()}');
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
  int get durationMs => (_yt.duration() * 1000).round();
  @override
  int get currentPositionMs => (_yt.time() * 1000).round();

  @override
  bool canPlay(Playable p) => p.youtubeId != null && _yt.available;

  @override
  Future<void> open(Playable p, {int startMs = 0}) async => _yt.load(p.youtubeId!);

  @override
  Future<void> play() async => _yt.play();

  @override
  Future<void> pause() async => _yt.pause();

  @override
  Future<void> seek(int ms) async => _yt.seek(ms / 1000.0);

  @override
  Future<void> setSpeed(double speed) async => _yt.setRate(speed);

  @override
  Future<void> setVolume(double volume) async => _yt.setVolume(volume * 100);

  @override
  bool get supportsEq => false;

  @override
  Future<void> setEq(bool enabled, List<double> gainsDb) async {}

  @override
  bool get supportsSpatial => false;
  @override
  Future<void> setSpatial(bool on) async {}
  @override
  Future<void> setProtection(bool on) async {}

  @override
  bool get supportsMixFilter => false;
  @override
  Future<void> setMixChain(bool on) async {}
  @override
  Future<void> setMixFilter(double highpassHz, double lowpassHz) async {}

  @override
  Future<List<AudioOutput>> outputs() async => const [];
  @override
  Future<void> setOutput(String id) async {}

  @override
  Future<void> dispose() async {
    _poll?.cancel();
  }
}
