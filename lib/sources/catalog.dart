import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/settings.dart';
import '../core/recommender.dart';
import 'artist_info.dart';
import 'deezer.dart';
import 'registry.dart';
import 'source.dart';

String _s(Object? v) => v == null ? '' : '$v';
Map<dynamic, dynamic>? _m(Object? v) => v is Map ? v : null;
List<dynamic> _l(Object? v) => v is List ? v : const [];

String? _img(Object? v) {
  final u = _s(v);
  if (u.isEmpty) return null;
  return u.replaceAll(RegExp(r'\d{2,3}x\d{2,3}'), '500x500').replaceFirst('http://', 'https://');
}

String _streamUri(String key) => Uri(scheme: 'aurora', host: 'stream', queryParameters: {'k': key}).toString();

/// A song row from any JioSaavn response (search, album, playlist, artist pages differ slightly).
Track? saavnSong(Map<dynamic, dynamic> s) {
  final id = _s(s['id']);
  if (id.isEmpty) return null;
  final info = _m(s['more_info']) ?? const {};
  final title = decodeEntities(_s(s['title']).isNotEmpty ? _s(s['title']) : _s(s['song']));
  if (title.isEmpty) return null;

  final primary = _l(_m(info['artistMap'])?['primary_artists'])
      .whereType<Map>()
      .map((a) => _s(a['name']))
      .where((n) => n.isNotEmpty)
      .toList();
  var artist = primary.join(', ');
  if (artist.isEmpty) artist = _s(s['primary_artists']);
  if (artist.isEmpty) artist = _s(info['primary_artists']);
  if (artist.isEmpty) artist = _s(s['subtitle']).split(' - ').first;

  final durRaw = info['duration'] ?? s['duration'];
  final duration = int.tryParse(_s(durRaw)) ?? 0;
  final key = TrackKeys.saavn(id);
  return Track(
    mediaId: key,
    title: title,
    artist: artist.isEmpty ? 'Unknown Artist' : decodeEntities(artist),
    album: decodeEntities(_s(info['album']).isNotEmpty ? _s(info['album']) : _s(s['album'])),
    albumId: id.hashCode,
    durationMs: duration * 1000,
    year: int.tryParse(_s(s['year'])) ?? 0,
    uri: _streamUri(key),
    artworkUri: _img(s['image']),
    mimeType: 'audio/mp4',
  );
}

/// Browse data (home, artists, albums, playlists, search) from the JioSaavn web API.
class Catalog {
  Catalog(this._settings, {http.Client? client})
      : _http = client ?? http.Client(),
        deezer = DeezerApi(_settings),
        info = ArtistInfoApi(_settings);

  final DeezerApi deezer;
  final ArtistInfoApi info;

  final Settings _settings;
  final http.Client _http;
  Future<List<HomeSection>>? _homeFuture;

  static const _base = 'https://www.jiosaavn.com/api.php';

  Future<dynamic> _call(String method, Map<String, String> params) async {
    try {
      final url = Uri.parse(_base).replace(queryParameters: {
        '__call': method,
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        ...params,
      });
      final res = await _http.get(_settings.proxied(url), headers: const {
        'Accept': 'application/json',
        'Accept-Language': 'en-IN,en;q=0.9',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  // ---- Home ------------------------------------------------------------------------------------

  Future<List<HomeSection>> home({bool refresh = false}) {
    if (refresh) _homeFuture = null;
    return _homeFuture ??= _loadHome();
  }

  CatalogItem? _item(Map<dynamic, dynamic> m) {
    final type = _s(m['type']).toLowerCase();
    final id = _s(m['id']);
    final title = decodeEntities(_s(m['title']).isNotEmpty ? _s(m['title']) : _s(m['name']));
    if (id.isEmpty || title.isEmpty) return null;
    final info = _m(m['more_info']) ?? const {};
    final year = int.tryParse(_s(m['year']).isNotEmpty ? _s(m['year']) : _s(info['year'])) ?? 0;
    final subtitle = decodeEntities(_s(m['subtitle']).isNotEmpty ? _s(m['subtitle']) : _s(m['description']));
    switch (type) {
      case 'song':
        final t = saavnSong(m);
        return t == null
            ? null
            : CatalogItem(kind: ItemKind.song, id: id, title: title, subtitle: t.artist, imageUrl: t.artworkUri, track: t);
      case 'album':
        return CatalogItem(kind: ItemKind.album, id: id, title: title, subtitle: subtitle, imageUrl: _img(m['image']), year: year);
      case 'playlist':
        return CatalogItem(kind: ItemKind.playlist, id: id, title: title, subtitle: subtitle, imageUrl: _img(m['image']));
      case 'artist':
        return CatalogItem(kind: ItemKind.artist, id: id, title: title, subtitle: 'Artist', imageUrl: _img(m['image']));
      default:
        return null; // radio stations, shows, channels: not playable here
    }
  }

  Future<List<HomeSection>> _loadHome() async {
    final both = await Future.wait<List<HomeSection>>([_loadSaavnHome(), deezer.charts()]);
    return [...both[0], ...both[1]];
  }

  Future<List<HomeSection>> _loadSaavnHome() async {
    final root = await _call('webapi.getLaunchData', {});
    if (root is! Map) return const [];
    final modules = _m(root['modules']) ?? const {};
    final keys = root.keys.where((k) => root[k] is List && _l(root[k]).isNotEmpty).map((k) => '$k').toList();
    keys.sort((a, b) {
      int pos(String k) => int.tryParse(_s(_m(modules[k])?['position'])) ?? 999;
      return pos(a).compareTo(pos(b));
    });

    final sections = <HomeSection>[];
    for (final key in keys) {
      if (key.startsWith('promo') || key == 'greeting') continue;
      final items = [for (final e in _l(root[key])) if (e is Map) _item(e)].whereType<CatalogItem>().toList();
      if (items.isEmpty) continue;
      var title = _s(_m(modules[key])?['title']);
      if (title.isEmpty) title = _pretty(key);
      final songCount = items.where((i) => i.kind == ItemKind.song).length;
      final artistCount = items.where((i) => i.kind == ItemKind.artist).length;
      final style = key == 'charts'
          ? SectionStyle.chart
          : songCount * 2 > items.length
              ? SectionStyle.songs
              : artistCount * 2 > items.length
                  ? SectionStyle.circle
                  : SectionStyle.square;
      sections.add(HomeSection(title, items, style: style));
    }

    // "Top Picks": the first mixed shelf rendered as large cards, like the real app's hero row.
    final heroIndex = sections.indexWhere((s) => s.style == SectionStyle.square && s.items.length >= 3);
    if (heroIndex >= 0) {
      final hero = sections.removeAt(heroIndex);
      sections.insert(0, HomeSection('Top Picks', hero.items.take(10).toList(), style: SectionStyle.wide, caption: hero.title));
    }

    // A songs shelf even when the launch data has none: take the first chart's tracks.
    if (!sections.any((s) => s.style == SectionStyle.songs)) {
      final chart = sections.where((s) => s.style == SectionStyle.chart).firstOrNull;
      final first = chart?.items.firstOrNull;
      if (first != null) {
        final page = await playlist(first.id);
        if (page != null && page.tracks.isNotEmpty) {
          sections.add(HomeSection(
            first.title,
            [
              for (final t in page.tracks.take(16))
                CatalogItem(kind: ItemKind.song, id: t.mediaId, title: t.title, subtitle: t.artist, imageUrl: t.artworkUri, track: t)
            ],
            style: SectionStyle.songs,
          ));
        }
      }
    }
    return sections;
  }

  String _pretty(String key) => key.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  // ---- Detail pages ----------------------------------------------------------------------------

  Future<CollectionPage?> album(String id) async {
    if (id.startsWith('dz:')) return deezer.album(id.substring(3));
    if (id.startsWith('mb:')) return _mbAlbum(id.substring(3));
    final d = await _call('content.getAlbumDetails', {'albumid': id});
    final m = d is Map && d['list'] != null ? d : await _call('album.getDetails', {'albumid': id});
    return _collection(m, id, ItemKind.album);
  }

  Future<CollectionPage?> playlist(String id) async {
    if (id.startsWith('dz:')) return deezer.playlist(id.substring(3));
    final d = await _call('playlist.getDetails', {'listid': id, 'n': '100', 'p': '1'});
    return _collection(d, id, ItemKind.playlist);
  }

  CollectionPage? _collection(Object? d, String id, ItemKind kind) {
    if (d is! Map) return null;
    final tracks = [for (final s in _l(d['list'])) if (s is Map) saavnSong(s)].whereType<Track>().toList();
    final title = decodeEntities(_s(d['title']).isNotEmpty ? _s(d['title']) : _s(d['name']));
    if (title.isEmpty && tracks.isEmpty) return null;
    final subtitle = decodeEntities(_s(d['subtitle']).isNotEmpty ? _s(d['subtitle']) : (tracks.isNotEmpty ? tracks.first.artist : ''));
    return CollectionPage(
      id: id,
      kind: kind,
      title: title,
      subtitle: subtitle,
      imageUrl: _img(d['image']),
      description: decodeEntities(_s(d['header_desc']).isNotEmpty ? _s(d['header_desc']) : _s(d['description'])),
      year: int.tryParse(_s(d['year'])) ?? 0,
      tracks: tracks,
    );
  }

  List<Track>? _forYou;
  int _forYouAt = 0;

  /// Songs picked from the listener's taste: top tracks of favourite artists plus a share from
  /// artists related to them (discovery), ranked and varied by [Recommender].
  Future<List<Track>> forYou({bool refresh = false}) async {
    final rec = Recommender(_settings);
    final stale = DateTime.now().millisecondsSinceEpoch - _forYouAt > 10 * 60 * 1000;
    if (!refresh && !stale && _forYou != null) return _forYou!;
    final seeds = rec.topArtists(n: 5);
    if (seeds.isEmpty) return const [];
    final pool = <Track>[];
    final seen = <String>{};
    Future<void> take(String name, {int limit = 8}) async {
      final hits = await deezer.searchArtists(name, limit: 1);
      if (hits.isEmpty) return;
      final page = await deezer.artist(hits.first.id.substring(3));
      if (page == null) return;
      for (final t in page.topSongs.take(limit)) {
        if (seen.add(TrackMatch.normalize('${t.title} ${t.artist}'))) pool.add(t);
      }
      if (limit >= 8) {
        // Discovery: a couple of tracks from each of the first related artists.
        for (final r in page.similar.take(2)) {
          final rp = await deezer.artist(r.id.substring(3));
          if (rp == null) continue;
          for (final t in rp.topSongs.take(3)) {
            if (seen.add(TrackMatch.normalize('${t.title} ${t.artist}'))) pool.add(t);
          }
        }
      }
    }
    await Future.wait([for (final s in seeds.take(4)) take(s)]);
    final liked = {for (final m in rec.likedTracks()) '${m['mediaId']}'};
    pool.removeWhere((t) => liked.contains(t.mediaId));
    _forYou = rec.rank(pool).take(30).toList();
    _forYouAt = DateTime.now().millisecondsSinceEpoch;
    return _forYou!;
  }

  static String _coverUrl(String groupId) => 'https://coverartarchive.org/release-group/$groupId/front-500';

  Future<CollectionPage?> _mbAlbum(String groupId) async {
    final r = await info.releaseTracks(groupId);
    if (r == null) return null;
    final cover = _coverUrl(groupId);
    return CollectionPage(
      id: 'mb:$groupId',
      kind: ItemKind.album,
      title: r.title,
      subtitle: r.artist,
      imageUrl: cover,
      year: r.year,
      tracks: [
        for (final t in r.tracks)
          Track(mediaId: 'mb:${t.id}', title: t.title, artist: r.artist, album: r.title, durationMs: t.ms, uri: 'mb:${t.id}', artworkUri: cover),
      ],
    );
  }

  /// Artist page in two steps so it appears at once: first Deezer (portrait, fans, top songs, albums,
  /// related artists), then the same page enriched with MusicBrainz (genres, facts, every studio release,
  /// including ones Deezer lacks) and the Wikipedia biography. JioSaavn ids open the JioSaavn page,
  /// completed from Deezer when its discography is empty.
  Stream<ArtistPage?> artistStream(String id, {String name = ''}) async* {
    ArtistPage? base;
    try {
      base = await _artistById(id, name);
    } catch (_) {}
    // The id's own source failed (offline, blocked, rate limited): find the artist again by name.
    if (base == null && name.isNotEmpty) {
      try {
        final hits = await deezer.searchArtists(name, limit: 3);
        final match = hits.where((h) => TrackMatch.normalize(h.title) == TrackMatch.normalize(name)).firstOrNull ?? hits.firstOrNull;
        if (match != null && match.id != id) base = await deezer.artist(match.id.substring(3));
      } catch (_) {}
    }
    if (base == null && name.isNotEmpty) base = ArtistPage(id: id, name: name);
    if (base == null) return;
    base = await _ensureTopSongs(base);
    yield base;
    try {
      final extra = await info.lookup(base.name);
      yield _enrich(base, extra);
    } catch (_) {}
  }

  Future<ArtistPage?> _artistById(String id, String name) async {
    if (id.startsWith('dz:')) return deezer.artist(id.substring(3));
    var base = await _saavnArtist(id);
    final nm = base?.name ?? name;
    if (base != null && (base.albums.isEmpty || base.topSongs.isEmpty) && nm.isNotEmpty) {
      final hits = await deezer.searchArtists(nm, limit: 3);
      final match = hits.where((h) => TrackMatch.normalize(h.title) == TrackMatch.normalize(nm)).firstOrNull;
      final dz = match == null ? null : await deezer.artist(match.id.substring(3));
      if (dz != null) base = _combine(base, dz);
    }
    return base;
  }

  /// Plays-anywhere song search used when no catalogue returned this artist's top songs.
  Future<List<Track>> Function(String query)? songSearch;

  Future<ArtistPage> _ensureTopSongs(ArtistPage p) async {
    if (p.topSongs.isNotEmpty || songSearch == null) return p;
    try {
      final key = TrackMatch.normalize(p.name);
      final found = (await songSearch!(p.name)).where((t) => key.isNotEmpty && TrackMatch.normalize(t.artist).contains(key)).take(20).toList();
      if (found.isEmpty) return p;
      return ArtistPage(
        id: p.id,
        name: p.name,
        imageUrl: p.imageUrl,
        bio: p.bio,
        followers: p.followers,
        topSongs: found,
        albums: p.albums,
        singles: p.singles,
        similar: p.similar,
        playlists: p.playlists,
        genres: p.genres,
        facts: p.facts,
      );
    } catch (_) {
      return p;
    }
  }

  ArtistPage _combine(ArtistPage a, ArtistPage dz) => ArtistPage(
        id: a.id,
        name: a.name,
        imageUrl: a.imageUrl ?? dz.imageUrl,
        bio: a.bio,
        followers: a.followers.isNotEmpty ? a.followers : dz.followers,
        topSongs: a.topSongs.isNotEmpty ? a.topSongs : dz.topSongs,
        albums: a.albums.isNotEmpty ? a.albums : dz.albums,
        singles: a.singles.isNotEmpty ? a.singles : dz.singles,
        similar: a.similar.isNotEmpty ? a.similar : dz.similar,
        playlists: dz.playlists,
      );

  ArtistPage _enrich(ArtistPage p, ArtistInfo x) {
    final have = {for (final i in [...p.albums, ...p.singles]) TrackMatch.normalize(i.title)};
    final albums = [...p.albums];
    final singles = [...p.singles];
    for (final g in x.releaseGroups) {
      if (!have.add(TrackMatch.normalize(g.title))) continue;
      final item = CatalogItem(
        kind: ItemKind.album,
        id: 'mb:${g.id}',
        title: g.title,
        subtitle: g.type,
        imageUrl: _coverUrl(g.id),
        year: g.year,
      );
      (g.type == 'Album' ? albums : singles).add(item);
    }
    int byYear(CatalogItem a, CatalogItem b) => b.year.compareTo(a.year);
    albums.sort(byYear);
    singles.sort(byYear);
    return ArtistPage(
      id: p.id,
      name: p.name,
      imageUrl: p.imageUrl,
      bio: x.bio.isNotEmpty ? x.bio : p.bio,
      followers: p.followers,
      topSongs: p.topSongs,
      albums: albums,
      singles: singles,
      similar: p.similar,
      playlists: p.playlists,
      genres: x.genres,
      facts: x.facts,
    );
  }

  Future<ArtistPage?> artist(String id) async {
    ArtistPage? last;
    await for (final p in artistStream(id)) {
      last = p;
    }
    return last;
  }

  Future<ArtistPage?> _saavnArtist(String id) async {
    final d = await _call('artist.getArtistPageDetails', {
      'artistId': id,
      'n_song': '20',
      'n_album': '20',
      'page': '0',
      'category': '',
      'sort_order': '',
    });
    if (d is! Map) return null;
    final name = decodeEntities(_s(d['name']).isNotEmpty ? _s(d['name']) : _s(d['title']));
    if (name.isEmpty) return null;

    List<CatalogItem> albums(Object? list, ItemKind kind) => [
          for (final e in _l(list))
            if (e is Map && _s(e['id']).isNotEmpty)
              CatalogItem(
                kind: kind,
                id: _s(e['id']),
                title: decodeEntities(_s(e['title']).isNotEmpty ? _s(e['title']) : _s(e['name'])),
                subtitle: decodeEntities(_s(e['subtitle'])),
                imageUrl: _img(e['image']),
                year: int.tryParse(_s(e['year']).isNotEmpty ? _s(e['year']) : _s(_m(e['more_info'])?['year'])) ?? 0,
              )
        ];

    var bio = '';
    final rawBio = d['bio'];
    if (rawBio is String && rawBio.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawBio);
        if (parsed is List) bio = parsed.whereType<Map>().map((e) => _s(e['text'])).where((t) => t.isNotEmpty).join('\n\n');
      } catch (_) {
        bio = rawBio;
      }
    } else if (rawBio is List) {
      bio = rawBio.whereType<Map>().map((e) => _s(e['text'])).where((t) => t.isNotEmpty).join('\n\n');
    }

    return ArtistPage(
      id: id,
      name: name,
      imageUrl: _img(d['image']),
      bio: decodeEntities(bio.replaceAll(RegExp(r'<[^>]*>'), '')),
      followers: _s(d['follower_count']),
      topSongs: [for (final s in _l(d['topSongs'])) if (s is Map) saavnSong(s)].whereType<Track>().toList(),
      albums: albums(d['topAlbums'], ItemKind.album),
      singles: albums(d['singles'], ItemKind.album),
      similar: [
        for (final e in _l(d['similarArtists']))
          if (e is Map && _s(e['id']).isNotEmpty)
            CatalogItem(
              kind: ItemKind.artist,
              id: _s(e['id']),
              title: decodeEntities(_s(e['name']).isNotEmpty ? _s(e['name']) : _s(e['title'])),
              subtitle: 'Artist',
              imageUrl: _img(e['image']),
            )
      ],
    );
  }

  // ---- Search ----------------------------------------------------------------------------------

  /// Artists, albums and playlists. Songs come from the playback sources, so they are not duplicated here.
  Future<SearchBundle> search(String query) async {
    final parts = await Future.wait<Object?>([
      _call('autocomplete.get', {'query': query}),
      deezer.searchArtists(query),
      deezer.searchAlbums(query),
      deezer.searchPlaylists(query),
    ]);
    final d = parts[0];
    final dzArtists = parts[1] as List<CatalogItem>;
    final dzAlbums = parts[2] as List<CatalogItem>;
    final dzLists = parts[3] as List<CatalogItem>;
    if (d is! Map) {
      return SearchBundle(
        topArtist: _topArtist(dzArtists, query),
        artists: dzArtists.where((a) => a != _topArtist(dzArtists, query)).toList(),
        albums: dzAlbums,
        playlists: dzLists,
      );
    }

    List<CatalogItem> pick(String key, ItemKind kind) => [
          for (final e in _l(_m(d[key])?['data']))
            if (e is Map && _s(e['id']).isNotEmpty)
              CatalogItem(
                kind: kind,
                id: _s(e['id']),
                title: decodeEntities(_s(e['title']).isNotEmpty ? _s(e['title']) : _s(e['name'])),
                subtitle: decodeEntities(_s(e['description']).isNotEmpty ? _s(e['description']) : _s(e['subtitle'])),
                imageUrl: _img(e['image']),
              )
        ];

    final saavnArtists = pick('artists', ItemKind.artist);
    final top = _topArtist(dzArtists, query) ?? _topArtist(saavnArtists, query);
    final rest = [...dzArtists, ...saavnArtists].where((a) => a != top && !_sameName(a, top)).toList();
    return SearchBundle(
      topArtist: top,
      artists: rest,
      albums: [...dzAlbums.take(4), ...pick('albums', ItemKind.album)],
      playlists: [...dzLists.take(4), ...pick('playlists', ItemKind.playlist)],
    );
  }

  bool _sameName(CatalogItem a, CatalogItem? b) => b != null && TrackMatch.normalize(a.title) == TrackMatch.normalize(b.title);

  CatalogItem? _topArtist(List<CatalogItem> artists, String query) {
    final q = TrackMatch.normalize(query);
    for (final a in artists) {
      final n = TrackMatch.normalize(a.title);
      if (n.isEmpty) continue;
      if (n == q || n.contains(q) || q.contains(n)) return a;
    }
    return null;
  }
}
