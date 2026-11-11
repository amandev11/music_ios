import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../sources/source.dart';
import 'transport.dart';

class JustAudioTransport implements Transport {
  JustAudioTransport() {
    _subs.add(_player.playerStateStream.listen((s) {
      _playing.add(s.playing && s.processingState != ProcessingState.completed);
      _buffering.add(s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering);
      if (s.processingState == ProcessingState.completed && !_completedFired) {
        _completedFired = true;
        _completed.add(null);
      }
    }));
    _subs.add(_player.positionStream.listen(_position.add));
    _subs.add(_player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) => _errors.add('$e')));
  }

  final AudioPlayer _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  bool _completedFired = false;

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<int> get positionMs => _position.stream.map((p) => p.inMilliseconds);
  @override
  int get durationMs => _player.duration?.inMilliseconds ?? 0;
  @override
  int get currentPositionMs => _player.position.inMilliseconds;

  @override
  bool canPlay(Playable p) => p.url != null;

  @override
  Future<void> open(Playable p, {int startMs = 0}) async {
    _completedFired = false;
    final url = p.url!;
    final source = AudioSource.uri(
      Uri.parse(url),
      headers: p.headers.isEmpty ? null : p.headers,
    );
    try {
      await _player.setAudioSource(source, initialPosition: startMs > 0 ? Duration(milliseconds: startMs) : null);
    } catch (e) {
      _errors.add('$e');
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(int ms) => _player.seek(Duration(milliseconds: ms));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

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
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
