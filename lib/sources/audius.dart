import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/settings.dart';
import 'source.dart';

/// Audius: an open, artist-owned catalogue with a public keyless API and full-length streams.
class AudiusSource implements MusicSource {
  AudiusSource(this._settings, {http.Client? client})
    : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;

  static const _base = 'https://api.audius.co';
  static const _app = 'keystone';

  @override
  SourceKind get kind => SourceKind.audius;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    try {
      final url = Uri.parse('$_base/v1/tracks/search').replace(
        queryParameters: {
          'query': query,
          'app_name': _app,
          'limit': '${limit.clamp(1, 30)}',
        },
      );
      final res = await _http
          .get(_settings.proxied(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final data = j is Map && j['data'] is List ? j['data'] as List : const [];
      final out = <Track>[];
      for (final t in data) {
        if (t is! Map) continue;
        final id = '${t['id'] ?? ''}';
        if (id.isEmpty || t['is_streamable'] == false) continue;
        final art = t['artwork'];
        String? cover;
        if (art is Map) {
          final c = '${art['1000x1000'] ?? art['480x480'] ?? ''}';
          if (c.isNotEmpty) cover = c;
        }
        final user = t['user'];
        out.add(
          Track(
            mediaId: TrackKeys.audius(id),
            title: '${t['title'] ?? ''}',
            artist: user is Map && '${user['name'] ?? ''}'.isNotEmpty
                ? '${user['name']}'
                : 'Unknown Artist',
            album: '${t['genre'] ?? ''}',
            durationMs: ((t['duration'] as num?) ?? 0).toInt() * 1000,
            artworkUri: cover,
            mimeType: 'audio/mpeg',
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Playable?> stream(String rawId, {int? quality}) async =>
      Playable.url('$_base/v1/tracks/$rawId/stream?app_name=$_app', kbps: 320);
}
