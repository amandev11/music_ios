import 'dart:async';

import '../sources/source.dart';

/// One playing thing at a time. The queue engine owns ordering; a transport only opens, plays and
/// reports. Implementations: media_kit/mpv (desktop and iOS), just_audio (web), YouTube IFrame (web).
class AudioOutput {
  const AudioOutput(this.id, this.name);
  final String id;
  final String name;
}

abstract class Transport {
  Stream<bool> get playing;
  Stream<bool> get buffering;

  /// Fires once when the opened item plays to its end.
  Stream<void> get completed;
  Stream<String> get errors;
  Stream<int> get positionMs;
  int get durationMs;
  int get currentPositionMs;

  bool get supportsEq;
  bool canPlay(Playable p);
  Future<void> open(Playable p, {int startMs = 0});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int ms);
  Future<void> setSpeed(double speed);

  /// 0..1.
  Future<void> setVolume(double volume);
  Future<void> setEq(bool enabled, List<double> gainsDb);

  /// Spatial widening (mpv only): a wider, more enveloping stereo stage on headphones and speakers.
  bool get supportsSpatial;
  Future<void> setSpatial(bool on);

  /// DJ filters for Automix (mpv only): installs or removes a transparent high-pass/low-pass pair.
  bool get supportsMixFilter;
  Future<void> setMixChain(bool on);

  /// Cut-off frequencies in Hz; (10, 20000) is transparent.
  Future<void> setMixFilter(double highpassHz, double lowpassHz);

  /// Speaker protection: sub-bass filter, peak limiter and a little headroom, so loud masters or EQ boosts
  /// never clip into a speaker or receiver.
  Future<void> setProtection(bool on);

  /// Output devices this transport can route to (empty when the OS decides).
  Future<List<AudioOutput>> outputs();
  Future<void> setOutput(String id);
  Future<void> dispose();
}
