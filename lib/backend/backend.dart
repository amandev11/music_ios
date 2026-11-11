import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../engine/transport.dart' show AudioOutput;

/// Per-frame audio features for drawing. Widgets listen on this notifier from a CustomPainter's
/// `repaint`, so 60 Hz updates repaint only the visualizer.
class AudioFrame extends ChangeNotifier {
  AudioFrame({int bands = 32}) : spectrum = Float32List(bands);

  final Float32List spectrum;

  /// Beat envelope 0..1 (1 on the beat); 0 until a beat grid is locked.
  double envelope = 0;
  double rms = 0;
  double bpm = 0;
  double confidence = 0;
  int beatInBar = -1;
  int beatsPerBar = 4;

  bool get beatLocked => bpm > 0 && confidence > 0.4;

  void publish() => notifyListeners();
}

/// Everything the UI needs from an audio engine. Android implements it over the native Media3 +
/// ONNX engine; every other platform implements it in Dart on just_audio / the YouTube IFrame.
abstract class Backend {
  ValueListenable<LibraryData> get library;
  ValueListenable<Snapshot> get snapshot;
  ValueListenable<Progress> get progress;
  AudioFrame get frame;
  ValueListenable<bool> get spatial;
  ValueListenable<PlaybackError?> get errors;

  /// True when [frame] carries real beat detection (native engine); otherwise it is a plain animation.
  bool get hasBeatEngine;
  bool get canAddMusic;
  bool get needsPermission => library.value.state == LibraryState.needsPermission;

  Future<void> init();
  Future<void> requestPermission();
  Future<void> refreshLibrary();
  Future<void> addMusic();

  Future<void> playTracks(List<Track> tracks, int index, {bool shuffle = false});
  Future<void> toggle();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(int ms);
  Future<void> skipTo(int index);
  Future<void> move(int from, int to);
  Future<void> remove(int index);
  Future<void> playNext(Track t);
  Future<void> addToQueue(Track t);
  Future<void> setShuffle(bool on);
  Future<void> cycleRepeat();
  Future<void> setSpeed(double speed);

  Future<List<Track>> searchLocal(String query);
  Future<List<Track>> searchRemote(String query);
  Future<List<Track>> albumTracks(Album album);

  Future<bool> spatialAvailable();
  Future<void> toggleSpatial();

  /// Live tempo from the beat grid; null when unavailable.
  Future<({double bpm, double confidence})?> tempo();
  Future<TrackAnalysis?> analyze(Track t);

  /// Equalizer: always a 10-band curve in dB (see engine/eq.dart); each backend maps it.
  bool get eqSupported;
  Future<void> applyEq(bool enabled, List<double> gains);

  /// Speaker protection: sub-bass filter, peak limiter and headroom on the output.
  Future<void> setOutputProtection(bool on);

  /// Master volume 0..1 and output device routing (empty list = OS default only).
  ValueNotifier<double> get volume;
  Future<void> setVolume(double v);
  Future<List<AudioOutput>> outputs();
  Future<void> setOutput(String id);

  /// Automix crossfade into the next queue item.
  /// [beatMix] false = plain crossfade of [seconds]; true = DJ-style Automix, whose length is picked per
  /// song when [auto] is set (otherwise [seconds] is the maximum).
  Future<void> setAutomix(bool enabled, double seconds, {bool beatMix = true, bool auto = true});

  /// Called by the UI while the full player is visible, to start/stop the 60 Hz frame stream.
  void setFrameActive(bool active);

  Future<void> dispose();
}
