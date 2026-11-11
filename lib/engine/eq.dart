/// The equalizer is always edited as a 10-band curve in dB; each backend maps it to what it has
/// (mpv's `equalizer` filter, Android's hardware Equalizer with 5 or so bands).
const eqFrequencies = <double>[31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const eqMinDb = -12.0;
const eqMaxDb = 12.0;

const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass Booster': [6, 5.5, 4.5, 2.5, 1, 0, 0, 0, 0, 0],
  'Bass Reducer': [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0],
  'Treble Booster': [0, 0, 0, 0, 0, 1, 2.5, 4, 5.5, 6],
  'Treble Reducer': [0, 0, 0, 0, 0, -1, -2.5, -4, -5.5, -6],
  'Vocal Booster': [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1],
  'Loudness': [5, 4, 1, 0, -1, -1, 0, 1, 4, 5],
  'Acoustic': [4, 4, 3, 1, 1, 1, 2, 3, 3, 2],
  'Classical': [4, 3, 3, 2, -1, -1, 0, 2, 3, 4],
  'Dance': [6, 5, 3, 0, 0, -2, -3, -3, 0, 0],
  'Electronic': [4, 4, 1, 0, -2, 2, 1, 1, 4, 5],
  'Hip-Hop': [5, 4, 1, 3, -1, -1, 1, -1, 2, 3],
  'Jazz': [3, 2, 1, 2, -2, -2, 0, 1, 2, 3],
  'Pop': [-1, 1, 3, 4, 3, 0, -1, -1, -1, -1],
  'Rock': [4, 3, 1, -1, -2, -1, 1, 3, 4, 5],
};

/// mpv audio filter chain for [gains] (dB per band), or an empty string when the curve is flat.
String mpvEqFilter(bool enabled, List<double> gains) {
  if (!enabled || gains.every((g) => g.abs() < 0.05)) return '';
  final parts = <String>[];
  for (var i = 0; i < eqFrequencies.length && i < gains.length; i++) {
    if (gains[i].abs() < 0.05) continue;
    parts.add('equalizer=f=${eqFrequencies[i].toStringAsFixed(0)}:t=o:w=1:g=${gains[i].toStringAsFixed(2)}');
  }
  // Pull the whole signal down by the strongest boost so boosted bands cannot clip.
  final peak = gains.reduce((a, b) => a > b ? a : b);
  if (peak > 0) parts.add('volume=${(-peak).toStringAsFixed(2)}dB');
  return 'lavfi=[${parts.join(',')}]';
}
