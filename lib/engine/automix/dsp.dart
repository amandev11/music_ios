import 'dart:math';
import 'dart:typed_data';

/// What Automix knows about one track. All times are in milliseconds from the start of the file.
class TrackProfile {
  const TrackProfile({
    required this.bpm,
    required this.confidence,
    required this.firstDownbeatMs,
    required this.key,
    required this.introMs,
    required this.outroMs,
    required this.loudness,
  });

  final double bpm;

  /// 0..1: how clearly a steady pulse was found. Below ~0.25 the tempo is not trusted.
  final double confidence;

  /// A bar line of the beat grid (the grid continues every 4 beats in both directions).
  final double firstDownbeatMs;

  /// Camelot code, e.g. "8A" (A minor) or "8B" (C major); empty when no key was found.
  final String key;

  /// First and last audible moment (leading and trailing silence trimmed).
  final int introMs;
  final int outroMs;

  /// Median level 0..1, used to match the loudness of two songs during a blend.
  final double loudness;

  double get beatMs => bpm > 0 ? 60000 / bpm : 0;
  double get barMs => beatMs * 4;
  bool get tempoReliable => bpm > 0 && confidence >= 0.25;
}

class PcmJob {
  PcmJob(this.samples, this.sampleRate);
  final Int16List samples;
  final int sampleRate;
}

/// Entry point for `compute`.
TrackProfile? analyzeJob(PcmJob job) => analyzePcm(job.samples, job.sampleRate);

// ---------------------------------------------------------------------------------------------
// FFT (radix-2, in place)
// ---------------------------------------------------------------------------------------------

class _Fft {
  _Fft(this.n) {
    cosT = Float64List(n ~/ 2);
    sinT = Float64List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      cosT[i] = cos(2 * pi * i / n);
      sinT[i] = -sin(2 * pi * i / n);
    }
    rev = Int32List(n);
    final bits = (log(n) / ln2).round();
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) r |= 1 << (bits - 1 - b);
      }
      rev[i] = r;
    }
  }

  final int n;
  late final Float64List cosT, sinT;
  late final Int32List rev;

  void run(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final step = n ~/ size;
      for (var start = 0; start < n; start += size) {
        for (var k = 0; k < half; k++) {
          final wr = cosT[k * step], wi = sinT[k * step];
          final a = start + k, b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Analysis
// ---------------------------------------------------------------------------------------------

const _win = 512;
const _hop = 256;

/// Tempo, beat grid, key, silence and loudness from mono 16-bit PCM (11 kHz is plenty).
TrackProfile? analyzePcm(Int16List pcm, int sr) {
  if (pcm.length < sr * 20) return null; // too short to say anything useful

  final frames = (pcm.length - _win) ~/ _hop;
  final fft = _Fft(_win);
  final hann = Float64List(_win);
  for (var i = 0; i < _win; i++) {
    hann[i] = 0.5 - 0.5 * cos(2 * pi * i / (_win - 1));
  }
  final re = Float64List(_win), im = Float64List(_win);
  final maxBin = min(_win ~/ 2 - 1, (4000 / (sr / _win)).floor());
  final prev = Float64List(maxBin + 1);
  final onset = Float64List(frames);
  final rms = Float64List(frames);

  for (var f = 0; f < frames; f++) {
    final off = f * _hop;
    var sum = 0.0;
    for (var i = 0; i < _win; i++) {
      final v = pcm[off + i] / 32768.0;
      sum += v * v;
      re[i] = v * hann[i];
      im[i] = 0;
    }
    rms[f] = sqrt(sum / _win);
    fft.run(re, im);
    var flux = 0.0;
    for (var k = 1; k <= maxBin; k++) {
      final m = log(1 + 20 * sqrt(re[k] * re[k] + im[k] * im[k]));
      final d = m - prev[k];
      if (d > 0) flux += d;
      prev[k] = m;
    }
    onset[f] = flux;
  }

  final fps = sr / _hop;

  // ---- silence trimming and loudness -------------------------------------------------------
  final env = _smooth(rms, (fps * 0.5).round());
  final sorted = List<double>.of(env)..sort();
  final peak = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
  final threshold = peak * 0.06;
  var first = 0, last = frames - 1;
  while (first < frames - 1 && env[first] < threshold) {
    first++;
  }
  while (last > first && env[last] < threshold) {
    last--;
  }
  final audible = [for (var i = first; i <= last; i++) env[i]]..sort();
  final median = audible.isEmpty ? 0.0 : audible[audible.length ~/ 2];
  final introMs = (first * _hop / sr * 1000).round();
  final outroMs = ((last + 1) * _hop / sr * 1000).round();

  // ---- tempo and beat grid -----------------------------------------------------------------
  final o = _detrend(onset, (fps * 0.6).round());
  var meanAll = 0.0;
  for (final v in o) {
    meanAll += v;
  }
  meanAll /= max(1, o.length);

  double sample(double pos) {
    if (pos < 0 || pos >= o.length - 1) return 0;
    final i = pos.floor();
    final fr = pos - i;
    return o[i] * (1 - fr) + o[i + 1] * fr;
  }

  ({double score, double phase}) bestPhase(double period, [double step = 1.0]) {
    var best = -1.0, bestPh = 0.0;
    for (var ph = 0.0; ph < period; ph += step) {
      var s = 0.0;
      var n = 0;
      for (var p = ph; p < o.length - 1; p += period) {
        s += sample(p);
        n++;
      }
      final mean = n == 0 ? 0 : s / n;
      if (mean > best) {
        best = mean.toDouble();
        bestPh = ph;
      }
    }
    return (score: best, phase: bestPh);
  }

  double prior(double bpm) {
    final x = log(bpm / 118) / ln2 / 0.62;
    return exp(-0.5 * x * x);
  }

  var bestBpm = 0.0, bestScore = 0.0;
  for (var bpm = 68.0; bpm <= 178; bpm += 0.5) {
    final period = fps * 60 / bpm;
    final r = bestPhase(period);
    final s = r.score * prior(bpm);
    if (s > bestScore) {
      bestScore = s;
      bestBpm = bpm;
    }
  }
  if (bestBpm == 0) return null;

  // Refine around the winner with finer steps.
  var refinedBpm = bestBpm, refinedScore = 0.0, refinedPhase = 0.0;
  for (var bpm = bestBpm - 0.6; bpm <= bestBpm + 0.6; bpm += 0.05) {
    final period = fps * 60 / bpm;
    final r = bestPhase(period, 0.25);
    if (r.score > refinedScore) {
      refinedScore = r.score;
      refinedBpm = bpm;
      refinedPhase = r.phase;
    }
  }
  final period = fps * 60 / refinedBpm;
  final confidence = meanAll <= 0 ? 0.0 : ((refinedScore / meanAll - 1) / 2.5).clamp(0.0, 1.0);

  // Which of four beats is the bar line: the one whose beats carry the most onset energy.
  final barSums = List<double>.filled(4, 0);
  var k = 0;
  for (var p = refinedPhase; p < o.length - 1; p += period, k++) {
    barSums[k % 4] += sample(p);
  }
  var bar = 0;
  for (var i = 1; i < 4; i++) {
    if (barSums[i] > barSums[bar]) bar = i;
  }
  // Frame index to time: frame centre = start + window/2.
  final beatMs = 60000 / refinedBpm;
  final firstBeatMs = (refinedPhase * _hop + _win / 2) / sr * 1000;
  final firstDownbeatMs = firstBeatMs + bar * beatMs;

  // ---- key ---------------------------------------------------------------------------------
  final key = _estimateKey(pcm, sr, first * _hop, (last + 1) * _hop);

  return TrackProfile(
    bpm: refinedBpm,
    confidence: confidence,
    firstDownbeatMs: firstDownbeatMs,
    key: key,
    introMs: introMs,
    outroMs: outroMs,
    loudness: median,
  );
}

Float64List _smooth(Float64List x, int width) {
  final out = Float64List(x.length);
  final w = max(1, width);
  var acc = 0.0;
  for (var i = 0; i < x.length; i++) {
    acc += x[i];
    if (i >= w) acc -= x[i - w];
    out[i] = acc / min(i + 1, w);
  }
  // Shift back so the average is centred on the frame, not trailing it.
  final shifted = Float64List(x.length);
  final d = w ~/ 2;
  for (var i = 0; i < x.length; i++) {
    shifted[i] = out[min(x.length - 1, i + d)];
  }
  return shifted;
}

Float64List _detrend(Float64List x, int width) {
  final m = _smooth(x, width);
  final out = Float64List(x.length);
  for (var i = 0; i < x.length; i++) {
    final v = x[i] - m[i];
    out[i] = v > 0 ? v : 0;
  }
  return out;
}

const _major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const _minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

/// Krumhansl-Schmuckler key finding on a chromagram, returned as a Camelot code.
String _estimateKey(Int16List pcm, int sr, int fromSample, int toSample) {
  const n = 4096;
  final fft = _Fft(n);
  final hann = Float64List(n);
  for (var i = 0; i < n; i++) {
    hann[i] = 0.5 - 0.5 * cos(2 * pi * i / (n - 1));
  }
  final re = Float64List(n), im = Float64List(n);
  final chroma = List<double>.filled(12, 0);
  final binHz = sr / n;
  final lo = (65 / binHz).ceil(), hi = min(n ~/ 2 - 1, (2000 / binHz).floor());
  // Skip the first/last 10 % (intros and outros are often not in the home key) and step by 2 frames.
  final start = fromSample + ((toSample - fromSample) * 0.1).round();
  final end = toSample - ((toSample - fromSample) * 0.1).round();
  for (var off = start; off + n < min(end, pcm.length); off += n * 2) {
    for (var i = 0; i < n; i++) {
      re[i] = pcm[off + i] / 32768.0 * hann[i];
      im[i] = 0;
    }
    fft.run(re, im);
    for (var k = lo; k <= hi; k++) {
      final mag = sqrt(re[k] * re[k] + im[k] * im[k]);
      final midi = 69 + 12 * log(k * binHz / 440) / ln2;
      final pc = (midi.round() % 12 + 12) % 12;
      chroma[pc] += sqrt(mag);
    }
  }
  final total = chroma.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return '';

  double corr(List<double> profile, int tonic) {
    var mx = 0.0, my = 0.0;
    for (var i = 0; i < 12; i++) {
      mx += chroma[(tonic + i) % 12];
      my += profile[i];
    }
    mx /= 12;
    my /= 12;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < 12; i++) {
      final a = chroma[(tonic + i) % 12] - mx, b = profile[i] - my;
      sxy += a * b;
      sxx += a * a;
      syy += b * b;
    }
    return sxx <= 0 || syy <= 0 ? -1 : sxy / sqrt(sxx * syy);
  }

  var best = -2.0, tonic = 0;
  var minor = false;
  for (var t = 0; t < 12; t++) {
    final a = corr(_major, t), b = corr(_minor, t);
    if (a > best) {
      best = a;
      tonic = t;
      minor = false;
    }
    if (b > best) {
      best = b;
      tonic = t;
      minor = true;
    }
  }
  final majorTonic = minor ? (tonic + 3) % 12 : tonic; // relative major shares the Camelot number
  final number = (majorTonic * 7 + 7) % 12 + 1;
  return '$number${minor ? 'A' : 'B'}';
}
