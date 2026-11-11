import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/settings.dart';

class ReleaseGroup {
  const ReleaseGroup(this.id, this.title, this.type, this.year);
  final String id;
  final String title;

  /// 'Album', 'Single' or 'EP'.
  final String type;
  final int year;
}

class ArtistInfo {
  const ArtistInfo({this.bio = '', this.genres = const [], this.facts = '', this.mbid = '', this.releaseGroups = const []});
  final String bio;
  final List<String> genres;
  final String facts;
  final String mbid;

  /// Studio albums, EPs and singles credited to the artist on MusicBrainz.
  final List<ReleaseGroup> releaseGroups;
}

/// MusicBrainz (type, origin, formation year, genre tags and the Wikipedia link) plus the Wikipedia
/// summary for the biography. Both are open APIs; results are cached per artist name.
class ArtistInfoApi {
  ArtistInfoApi(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;
  final Map<String, Future<ArtistInfo>> _cache = {};

  static const _ua = {'User-Agent': 'MusicApp/1.0 (personal player)', 'Accept': 'application/json'};

  Future<ArtistInfo> lookup(String name) => _cache.putIfAbsent(name.toLowerCase(), () => _lookup(name));

  Future<dynamic> _json(Uri url) async {
    try {
      final res = await _http.get(_settings.proxied(url), headers: _ua).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  Future<ArtistInfo> _lookup(String name) async {
    var genres = <String>[];
    var facts = '';
    String? wikiTitle;
    var mbid = '';
    var groups = <ReleaseGroup>[];

    final search = await _json(Uri.https('musicbrainz.org', '/ws/2/artist/', {'query': 'artist:"$name"', 'fmt': 'json', 'limit': '3'}));
    final list = search is Map && search['artists'] is List ? search['artists'] as List : const [];
    Map? hit;
    for (final a in list) {
      if (a is Map && '${a['name']}'.toLowerCase() == name.toLowerCase()) {
        hit = a;
        break;
      }
    }
    hit ??= list.isNotEmpty && list.first is Map && (list.first['score'] ?? 0) >= 90 ? list.first as Map : null;

    if (hit != null) {
      final id = '${hit['id']}';
      mbid = id;
      await Future<void>.delayed(const Duration(milliseconds: 1100)); // MusicBrainz allows ~1 request/s
      final detail = await _json(Uri.https('musicbrainz.org', '/ws/2/artist/$id', {'inc': 'url-rels+genres', 'fmt': 'json'}));
      final d = detail is Map ? detail : hit;
      final tags = <Map>[
        for (final g in (d['genres'] is List ? d['genres'] as List : const [])) if (g is Map) g,
      ]..sort((a, b) => ((b['count'] ?? 0) as num).compareTo((a['count'] ?? 0) as num));
      genres = [for (final g in tags.take(5)) _title('${g['name']}')];
      final type = '${d['type'] ?? ''}';
      final area = d['area'] is Map ? '${d['area']['name']}' : '';
      final span = d['life-span'] is Map ? d['life-span'] as Map : const {};
      final begin = '${span['begin'] ?? ''}';
      facts = [
        if (type.isNotEmpty) type,
        if (area.isNotEmpty && area != 'null') area,
        if (begin.isNotEmpty && begin != 'null') (type == 'Person' ? 'Born ${begin.split('-').first}' : 'Since ${begin.split('-').first}'),
      ].join(' · ');
      for (final r in (d['relations'] is List ? d['relations'] as List : const [])) {
        if (r is Map && r['type'] == 'wikipedia' && r['url'] is Map) {
          final u = '${r['url']['resource']}';
          if (u.contains('en.wikipedia.org/wiki/')) wikiTitle = Uri.decodeComponent(u.split('/wiki/').last);
        }
      }
    }

    if (mbid.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      groups = await _releaseGroups(mbid);
    }

    var bio = await _wiki(wikiTitle ?? name);
    if (bio.isEmpty && wikiTitle == null) bio = await _wiki('$name (musician)');
    return ArtistInfo(bio: bio, genres: genres, facts: facts, mbid: mbid, releaseGroups: groups);
  }

  static const _skip = {'Live', 'Remix', 'DJ-mix', 'Demo', 'Interview', 'Spokenword', 'Audiobook', 'Audio drama', 'Mixtape/Street'};

  Future<List<ReleaseGroup>> _releaseGroups(String mbid) async {
    final r = await _json(Uri.https('musicbrainz.org', '/ws/2/release-group', {'artist': mbid, 'type': 'album|single|ep', 'limit': '100', 'fmt': 'json'}));
    final list = r is Map && r['release-groups'] is List ? r['release-groups'] as List : const [];
    final out = <ReleaseGroup>[];
    for (final g in list) {
      if (g is! Map) continue;
      final secondary = [for (final x in (g['secondary-types'] is List ? g['secondary-types'] as List : const [])) '$x'];
      if (secondary.any(_skip.contains)) continue;
      final type = '${g['primary-type'] ?? ''}';
      if (type != 'Album' && type != 'Single' && type != 'EP') continue;
      final date = '${g['first-release-date'] ?? ''}';
      out.add(ReleaseGroup('${g['id']}', '${g['title']}', type, date.length >= 4 ? int.tryParse(date.substring(0, 4)) ?? 0 : 0));
    }
    return out;
  }

  /// Tracks of the first release in a release group, for opening a MusicBrainz album.
  Future<({String title, String artist, int year, List<({String id, String title, int ms})> tracks})?> releaseTracks(String groupId) async {
    final r = await _json(Uri.https('musicbrainz.org', '/ws/2/release', {'release-group': groupId, 'inc': 'recordings+artist-credits', 'limit': '8', 'fmt': 'json'}));
    final releases = r is Map && r['releases'] is List ? r['releases'] as List : const [];
    Map? best;
    var bestCount = -1;
    for (final rel in releases) {
      if (rel is! Map) continue;
      var count = 0;
      for (final m in (rel['media'] is List ? rel['media'] as List : const [])) {
        if (m is Map && m['tracks'] is List) count += (m['tracks'] as List).length;
      }
      if (count > bestCount) {
        best = rel;
        bestCount = count;
      }
    }
    if (best == null || bestCount <= 0) return null;
    final tracks = <({String id, String title, int ms})>[];
    for (final m in (best['media'] as List)) {
      if (m is! Map) continue;
      for (final t in (m['tracks'] as List? ?? const [])) {
        if (t is! Map) continue;
        final rec = t['recording'] is Map ? t['recording'] as Map : const {};
        tracks.add((id: '${rec['id'] ?? t['id']}', title: '${t['title']}', ms: (t['length'] as num?)?.toInt() ?? 0));
      }
    }
    final credit = best['artist-credit'] is List ? (best['artist-credit'] as List).whereType<Map>().map((e) => '${e['name']}${e['joinphrase'] ?? ''}').join() : '';
    final date = '${best['date'] ?? ''}';
    return (title: '${best['title']}', artist: credit, year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) ?? 0 : 0, tracks: tracks);
  }

  Future<String> _wiki(String title) async {
    final r = await _json(Uri.https('en.wikipedia.org', '/api/rest_v1/page/summary/${Uri.encodeComponent(title.replaceAll(' ', '_'))}'));
    if (r is! Map || r['type'] == 'disambiguation') return '';
    return '${r['extract'] ?? ''}'.trim();
  }

  static String _title(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
