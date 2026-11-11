import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/settings.dart';

String _s(Object? v) => v == null ? '' : '$v';
Map<dynamic, dynamic>? _m(Object? v) => v is Map ? v : null;
List<dynamic> _l(Object? v) => v is List ? v : const [];

/// Deezer's public catalogue API: keyless, fast and worldwide. It gives real artist portraits, fan counts,
/// top tracks, discographies and related artists. Deezer only streams 30 s previews, so its tracks are
/// metadata: `dz:` ids are resolved to a full stream on JioSaavn or YouTube by title/artist/duration.
class DeezerApi {
  DeezerApi(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;

  static const _base = 'https://api.deezer.com';

  /// One automatic retry: a single dropped request used to leave an artist page empty.
  Future<Map<dynamic, dynamic>?> _get(String path, [Map<String, String> q = const {}]) async =>
      await _getOnce(path, q) ?? await _getOnce(path, q);

  Future<Map<dynamic, dynamic>?> _getOnce(String path, Map<String, String> q) async {
    try {
      final url = Uri.parse('$_base$path').replace(queryParameters: q.isEmpty ? null : q);
      final res = await _http.get(_settings.proxied(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is Map && j['error'] != null) return null;
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }

  static String? _pic(Map<dynamic, dynamic>? m, [List<String> keys = const ['picture_xl', 'picture_big', 'cover_xl', 'cover_big', 'picture_medium', 'cover_medium']]) {
    if (m == null) return null;
    for (final k in keys) {
      final v = _s(m[k]);
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  Track? track(Map<dynamic, dynamic> m, {String? albumTitle, String? albumCover}) {
    final id = _s(m['id']);
    final title = _s(m['title_short']).isNotEmpty && _s(m['title']).length > 60 ? _s(m['title_short']) : _s(m['title']);
    if (id.isEmpty || title.isEmpty) return null;
    final names = <String>[
      for (final c in _l(m['contributors']))
        if (c is Map && _s(c['name']).isNotEmpty) _s(c['name'])
    ];
    final artist = names.isNotEmpty ? names.join(', ') : _s(_m(m['artist'])?['name']);
    final album = _m(m['album']);
    final key = TrackKeys.meta(id);
    return Track(
      mediaId: key,
      title: title,
      artist: artist.isEmpty ? 'Unknown Artist' : artist,
      album: albumTitle ?? _s(album?['title']),
      durationMs: (int.tryParse(_s(m['duration'])) ?? 0) * 1000,
      uri: key,
      artworkUri: albumCover ?? _pic(album),
    );
  }

  CatalogItem? _artistItem(Object? e) {
    final m = _m(e);
    if (m == null || _s(m['id']).isEmpty) return null;
    return CatalogItem(kind: ItemKind.artist, id: 'dz:${_s(m['id'])}', title: _s(m['name']), subtitle: 'Artist', imageUrl: _pic(m));
  }

  CatalogItem? _albumItem(Object? e) {
    final m = _m(e);
    if (m == null || _s(m['id']).isEmpty) return null;
    final type = _s(m['record_type']);
    final date = _s(m['release_date']);
    final year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) ?? 0 : 0;
    final who = _s(_m(m['artist'])?['name']);
    return CatalogItem(
      kind: ItemKind.album,
      id: 'dz:${_s(m['id'])}',
      title: _s(m['title']),
      subtitle: [if (type.isNotEmpty) '${type[0].toUpperCase()}${type.substring(1)}', if (who.isNotEmpty) who].join(' • '),
      imageUrl: _pic(m),
      year: year,
    );
  }

  CatalogItem? _playlistItem(Object? e) {
    final m = _m(e);
    if (m == null || _s(m['id']).isEmpty) return null;
    final owner = _s(_m(m['user'])?['name']);
    return CatalogItem(
      kind: ItemKind.playlist,
      id: 'dz:${_s(m['id'])}',
      title: _s(m['title']),
      subtitle: owner.isEmpty ? 'Playlist' : 'Playlist • $owner',
      imageUrl: _pic(m, const ['picture_xl', 'picture_big', 'picture_medium']),
    );
  }

  // ---- Browse -----------------------------------------------------------------------------------

  Future<List<HomeSection>> charts() async {
    final c = await _get('/chart/0', {'limit': '20'});
    if (c == null) return const [];
    List<CatalogItem> pick(String key, CatalogItem? Function(Object?) f) =>
        [for (final e in _l(_m(c[key])?['data'])) f(e)].whereType<CatalogItem>().toList();
    final songs = <CatalogItem>[
      for (final e in _l(_m(c['tracks'])?['data']))
        if (e is Map)
          if (track(e) case final t?)
            CatalogItem(kind: ItemKind.song, id: t.mediaId, title: t.title, subtitle: t.artist, imageUrl: t.artworkUri, track: t)
    ];
    final out = <HomeSection>[];
    final artists = pick('artists', _artistItem);
    final albums = pick('albums', _albumItem);
    final lists = pick('playlists', _playlistItem);
    if (songs.isNotEmpty) out.add(HomeSection('Top songs worldwide', songs, style: SectionStyle.songs));
    if (artists.isNotEmpty) out.add(HomeSection('Popular artists', artists, style: SectionStyle.circle));
    if (albums.isNotEmpty) out.add(HomeSection('Top albums', albums));
    if (lists.isNotEmpty) out.add(HomeSection('Trending playlists', lists));
    return out;
  }

  Future<List<CatalogItem>> searchArtists(String q, {int limit = 8}) async {
    final r = await _get('/search/artist', {'q': q, 'limit': '$limit'});
    return [for (final e in _l(r?['data'])) _artistItem(e)].whereType<CatalogItem>().toList();
  }

  Future<List<CatalogItem>> searchAlbums(String q, {int limit = 8}) async {
    final r = await _get('/search/album', {'q': q, 'limit': '$limit'});
    return [for (final e in _l(r?['data'])) _albumItem(e)].whereType<CatalogItem>().toList();
  }

  Future<List<CatalogItem>> searchPlaylists(String q, {int limit = 8}) async {
    final r = await _get('/search/playlist', {'q': q, 'limit': '$limit'});
    return [for (final e in _l(r?['data'])) _playlistItem(e)].whereType<CatalogItem>().toList();
  }

  // ---- Detail -----------------------------------------------------------------------------------

  Future<ArtistPage?> artist(String rawId) async {
    final results = await Future.wait<Map<dynamic, dynamic>?>([
      _get('/artist/$rawId'),
      _get('/artist/$rawId/top', {'limit': '50'}),
      _get('/artist/$rawId/albums', {'limit': '100'}),
      _get('/artist/$rawId/related', {'limit': '20'}),
      _get('/artist/$rawId/playlists', {'limit': '20'}),
    ]);
    final a = results[0];
    if (a == null || _s(a['name']).isEmpty) return null;
    final albums = <CatalogItem>[];
    final singles = <CatalogItem>[];
    final seen = <String>{};
    for (final e in _l(results[2]?['data'])) {
      final it = _albumItem(e);
      if (it == null || !seen.add(it.title.toLowerCase())) continue;
      final type = _s(_m(e)?['record_type']);
      (type == 'album' || type == 'compile' ? albums : singles).add(it);
    }
    int byYear(CatalogItem x, CatalogItem y) => y.year.compareTo(x.year);
    albums.sort(byYear);
    singles.sort(byYear);
    final fans = int.tryParse(_s(a['nb_fan'])) ?? 0;
    return ArtistPage(
      id: 'dz:$rawId',
      name: _s(a['name']),
      imageUrl: _pic(a),
      followers: fans > 0 ? '${_compact(fans)} fans' : '',
      topSongs: [for (final e in _l(results[1]?['data'])) if (e is Map) track(e)].whereType<Track>().toList(),
      albums: albums,
      singles: singles,
      similar: [for (final e in _l(results[3]?['data'])) _artistItem(e)].whereType<CatalogItem>().toList(),
      playlists: [for (final e in _l(results[4]?['data'])) _playlistItem(e)].whereType<CatalogItem>().toList(),
    );
  }

  Future<CollectionPage?> album(String rawId) async {
    final a = await _get('/album/$rawId');
    if (a == null) return null;
    final title = _s(a['title']);
    final cover = _pic(a);
    final artist = _s(_m(a['artist'])?['name']);
    final tracks = <Track>[];
    for (final e in _l(_m(a['tracks'])?['data'])) {
      if (e is! Map) continue;
      final t = track(e, albumTitle: title, albumCover: cover);
      if (t != null) tracks.add(t);
    }
    final date = _s(a['release_date']);
    return CollectionPage(
      id: 'dz:$rawId',
      kind: ItemKind.album,
      title: title,
      subtitle: artist,
      imageUrl: cover,
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) ?? 0 : 0,
      description: [if (_s(a['label']).isNotEmpty) _s(a['label']), if (_s(a['genres']).isNotEmpty) ''].where((e) => e.isNotEmpty).join(' · '),
      tracks: tracks,
    );
  }

  Future<CollectionPage?> playlist(String rawId) async {
    final p = await _get('/playlist/$rawId');
    if (p == null) return null;
    final more = await _get('/playlist/$rawId/tracks', {'limit': '150'});
    final src = _l((more ?? _m(p['tracks']))?['data']);
    return CollectionPage(
      id: 'dz:$rawId',
      kind: ItemKind.playlist,
      title: _s(p['title']),
      subtitle: _s(_m(p['creator'])?['name']),
      imageUrl: _pic(p, const ['picture_xl', 'picture_big', 'picture_medium']),
      description: _s(p['description']),
      tracks: [for (final e in src) if (e is Map) track(e)].whereType<Track>().toList(),
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}
