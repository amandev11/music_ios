import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';

/// YouTube Music's browse endpoints (the same WEB_REMIX client the search uses; no account or token):
/// top charts, the home shelves, and the track list of any playlist or album page.
class YtMusicBrowse {
  YtMusicBrowse({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  Future<Map<String, dynamic>?> _browse(Map<String, Object?> body) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _http
            .post(
              Uri.https('music.youtube.com', '/youtubei/v1/browse', {
                'prettyPrint': 'false',
              }),
              headers: const {
                'Content-Type': 'application/json',
                'Origin': 'https://music.youtube.com',
                'Referer': 'https://music.youtube.com/',
                'User-Agent': _ua,
              },
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB_REMIX',
                    'clientVersion': '1.20250210.01.00',
                    'hl': 'en',
                    'gl': body['_gl'] ?? 'IN',
                  },
                },
                ...body..remove('_gl'),
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200)
          return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('YT Music browse failed: $e');
      }
    }
    return null;
  }

  // ---- Public ------------------------------------------------------------------------------------

  /// Top charts (songs, trending, top artists, playlists) for [country] ('ZZ' = global).
  Future<List<HomeSection>> charts({
    String country = 'ZZ',
    String gl = 'IN',
  }) async {
    final r = await _browse({
      'browseId': 'FEmusic_charts',
      'formData': {
        'selectedValues': [country],
      },
      '_gl': gl,
    });
    return r == null ? const [] : _sections(r, chartMode: true);
  }

  /// The home shelves a signed-out visitor gets: quick picks, trending playlists, new albums, moods.
  Future<List<HomeSection>> home({String gl = 'IN'}) async {
    final r = await _browse({'browseId': 'FEmusic_home', '_gl': gl});
    return r == null ? const [] : _sections(r);
  }

  Future<List<HomeSection>> newReleases({String gl = 'IN'}) async {
    final r = await _browse({'browseId': 'FEmusic_new_releases', '_gl': gl});
    return r == null ? const [] : _sections(r);
  }

  /// Tracks of a playlist (`VL...`/`PL...`/`RDCLAK...`) or album (`MPRE...`) page.
  Future<CollectionPage?> collection(
    String id, {
    required ItemKind kind,
  }) async {
    final browseId =
        id.startsWith('MPRE') || id.startsWith('VL') || id.startsWith('OLAK')
        ? id
        : 'VL$id';
    final r = await _browse({'browseId': browseId});
    if (r == null) return null;
    final tracks = <Track>[];
    final seen = <String>{};
    final title = _firstTitle(r);
    final thumb = _bestThumb(
      _find(r, 'musicThumbnailRenderer') ??
          _find(r, 'croppedSquareThumbnailRenderer'),
    );
    final sub = _subtitleOf(r);
    _walkKey(r, 'musicResponsiveListItemRenderer', (item) {
      final t = _trackFromRow(item, fallbackArtist: sub, fallbackArt: thumb);
      if (t != null && seen.add(t.mediaId)) tracks.add(t);
    });
    if (tracks.isEmpty) return null;
    return CollectionPage(
      id: id,
      kind: kind,
      title: title,
      subtitle: sub,
      imageUrl: thumb,
      tracks: tracks,
    );
  }

  // ---- Parsing -----------------------------------------------------------------------------------

  List<HomeSection> _sections(
    Map<String, dynamic> root, {
    bool chartMode = false,
  }) {
    final out = <HomeSection>[];
    _walkKey(root, 'musicCarouselShelfRenderer', (shelf) {
      final title = _text(
        _dig(shelf, [
          'header',
          'musicCarouselShelfBasicHeaderRenderer',
          'title',
        ]),
      );
      final contents = shelf['contents'];
      if (title.isEmpty || contents is! List) return;
      final items = <CatalogItem>[];
      var songs = 0;
      for (final c in contents) {
        if (c is! Map) continue;
        final two = c['musicTwoRowItemRenderer'];
        final row = c['musicResponsiveListItemRenderer'];
        CatalogItem? it;
        if (two is Map) it = _twoRow(two);
        if (row is Map) {
          final t = _trackFromRow(row);
          if (t != null)
            it = CatalogItem(
              kind: ItemKind.song,
              id: t.mediaId,
              title: t.title,
              subtitle: t.artist,
              imageUrl: t.artworkUri,
              track: t,
            );
        }
        if (it == null) continue;
        if (it.kind == ItemKind.song) songs++;
        items.add(it);
      }
      if (items.length < 3) return;
      final allSongs = songs == items.length;
      final allArtists = items.every((e) => e.kind == ItemKind.artist);
      final style = allSongs
          ? (chartMode ? SectionStyle.chart : SectionStyle.songs)
          : allArtists
          ? SectionStyle.circle
          : SectionStyle.square;
      out.add(
        HomeSection(
          _prettify(title, chartMode),
          items,
          style: style,
          caption: 'YouTube Music',
        ),
      );
    });
    return out;
  }

  static String _prettify(String t, bool chart) =>
      chart &&
          !t.toLowerCase().contains('top') &&
          !t.toLowerCase().contains('trending')
      ? t
      : t;

  CatalogItem? _twoRow(Map<dynamic, dynamic> r) {
    final title = _text(r['title']);
    if (title.isEmpty) return null;
    final sub = _text(r['subtitle']);
    final img = _bestThumb(_find(r, 'musicThumbnailRenderer'));
    final nav = r['navigationEndpoint'];
    if (nav is! Map) return null;
    final watch = nav['watchEndpoint'];
    if (watch is Map && watch['videoId'] != null) {
      final id = '${watch['videoId']}';
      final parts = sub
          .split('•')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final artist = parts.length > 1
          ? parts[1]
          : (parts.isNotEmpty ? parts.first : '');
      final t = Track(
        mediaId: TrackKeys.youtube(id),
        title: title,
        artist: artist,
        artworkUri: img ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        uri: TrackKeys.youtube(id),
      );
      return CatalogItem(
        kind: ItemKind.song,
        id: t.mediaId,
        title: title,
        subtitle: artist,
        imageUrl: t.artworkUri,
        track: t,
      );
    }
    final browse = nav['browseEndpoint'];
    final bid = browse is Map ? '${browse['browseId']}' : '';
    if (bid.startsWith('VL'))
      return CatalogItem(
        kind: ItemKind.playlist,
        id: 'ytp:${bid.substring(2)}',
        title: title,
        subtitle: sub,
        imageUrl: img,
      );
    if (bid.startsWith('MPRE') || bid.startsWith('OLAK'))
      return CatalogItem(
        kind: ItemKind.album,
        id: 'yta:$bid',
        title: title,
        subtitle: sub.replaceFirst(RegExp(r'^(Album|Single|EP)\s*•\s*'), ''),
        imageUrl: img,
      );
    if (bid.startsWith('UC') || bid.startsWith('MPLA'))
      return CatalogItem(
        kind: ItemKind.artist,
        id: 'name:$title',
        title: title,
        subtitle: 'Artist',
        imageUrl: img,
      );
    final pl = nav['watchPlaylistEndpoint'];
    if (pl is Map && pl['playlistId'] != null)
      return CatalogItem(
        kind: ItemKind.playlist,
        id: 'ytp:${pl['playlistId']}',
        title: title,
        subtitle: sub,
        imageUrl: img,
      );
    return null;
  }

  Track? _trackFromRow(
    Map<dynamic, dynamic> r, {
    String fallbackArtist = '',
    String? fallbackArt,
  }) {
    final id = _videoId(r);
    if (id == null) return null;
    final cols = r['flexColumns'] is List ? r['flexColumns'] as List : const [];
    if (cols.isEmpty) return null;
    final title = _colText(cols[0]);
    if (title.isEmpty) return null;
    var artist = '';
    var album = '';
    if (cols.length > 1) {
      final parts = _colText(cols[1])
          .split('•')
          .map((e) => e.trim())
          .where(
            (e) =>
                e.isNotEmpty &&
                !RegExp(r'^\d+(\.\d+)?[KMB]? (views|plays)$').hasMatch(e) &&
                !const {'Song', 'Video'}.contains(e),
          )
          .toList();
      if (parts.isNotEmpty) artist = parts.first;
      if (parts.length > 2) album = parts[1];
    }
    if (cols.length > 2 && album.isEmpty) {
      final c = _colText(cols[2]);
      if (c.isNotEmpty && !RegExp(r'views|plays').hasMatch(c)) album = c;
    }
    if (artist.isEmpty) artist = fallbackArtist;
    var ms = 0;
    final fixed = r['fixedColumns'];
    if (fixed is List && fixed.isNotEmpty) {
      final d = _text(
        _dig(fixed.first, [
          'musicResponsiveListItemFixedColumnRenderer',
          'text',
        ]),
      );
      final m = RegExp(r'^(\d+):(\d{2})(?::(\d{2}))?$').firstMatch(d);
      if (m != null) {
        final a = int.parse(m.group(1)!),
            b = int.parse(m.group(2)!),
            c = m.group(3);
        ms = (c == null ? a * 60 + b : (a * 60 + b) * 60 + int.parse(c)) * 1000;
      }
    }
    if (ms > 0 && ms > 20 * 60 * 1000)
      return null; // hour-long mixes are not songs
    return Track(
      mediaId: TrackKeys.youtube(id),
      title: title,
      artist: artist,
      album: album,
      durationMs: ms,
      artworkUri:
          _bestThumb(_find(r, 'musicThumbnailRenderer')) ??
          fallbackArt ??
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      uri: TrackKeys.youtube(id),
    );
  }

  String? _videoId(Map<dynamic, dynamic> r) {
    final data = r['playlistItemData'];
    if (data is Map && data['videoId'] != null) return '${data['videoId']}';
    final id = _dig(r, [
      'overlay',
      'musicItemThumbnailOverlayRenderer',
      'content',
      'musicPlayButtonRenderer',
      'playNavigationEndpoint',
      'watchEndpoint',
      'videoId',
    ]);
    return id == null ? null : '$id';
  }

  static String _colText(Object? col) {
    final renderer = col is Map
        ? col['musicResponsiveListItemFlexColumnRenderer']
        : null;
    return _text(renderer is Map ? renderer['text'] : null);
  }

  static String _text(Object? node) {
    if (node is! Map) return '';
    final runs = node['runs'];
    if (runs is List)
      return [
        for (final r in runs)
          if (r is Map) '${r['text']}',
      ].join();
    return '${node['simpleText'] ?? ''}';
  }

  static Object? _dig(Object? node, List<String> path) {
    var cur = node;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  static String? _bestThumb(Object? renderer) {
    try {
      final list =
          _dig(renderer, ['thumbnail', 'thumbnails']) ??
          _dig(renderer, [
            'thumbnail',
            'musicThumbnailRenderer',
            'thumbnail',
            'thumbnails',
          ]);
      if (list is! List || list.isEmpty) return null;
      final url = '${(list.last as Map)['url']}';
      if (url.contains('lh3.googleusercontent.com') ||
          url.contains('yt3.ggpht.com'))
        return url.replaceFirst(RegExp(r'=w\d+-h\d+.*$'), '=w544-h544-l90-rj');
      return url;
    } catch (_) {
      return null;
    }
  }

  static Object? _find(Object? node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final f = _find(v, key);
        if (f != null) return f;
      }
    } else if (node is List) {
      for (final v in node) {
        final f = _find(v, key);
        if (f != null) return f;
      }
    }
    return null;
  }

  static void _walkKey(
    Object? node,
    String key,
    void Function(Map<dynamic, dynamic>) on,
  ) {
    if (node is Map) {
      final r = node[key];
      if (r is Map) on(r);
      for (final v in node.values) {
        _walkKey(v, key, on);
      }
    } else if (node is List) {
      for (final v in node) {
        _walkKey(v, key, on);
      }
    }
  }

  String _firstTitle(Map<String, dynamic> r) {
    for (final k in const [
      'musicResponsiveHeaderRenderer',
      'musicDetailHeaderRenderer',
      'musicImmersiveHeaderRenderer',
      'musicEditablePlaylistDetailHeaderRenderer',
    ]) {
      final h = _find(r, k);
      if (h is Map) {
        final t = _text(h['title']);
        if (t.isNotEmpty) return t;
      }
    }
    return '';
  }

  String _subtitleOf(Map<String, dynamic> r) {
    for (final k in const [
      'musicResponsiveHeaderRenderer',
      'musicDetailHeaderRenderer',
    ]) {
      final h = _find(r, k);
      if (h is Map) {
        final s = _text(h['straplineTextOne']).isNotEmpty
            ? _text(h['straplineTextOne'])
            : _text(h['subtitle']);
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }
}

// ---- Home-section cache (so the first paint after a restart is instant) -------------------------------

Map<String, Object?> sectionToJson(HomeSection s) => {
  't': s.title,
  's': s.style.index,
  'c': s.caption,
  'i': [
    for (final it in s.items)
      {
        'k': it.kind.index,
        'id': it.id,
        't': it.title,
        's': it.subtitle,
        'img': it.imageUrl,
        if (it.track != null) 'tr': it.track!.toMap(),
      },
  ],
};

HomeSection? sectionFromJson(Object? j) {
  try {
    final m = j as Map;
    final items = <CatalogItem>[
      for (final raw in (m['i'] as List))
        CatalogItem(
          kind: ItemKind.values[(raw as Map)['k'] as int],
          id: '${raw['id']}',
          title: '${raw['t']}',
          subtitle: '${raw['s'] ?? ''}',
          imageUrl: raw['img'] as String?,
          track: raw['tr'] is Map ? Track.fromMap(raw['tr'] as Map) : null,
        ),
    ];
    return HomeSection(
      '${m['t']}',
      items,
      style: SectionStyle.values[m['s'] as int],
      caption: '${m['c'] ?? ''}',
    );
  } catch (_) {
    return null;
  }
}
