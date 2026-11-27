import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../sources/lyrics.dart';

/// Disk cache for lyrics so a repeat play is ready in a few milliseconds without the network.
/// Keeps the most recent [capacity] songs, oldest dropped first. Misses are cached as well, for a day,
/// so instrumentals do not hit LRCLIB again and again.
class LyricsDiskCache {
  LyricsDiskCache._();

  static const capacity = 120;
  static const _index = 'vlyr.index';
  static final Map<String, Lyrics?> _mem = {};

  static String _key(Track t) => 'vlyr.${t.mediaId}';

  /// Returns (hit, lyrics): hit false means the song was never looked up; lyrics null means a known miss.
  static Future<(bool, Lyrics?)> read(Track t) async {
    final k = _key(t);
    if (_mem.containsKey(k)) return (true, _mem[k]);
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(k);
      if (raw == null) return (false, null);
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['miss'] == true) {
        final at = (m['at'] as num?)?.toInt() ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - at > 86400000) {
          return (false, null);
        }
        _mem[k] = null;
        return (true, null);
      }
      final lines = [
        for (final e in (m['l'] as List))
          LyricLine((e as List)[0] as int, e[1] as String),
      ];
      final l = Lyrics(lines, synced: m['s'] == true);
      _mem[k] = l;
      return (true, l);
    } catch (_) {
      return (false, null);
    }
  }

  static Future<void> write(Track t, Lyrics? l) async {
    final k = _key(t);
    _mem[k] = l;
    try {
      final p = await SharedPreferences.getInstance();
      final body = l == null
          ? {'miss': true, 'at': DateTime.now().millisecondsSinceEpoch}
          : {
              's': l.synced,
              'l': [
                for (final line in l.lines) [line.timeMs, line.text],
              ],
            };
      await p.setString(k, jsonEncode(body));
      final idx = (p.getStringList(_index) ?? <String>[])
        ..remove(k)
        ..add(k);
      while (idx.length > capacity) {
        await p.remove(idx.removeAt(0));
      }
      await p.setStringList(_index, idx);
    } catch (_) {}
  }
}
