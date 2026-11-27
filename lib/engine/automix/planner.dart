import 'dart:math';

import '../../core/models.dart';
import 'dsp.dart';

/// One planned transition from song A (playing) into song B (next).
class MixPlan {
  const MixPlan({
    required this.mixStartMs,
    required this.fadeMs,
    required this.bSeekMs,
    required this.bSpeed,
    required this.beatMatched,
    required this.keyCompatible,
    required this.bTrim,
    this.dj = 1,
    this.phraseAligned = false,
  });

  /// Position in A at which B starts and the blend begins.
  final int mixStartMs;
  final int fadeMs;

  /// Where in B to start (skips leading silence, lands on a bar line when beat-matched).
  final int bSeekMs;

  /// Playback speed given to B at the start so its tempo equals A's; eased back to 1 during the blend.
  final double bSpeed;
  final bool beatMatched;
  final bool keyCompatible;

  /// Starting gain for B (< 1 when B is louder than A); eased to 1 during the blend.
  final double bTrim;

  /// DJ style used for this blend: 0 smooth, 1 club, 2 quick cut.
  final int dj;

  /// The blend starts on an 4-bar phrase boundary of A, so the songs change section together.
  final bool phraseAligned;

  String describe() => beatMatched
      ? '${dj == 2
            ? 'quick cut'
            : dj == 0
            ? 'smooth'
            : 'club'} beat-matched (B x${bSpeed.toStringAsFixed(3)}), ${(fadeMs / 1000).toStringAsFixed(1)}s, ${keyCompatible ? 'harmonic' : 'key clash'}${phraseAligned ? ', on the phrase' : ''}'
      : 'smart crossfade ${fadeMs ~/ 1000}s';
}

class MixPlanner {
  /// Wired by the app: per-song custom transition ({mode: auto|crossfade|beat|none, sec}) and whether
  /// DJ filters are wanted.
  static Map<String, dynamic>? Function(String mediaId) overrideFor = (_) =>
      null;
  static bool filtersEnabled = false;

  /// 0 smooth blend, 1 club (beat-matched with bass swap), 2 quick cut on the beat.
  static int djStyle = 1;

  /// Camelot wheel distance: 0 same key, 1 relative or adjacent (blends well), 2+ clashes.
  static int keyDistance(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 2;
    final na = int.tryParse(a.substring(0, a.length - 1)),
        nb = int.tryParse(b.substring(0, b.length - 1));
    if (na == null || nb == null) return 2;
    final la = a[a.length - 1], lb = b[b.length - 1];
    var d = (na - nb).abs();
    d = min(d, 12 - d);
    if (la == lb) return d;
    return d == 0 ? 1 : d + 1;
  }

  /// Plain crossfade: B starts at A's start-of-fade and both are blended for [seconds] (capped to the songs' length).
  static MixPlan? crossfade({
    required int aDurMs,
    required int bDurMs,
    required double seconds,
  }) {
    var f = (seconds * 1000).round();
    f = min(f, (aDurMs * 0.45).round());
    if (bDurMs > 0) f = min(f, (bDurMs * 0.45).round());
    if (f < 800) return null;
    return MixPlan(
      mixStartMs: aDurMs - f,
      fadeMs: f,
      bSeekMs: 0,
      bSpeed: 1,
      beatMatched: false,
      keyCompatible: false,
      bTrim: 1,
    );
  }

  static MixPlan? plan({
    required Track a,
    required Track b,
    required TrackProfile? pa,
    required TrackProfile? pb,
    required int aDurMs,
    required double maxSeconds,
    bool auto = false,
  }) {
    final ov = overrideFor(a.mediaId);
    final mode = '${ov?['mode'] ?? 'auto'}';
    if (mode == 'none') return null; // user wants this song to end normally
    final ovSec = (ov?['sec'] as num?)?.toDouble() ?? 0;
    final explicit = ovSec > 0 && mode != 'auto';
    // Automatic length: a full 30 s blend. A length the listener chose (in Settings or for this song) is never
    // shortened, rounded to bars or capped to a tempo: it is used exactly as set.
    final userLength = explicit || !auto;
    final maxMs = !userLength
        ? 30000
        : ((explicit ? ovSec : maxSeconds) * 1000).round();
    final albumFlow =
        a.album.isNotEmpty &&
        a.album == b.album &&
        a.trackNumber > 0 &&
        b.trackNumber == a.trackNumber + 1;
    final skipB = pb != null && pb.introMs > 600 ? max(0, pb.introMs - 150) : 0;
    final trim = _trim(pa, pb);

    int capFade(int ms) {
      final share = userLength ? 0.45 : 0.25;
      var f = min(ms, (aDurMs * share).round());
      if (b.durationMs > 0) f = min(f, (b.durationMs * share).round());
      return max(f, 1500);
    }

    // Plain: no usable analysis. Still skips B's silence and respects album flow.
    MixPlan plain() {
      final plainMs = maxMs;
      final fade = capFade(
        albumFlow && !userLength ? min(plainMs, 2500) : plainMs,
      );
      final endA = pa != null && pa.outroMs > 0
          ? min(pa.outroMs, aDurMs)
          : aDurMs;
      return MixPlan(
        mixStartMs: max(0, endA - fade),
        fadeMs: fade,
        bSeekMs: skipB,
        bSpeed: 1,
        beatMatched: false,
        keyCompatible:
            pa != null && pb != null && keyDistance(pa.key, pb.key) <= 1,
        bTrim: trim,
      );
    }

    if (mode == 'crossfade') return plain();
    if (pa == null ||
        pb == null ||
        !pa.tempoReliable ||
        !pb.tempoReliable ||
        (albumFlow && !explicit))
      return plain();

    // Fold B's tempo by an octave if that brings it closer to A's (e.g. 70 vs 140 BPM).
    var bBpm = pb.bpm;
    for (final f in const [0.5, 2.0]) {
      if ((bBpm * f - pa.bpm).abs() < (bBpm - pa.bpm).abs()) bBpm = pb.bpm * f;
    }
    final ratio = pa.bpm / bBpm; // speed to apply to B
    if ((ratio - 1).abs() > 0.08) return plain();

    final compat = keyDistance(pa.key, pb.key) <= 1;
    final beat = pa.beatMs;
    int fade;
    if (userLength) {
      fade = capFade(maxMs); // exactly the length the listener asked for
    } else {
      // Auto: the longest whole number of bars within 30 s (so the blend ends on a bar line too).
      var beats = max(8, (maxMs / beat / 4).floor() * 4);
      if (beats * beat > maxMs) beats -= 4;
      fade = capFade((max(beats, 4) * beat).round());
    }
    // DJ habits: a key clash is kept short (8 beats), a harmonic pair is allowed to run long, and the
    // quick-cut style is just 4 beats. Lengths the listener set are never touched.
    if (!userLength) {
      if (djStyle == 2) {
        fade = capFade((4 * beat).round());
      } else if (!compat) {
        fade = min(fade, capFade((8 * beat).round()));
      }
    }

    // A: last bar line at or before (end of audible audio - fade).
    final endA = pa.outroMs > 0 ? min(pa.outroMs, aDurMs) : aDurMs;
    final target = endA - fade;
    final bar = pa.barMs;
    var k = ((target - pa.firstDownbeatMs) / bar).floor();
    var start = pa.firstDownbeatMs + k * bar;
    while (start + fade > aDurMs - 250 && k > 0) {
      k--;
      start = pa.firstDownbeatMs + k * bar;
    }
    // Land on a 4-bar phrase boundary when that costs at most two bars of A's tail.
    var phrase = false;
    final over = k % 4;
    if (k >= 4 && over <= 2) {
      final ks = k - over;
      final cand = pa.firstDownbeatMs + ks * bar;
      if (cand >= aDurMs * 0.35) {
        start = cand;
        phrase = true;
      }
    }
    if (start < aDurMs * 0.35) return plain();

    // B: first bar line (in B's own file time) at or after its audible start.
    var j = ((skipB - pb.firstDownbeatMs) / pb.barMs).ceil();
    if (j < 0) j = 0;
    final bStart = pb.firstDownbeatMs + j * pb.barMs;

    return MixPlan(
      mixStartMs: start.round(),
      fadeMs: fade,
      bSeekMs: bStart.round(),
      bSpeed: ratio,
      beatMatched: true,
      keyCompatible: compat,
      bTrim: trim,
      dj: djStyle,
      phraseAligned: phrase,
    );
  }

  /// "Mix now": blend into the next song starting at the next bar line of A (or at once when no beat grid is known).
  static MixPlan? now({
    required Track a,
    required Track b,
    required TrackProfile? pa,
    required TrackProfile? pb,
    required int posMs,
    required int aDurMs,
  }) {
    final remaining = aDurMs - posMs;
    if (remaining < 2500) return null;
    final trim = _trim(pa, pb);
    final skipB = pb != null && pb.introMs > 600 ? max(0, pb.introMs - 150) : 0;
    if (pa != null && pb != null && pa.tempoReliable && pb.tempoReliable) {
      var bBpm = pb.bpm;
      for (final f in const [0.5, 2.0]) {
        if ((bBpm * f - pa.bpm).abs() < (bBpm - pa.bpm).abs())
          bBpm = pb.bpm * f;
      }
      final ratio = pa.bpm / bBpm;
      if ((ratio - 1).abs() <= 0.08) {
        final bar = pa.barMs;
        final k = ((posMs + 350 - pa.firstDownbeatMs) / bar).ceil();
        final start = (pa.firstDownbeatMs + k * bar).round();
        var fade = (djStyle == 2 ? 4 : 8) * pa.beatMs.round();
        fade = min(fade, ((aDurMs - start) * 0.9).round());
        if (b.durationMs > 0) fade = min(fade, (b.durationMs * 0.45).round());
        if (fade >= 1500 && start + 1000 < aDurMs) {
          var j = ((skipB - pb.firstDownbeatMs) / pb.barMs).ceil();
          if (j < 0) j = 0;
          return MixPlan(
            mixStartMs: start,
            fadeMs: fade,
            bSeekMs: (pb.firstDownbeatMs + j * pb.barMs).round(),
            bSpeed: ratio,
            beatMatched: true,
            keyCompatible: keyDistance(pa.key, pb.key) <= 1,
            bTrim: trim,
            dj: djStyle,
          );
        }
      }
    }
    final fade = min(6000, (remaining * 0.8).round());
    return MixPlan(
      mixStartMs: posMs,
      fadeMs: fade,
      bSeekMs: skipB,
      bSpeed: 1,
      beatMatched: false,
      keyCompatible: false,
      bTrim: trim,
      dj: djStyle,
    );
  }

  static double _trim(TrackProfile? a, TrackProfile? b) {
    if (a == null || b == null || a.loudness <= 0 || b.loudness <= 0) return 1;
    return (a.loudness / b.loudness).clamp(0.5, 1.0);
  }
}
