import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/settings.dart';

class LyricLine {
  const LyricLine(this.timeMs, this.text);
  final int timeMs;
  final String text;
}

class Lyrics {
  const Lyrics(this.lines, {required this.synced});
  final List<LyricLine> lines;
  final bool synced;

  /// Index of the line playing at [positionMs], or -1 before the first.
  int activeIndex(int positionMs) {
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].timeMs <= positionMs) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}

/// Time-synced lyrics from LRCLIB (open, keyless); plain text when no synced version exists.
class LyricsRepository {
  LyricsRepository(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;
  final Map<String, Lyrics> _cache = {};
  final Set<String> _misses = {};

  Future<Lyrics?> fetch(Track t) async {
    final c = _cache[t.mediaId];
    if (c != null) return c;
    if (_misses.contains(t.mediaId) || t.title.isEmpty) return null;
    Lyrics? r;
    try {
      r = await _lookup(t);
    } catch (_) {}
    if (r != null) {
      _cache[t.mediaId] = r;
    } else {
      _misses.add(t.mediaId);
    }
    return r;
  }

  Future<Lyrics?> _lookup(Track t) async {
    final secs = t.durationMs ~/ 1000;
    final exact = await _get('get', {
      'track_name': t.title,
      'artist_name': t.artist,
      if (t.album.isNotEmpty) 'album_name': t.album,
      if (secs > 0) 'duration': '$secs',
    });
    if (exact is Map) {
      final l = _fromJson(exact);
      if (l != null) return l;
    }
    final list = await _get('search', {'track_name': t.title, 'artist_name': t.artist});
    if (list is! List) return null;
    final candidates = list
        .whereType<Map>()
        .where((m) => secs <= 0 || (((m['duration'] as num?)?.toDouble() ?? 0) - secs).abs() <= 4)
        .toList()
      ..sort((a, b) => (_has(b['syncedLyrics']) ? 1 : 0).compareTo(_has(a['syncedLyrics']) ? 1 : 0));
    return candidates.isEmpty ? null : _fromJson(candidates.first);
  }

  bool _has(Object? v) => v is String && v.isNotEmpty;

  Lyrics? _fromJson(Map o) {
    final synced = o['syncedLyrics'];
    if (_has(synced)) {
      final lines = parseLrc(synced as String);
      if (lines.isNotEmpty) return Lyrics(lines, synced: true);
    }
    final plain = o['plainLyrics'];
    if (!_has(plain)) return null;
    return Lyrics([for (final l in LineSplitter.split(plain as String)) LyricLine(0, l.trim())], synced: false);
  }

  Future<Object?> _get(String path, Map<String, String> q) async {
    final url = Uri.https('lrclib.net', '/api/$path', q);
    final res = await _http.get(_settings.proxied(url)).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static final _time = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

  /// `[mm:ss.xx] text`, including several stamps on one line.
  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    var offset = 0;
    for (final raw in LineSplitter.split(lrc)) {
      final line = raw.trim();
      if (line.toLowerCase().startsWith('[offset:')) {
        offset = int.tryParse(line.substring(line.indexOf(':') + 1).replaceAll(']', '').trim()) ?? 0;
        continue;
      }
      final stamps = _time.allMatches(line).toList();
      if (stamps.isEmpty) continue;
      final text = line.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final f = m.group(3) ?? '';
        final frac = f.isEmpty
            ? 0
            : f.length == 1
                ? int.parse(f) * 100
                : f.length == 2
                    ? int.parse(f) * 10
                    : int.parse(f.substring(0, 3));
        out.add(LyricLine((min * 60 + sec) * 1000 + frac - offset, text));
      }
    }
    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }
}
