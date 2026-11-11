import 'dart:math';

import 'models.dart';
import 'settings.dart';

/// On-device taste model. Every start, skip and like is stored locally; nothing leaves the device.
///
/// Artist affinity = sum over plays of  weight * 0.5^(age / 21 days)
///   full listen +1, skip -1.5, like +4 (likes never decay below a floor, so old favourites stay).
/// Tracks the listener skipped quickly are pushed down, tracks heard in the last hours are held back
/// so the same few songs do not loop, and a weighted random draw keeps results varied.
class Recommender {
  Recommender(this.settings);
  final Settings settings;
  final _rng = Random();

  static const _halfLifeDays = 21.0;

  static String artistKey(String artist) {
    final first = artist.split(RegExp(r'\s*(,|&| x | feat\.?| ft\.?| and )\s*', caseSensitive: false)).first;
    return first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-෿ ]'), '').trim();
  }

  Map<String, double> _affinity() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <String, double>{};
    for (final p in settings.plays) {
      final k = artistKey('${p['artist'] ?? ''}');
      if (k.isEmpty) continue;
      final ageDays = (now - ((p['ts'] as num?)?.toInt() ?? now)) / 86400000.0;
      final w = p['skip'] == true ? -1.5 : 1.0;
      out[k] = (out[k] ?? 0) + w * pow(0.5, ageDays / _halfLifeDays);
    }
    for (final m in likedTracks()) {
      final k = artistKey('${m['artist'] ?? ''}');
      if (k.isNotEmpty) out[k] = (out[k] ?? 0) + 4;
    }
    return out;
  }

  List<Map<String, dynamic>> likedTracks() {
    for (final p in settings.playlists) {
      if (p['id'] == 'liked') return [for (final m in (p['tracks'] as List)) Map<String, dynamic>.from(m as Map)];
    }
    return const [];
  }

  bool get hasTaste => _affinity().values.any((v) => v > 0.5);

  /// Display names of the artists the listener leans towards, best first.
  List<String> topArtists({int n = 5}) {
    final names = <String, String>{};
    for (final p in settings.plays.reversed) {
      final a = '${p['artist'] ?? ''}';
      names.putIfAbsent(artistKey(a), () => a.split(RegExp(r'\s*(,|&)\s*')).first);
    }
    for (final m in likedTracks()) {
      final a = '${m['artist'] ?? ''}';
      names.putIfAbsent(artistKey(a), () => a.split(RegExp(r'\s*(,|&)\s*')).first);
    }
    final aff = _affinity().entries.where((e) => e.value > 0 && names.containsKey(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in aff.take(n)) names[e.key]!];
  }

  Set<String> get _recentlyHeard {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 3 * 3600 * 1000;
    return {
      for (final p in settings.plays)
        if (((p['ts'] as num?)?.toInt() ?? 0) > cutoff) '${p['id']}'
    };
  }

  Set<String> get _skipped => {
        for (final p in settings.plays)
          if (p['skip'] == true) '${p['id']}'
      };

  double score(Track t, [Map<String, double>? aff]) {
    final a = (aff ?? _affinity())[artistKey(t.artist)] ?? 0;
    var s = 1 + max(-0.8, min(a, 12)) * 0.5;
    if (_skipped.contains(t.mediaId)) s *= 0.25;
    if (_recentlyHeard.contains(t.mediaId)) s *= 0.3;
    return max(0.05, s);
  }

  /// Weighted shuffle (Efraimidis-Spirakis): liked artists surface earlier, but order stays random.
  List<Track> rank(List<Track> tracks) {
    final aff = _affinity();
    final keyed = [
      for (final t in tracks) (t, pow(_rng.nextDouble(), 1 / score(t, aff)).toDouble()),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in keyed) e.$1];
  }
}
