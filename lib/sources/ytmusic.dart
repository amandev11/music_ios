import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';

/// YouTube Music search over the same InnerTube endpoint ytmusicapi uses (WEB_REMIX client): real
/// songs with proper artist, album, duration and square cover art, not random uploads and clips.
class YtMusicSearch {
  YtMusicSearch({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _songsFilter = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  Future<List<Track>> songs(String query, {int limit = 20}) async {
    final filtered = await _search(query, _songsFilter);
    if (filtered.isNotEmpty) return filtered.take(limit).toList();
    return (await _search(query, null)).take(limit).toList();
  }

  Future<List<Track>> _search(String query, String? params) async {
    try {
      final res = await _http
          .post(
            Uri.https('music.youtube.com', '/youtubei/v1/search', {'prettyPrint': 'false'}),
            headers: const {
              'Content-Type': 'application/json',
              'Origin': 'https://music.youtube.com',
              'Referer': 'https://music.youtube.com/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            },
            body: jsonEncode({
              'context': {
                'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20250210.01.00', 'hl': 'en', 'gl': 'US'},
              },
              'query': query,
              if (params != null) 'params': params,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final out = <Track>[];
      final seen = <String>{};
      _walk(jsonDecode(utf8.decode(res.bodyBytes)), (item) {
        final t = _parse(item);
        if (t != null && seen.add(t.mediaId)) out.add(t);
      });
      return out;
    } catch (e) {
      debugPrint('YT Music search failed: $e');
      return const [];
    }
  }

  void _walk(Object? node, void Function(Map<dynamic, dynamic>) onItem) {
    if (node is Map) {
      final r = node['musicResponsiveListItemRenderer'];
      if (r is Map) onItem(r);
      for (final v in node.values) {
        _walk(v, onItem);
      }
    } else if (node is List) {
      for (final v in node) {
        _walk(v, onItem);
      }
    }
  }

  static String _runs(Object? col) {
    final renderer = col is Map ? col['musicResponsiveListItemFlexColumnRenderer'] : null;
    final text = renderer is Map ? renderer['text'] : null;
    final runs = text is Map && text['runs'] is List ? text['runs'] as List : const [];
    return [for (final r in runs) if (r is Map) '${r['text']}'].join();
  }

  Track? _parse(Map<dynamic, dynamic> r) {
    final id = _videoId(r);
    if (id == null) return null;
    final cols = r['flexColumns'] is List ? r['flexColumns'] as List : const [];
    if (cols.length < 2) return null;
    final title = _runs(cols[0]);
    if (title.isEmpty) return null;
    final tokens = [for (final t in _runs(cols[1]).split('•')) t.trim()].where((e) => e.isNotEmpty).toList();
    if (tokens.isNotEmpty && const {'Song', 'Video'}.contains(tokens.first)) tokens.removeAt(0);
    if (tokens.isEmpty) return null;
    final durIdx = tokens.lastIndexWhere((e) => RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(e));
    var ms = 0;
    if (durIdx >= 0) {
      final parts = tokens[durIdx].split(':').map(int.parse).toList();
      ms = parts.fold<int>(0, (a, b) => a * 60 + b) * 1000;
      tokens.removeAt(durIdx);
    }
    if (ms == 0 || ms < 30000 || ms > 20 * 60 * 1000) return null;
    final artist = tokens.first;
    final album = tokens.length > 2 ? tokens[1] : '';
    return Track(
      mediaId: TrackKeys.youtube(id),
      title: title,
      artist: artist,
      album: album,
      durationMs: ms,
      artworkUri: _thumb(r) ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      uri: TrackKeys.youtube(id),
    );
  }

  String? _videoId(Map<dynamic, dynamic> r) {
    final data = r['playlistItemData'];
    if (data is Map && data['videoId'] != null) return '${data['videoId']}';
    final overlay = r['overlay'];
    try {
      final id = overlay['musicItemThumbnailOverlayRenderer']['content']['musicPlayButtonRenderer']['playNavigationEndpoint']['watchEndpoint']['videoId'];
      if (id != null) return '$id';
    } catch (_) {}
    return null;
  }

  String? _thumb(Map<dynamic, dynamic> r) {
    try {
      final list = r['thumbnail']['musicThumbnailRenderer']['thumbnail']['thumbnails'] as List;
      final url = '${(list.last as Map)['url']}';
      return url.replaceFirst(RegExp(r'=w\d+-h\d+.*$'), '=w544-h544-l90-rj');
    } catch (_) {
      return null;
    }
  }
}
