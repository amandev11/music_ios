import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../core/models.dart';

/// One smoothed reading for the shader and the lyrics: three band energies and a beat impulse, all 0..1.
@immutable
class AudioSpectrumData {
  const AudioSpectrumData({
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.beatImpulse = 0,
    this.isReal = false,
    this.bands,
  });

  final double bass;
  final double mid;
  final double treble;

  /// 1 on a detected (or synthesised) beat, decaying to 0 between beats.
  final double beatImpulse;

  /// True when the numbers come from the engine's real spectrum rather than the rhythmic fallback.
  final bool isReal;

  /// Sixteen smoothed band levels, lowest frequency first, for the spectrum scenes.
  final Float32List? bands;

  static const silent = AudioSpectrumData();
}

/// Turns the backend's [AudioFrame] into [AudioSpectrumData].
///
/// Real path: the native Android engine publishes a log-spaced PCM spectrum and a beat envelope in
/// `backend.frame`; its bands are grouped into sub-bass (20-150 Hz), mids (150-2000 Hz) and highs
/// (2000-16000 Hz). The other engines cannot tap raw PCM without a native FFT, so the fallback path
/// synthesises a rhythmic envelope locked to the song position and tempo. Nothing here ever throws:
/// a missing spectrum just means the fallback is used.
///
/// Call [tick] once per animation frame; [data] then notifies the shader painter and the lyrics.
class AudioSpectrumEngine {
  AudioSpectrumEngine({
    required this.backend,
    required this.positionMs,
    this.attack = 0.35,
    this.release = 0.08,
  });

  final Backend backend;

  /// Current heard position of the song in milliseconds.
  final int Function() positionMs;

  /// Smoothing per 60 Hz frame: how fast a value rises on a transient and how slowly it falls back.
  final double attack;
  final double release;

  final ValueNotifier<AudioSpectrumData> data = ValueNotifier(
    AudioSpectrumData.silent,
  );

  double _bass = 0, _mid = 0, _treble = 0, _beat = 0;
  final Float32List _bands = Float32List(16);
  final Float32List _bandTarget = Float32List(16);
  Duration _last = Duration.zero;
  int _realFrames = 0;
  Track? _track;
  double _fallbackBpm = 112;

  static const double _loHz = 20, _hiHz = 16000;

  /// Whether the engine is currently being fed by real spectrum data.
  bool get usingRealData => _realFrames > 6;

  void setTrack(Track? t) {
    if (t?.mediaId == _track?.mediaId) return;
    _track = t;
    // A stable pseudo tempo per song (90..138 bpm) so the fallback feels different from song to song.
    final h = (t?.mediaId.hashCode ?? 0).abs();
    _fallbackBpm = 90 + (h % 49).toDouble();
  }

  /// Advance by one frame. [elapsed] is the ticker time; [playing] false lets the values decay to zero.
  void tick(Duration elapsed, {required bool playing}) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.001, 0.1);
    _last = elapsed;
    // Frame-rate independent smoothing: the constants are per 60 Hz frame.
    final k = dt * 60;
    double a(double rate) => 1 - math.pow(1 - rate, k).toDouble();

    double tb = 0, tm = 0, tt = 0, tBeat = 0;
    var real = false;
    if (playing) {
      final r = _readReal();
      if (r != null) {
        (tb, tm, tt, tBeat) = r;
        real = true;
      } else {
        (tb, tm, tt, tBeat) = _synth(elapsed);
      }
    }
    _realFrames = real ? _realFrames + 1 : 0;
    if (!real && playing) _synthBands(elapsed, tb, tm, tt);
    for (var i = 0; i < 16; i++) {
      final target = playing ? _bandTarget[i] : 0.0;
      _bands[i] +=
          (target - _bands[i]) * (target > _bands[i] ? a(attack) : a(release));
    }

    _bass += (tb - _bass) * (tb > _bass ? a(attack) : a(release));
    _mid += (tm - _mid) * (tm > _mid ? a(attack) : a(release));
    _treble += (tt - _treble) * (tt > _treble ? a(attack) : a(release));
    _beat = math.max(tBeat, _beat * math.pow(0.88, k).toDouble());
    data.value = AudioSpectrumData(
      bass: _bass.clamp(0.0, 1.0),
      mid: _mid.clamp(0.0, 1.0),
      treble: _treble.clamp(0.0, 1.0),
      beatImpulse: _beat.clamp(0.0, 1.0),
      isReal: real,
      bands: Float32List.fromList(_bands),
    );
  }

  (double, double, double, double)? _readReal() {
    try {
      if (!backend.hasBeatEngine) return null;
      final f = backend.frame;
      final s = f.spectrum;
      final n = s.length;
      if (n == 0) return null;
      double peak(int from, int to) {
        var m = 0.0;
        for (var i = from; i < to && i < n; i++) {
          m = math.max(m, s[i].toDouble());
        }
        return m;
      }

      double bass = 0, mid = 0, high = 0, bn = 0, mn = 0, hn = 0, total = 0;
      for (var i = 0; i < n; i++) {
        // Centre frequency of a log-spaced band.
        final hz = _loHz * math.pow(_hiHz / _loHz, (i + 0.5) / n).toDouble();
        final v = s[i].toDouble().clamp(0.0, 1.0);
        total += v;
        if (hz < 150) {
          bass += v;
          bn++;
        } else if (hz < 2000) {
          mid += v;
          mn++;
        } else {
          high += v;
          hn++;
        }
      }
      if (total < 0.002) return null;
      for (var b = 0; b < 16; b++) {
        final from = (b * n / 16).floor(),
            to = math.max(from + 1, ((b + 1) * n / 16).floor());
        _bandTarget[b] = (peak(from, to) * (1.0 + b * 0.05)).clamp(0.0, 1.0);
      }
      // Bass is taken as the strongest band so a single kick drum still reads at full strength.
      final bassBands = math.max(1, bn.round());
      final bassOut = math.max(bn > 0 ? bass / bn : 0, peak(0, bassBands));
      final midOut = mn > 0 ? mid / mn * 1.6 : 0;
      final highOut = hn > 0 ? high / hn * 2.4 : 0;
      final beat = f.beatLocked
          ? f.envelope
          : bassOut > 0.7
          ? bassOut
          : 0.0;
      return (
        bassOut.clamp(0.0, 1.0).toDouble(),
        midOut.clamp(0.0, 1.0).toDouble(),
        highOut.clamp(0.0, 1.0).toDouble(),
        beat.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Plausible per-band levels for the fallback: bass bands follow the kick, highs the hats.
  void _synthBands(Duration elapsed, double bass, double mid, double treble) {
    final t = elapsed.inMicroseconds / 1e6;
    for (var i = 0; i < 16; i++) {
      final x = i / 15.0;
      final base = x < 0.25
          ? bass
          : x < 0.65
          ? mid
          : treble;
      final wob = 0.6 + 0.4 * math.sin(t * (2.0 + i * 0.9) + i * 1.7);
      _bandTarget[i] = (base * wob * (1.05 - 0.35 * x)).clamp(0.0, 1.0);
    }
  }

  /// Rhythmic envelope: a kick on every beat, a softer snare-like swell on 2 and 4, off-beat hats and a
  /// slow section swell, all derived from the song position so seeking keeps it in time.
  (double, double, double, double) _synth(Duration elapsed) {
    final bpm = backend.frame.bpm > 40 ? backend.frame.bpm : _fallbackBpm;
    final pos = positionMs() / 1000.0;
    final beats = pos * bpm / 60.0;
    final phase = beats - beats.floorToDouble();
    final beatIdx = beats.floor();
    final section = 0.75 + 0.25 * math.sin(pos / 14.0);
    final kick = math.exp(-phase * 7.0);
    final accent = beatIdx.isEven ? 1.0 : 0.82;
    final bass = (0.14 + 0.86 * kick * accent) * section;
    final snareWindow = (beatIdx % 4 == 1 || beatIdx % 4 == 3) ? 1.0 : 0.0;
    final mid =
        (0.22 +
            0.2 * (0.5 + 0.5 * math.sin(pos * 1.7)) +
            0.45 * snareWindow * math.exp(-phase * 5.0)) *
        section;
    final off = phase < 0.5 ? phase + 0.5 : phase - 0.5;
    final hat = math.exp(-off * 11.0);
    final treble =
        (0.1 + 0.55 * hat + 0.1 * (0.5 + 0.5 * math.sin(pos * 9.0))) * section;
    final beat = phase < 0.08 ? kick * accent : 0.0;
    return (bass, mid, treble, beat);
  }

  void dispose() => data.dispose();
}
