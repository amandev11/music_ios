import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/settings.dart';
import 'source.dart';

/// Browser YouTube: search through Invidious (CORS-enabled JSON), playback through the official
/// YouTube IFrame player, which is the only audio path a browser is allowed to take.
class YouTubeWebSource implements MusicSource {
  YouTubeWebSource(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;

  @override
  SourceKind get kind => SourceKind.youtube;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    for (final host in _settings.invidiousHosts) {
      try {
        final url = Uri.parse('$host/api/v1/search').replace(queryParameters: {
          'q': query,
          'type': 'video',
          'fields': 'videoId,title,author,lengthSeconds',
        });
        final res = await _http.get(_settings.proxied(url)).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;
        final list = jsonDecode(utf8.decode(res.bodyBytes));
        if (list is! List) continue;
        final out = <Track>[];
        for (final v in list.whereType<Map>()) {
          final secs = (v['lengthSeconds'] as num?)?.toInt() ?? 0;
          final id = v['videoId'] as String?;
          if (id == null || secs < 30 || secs > 15 * 60) continue;
          out.add(Track(
            mediaId: TrackKeys.youtube(id),
            title: decodeEntities((v['title'] as String?) ?? ''),
            artist: ((v['author'] as String?) ?? '').replaceAll(RegExp(r' - Topic$'), ''),
            durationMs: secs * 1000,
            artworkUri: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
            uri: TrackKeys.youtube(id),
          ));
          if (out.length >= limit) break;
        }
        if (out.isNotEmpty) return out;
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  @override
  Future<Playable?> stream(String rawId) async => Playable.youtube(rawId);
}
