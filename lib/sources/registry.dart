import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'source.dart';

/// Fans a query out to every enabled source and routes playback by track key. Playback resolution
/// asks the track's own source first; when it has nothing, the same recording is looked up on the
/// others (title/artist/duration match).
class SourceRegistry {
  SourceRegistry(this.sources);

  final List<MusicSource> sources;

  final Map<String, Track> _seen = {};
  final Map<String, (Playable, DateTime)> _streams = {};

  static const _perSource = 12;
  static const _searchTimeout = Duration(seconds: 9);
  static const _ttl = Duration(minutes: 20);

  MusicSource? _byKind(SourceKind k) {
    for (final s in sources) {
      if (s.kind == k) return s;
    }
    return null;
  }

  Track? remember(Track t) => _seen[t.mediaId] = t;

  Future<List<Track>> search(String query, {int perSource = _perSource}) async {
    final lists = await Future.wait(sources.map((s) async {
      try {
        return await s.search(query, limit: perSource).timeout(_searchTimeout);
      } catch (_) {
        return <Track>[];
      }
    }));
    for (final l in lists) {
      for (final t in l) {
        _seen[t.mediaId] = t;
      }
    }
    return _dedupe(_interleave(lists));
  }

  Future<Playable?> resolve(Track track) async {
    final key = track.mediaId;
    _seen.putIfAbsent(key, () => track);
    final hit = _streams[key];
    if (hit != null && DateTime.now().difference(hit.$2) < _ttl) return hit.$1;

    final primary = _byKind(track.kind);
    Playable? found;
    try {
      found = await primary?.stream(TrackKeys.rawId(key));
    } catch (_) {}
    found ??= await _matchElsewhere(track);
    // Last resort for YouTube tracks on Windows: YouTube's own embedded player (see engine/yt_desktop_io.dart).
    if (found == null && track.kind == SourceKind.youtube && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      found = Playable.youtube(TrackKeys.rawId(key));
    }
    if (found != null) _streams[key] = (found, DateTime.now());
    return found;
  }

  void forget(String key) => _streams.remove(key);

  /// Same recording from a different source than the track's own: the safety net when a stream resolves
  /// but then refuses to download (YouTube answering 403).
  Future<Playable?> resolveElsewhere(Track track) async {
    _streams.remove(track.mediaId);
    return _matchElsewhere(track);
  }

  Future<Playable?> _matchElsewhere(Track wanted) async {
    final query = '${wanted.artist} ${wanted.title}'.trim();
    for (final source in sources) {
      if (source.kind == wanted.kind) continue;
      List<Track> candidates;
      try {
        candidates = await source.search(query, limit: 8);
      } catch (_) {
        continue;
      }
      Track? best;
      var bestScore = TrackMatch.threshold;
      for (final c in candidates) {
        final s = TrackMatch.score(wanted, c);
        if (s >= bestScore) {
          best = c;
          bestScore = s;
        }
      }
      if (best == null) continue;
      try {
        final p = await source.stream(TrackKeys.rawId(best.mediaId));
        if (p != null) return p;
      } catch (_) {}
    }
    return null;
  }

  List<Track> _interleave(List<List<Track>> lists) {
    final out = <Track>[];
    var longest = 0;
    for (final l in lists) {
      if (l.length > longest) longest = l.length;
    }
    for (var i = 0; i < longest; i++) {
      for (final l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }

  List<Track> _dedupe(List<Track> tracks) {
    final seen = <String>{};
    return tracks.where((t) {
      final a = TrackMatch.normalize(t.artist);
      final k = '${TrackMatch.normalize(t.title)}|${a.length > 12 ? a.substring(0, 12) : a}';
      return seen.add(k);
    }).toList();
  }
}

class TrackMatch {
  static const threshold = 0.62;

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
      .replaceAll(RegExp(r'\b(feat|ft|featuring|official|video|audio|lyrics?|remaster(ed)?|version)\b.*'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static Set<String> _tokens(String s) => normalize(s).split(' ').where((e) => e.isNotEmpty).toSet();

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.union(b).length;
  }

  static double score(Track wanted, Track c) {
    final title = _jaccard(_tokens(wanted.title), _tokens(c.title));
    if (title < 0.5) return 0;
    final artist = _jaccard(_tokens(wanted.artist), _tokens(c.artist));
    final d1 = wanted.durationMs ~/ 1000;
    final d2 = c.durationMs ~/ 1000;
    double duration;
    if (d1 > 0 && d2 > 0) {
      final diff = (d1 - d2).abs();
      if (diff > 8) return 0;
      duration = 1.0 - diff / 8.0 * 0.3;
    } else {
      duration = 0.8;
    }
    return title * 0.5 + artist * 0.3 + duration * 0.2;
  }
}
