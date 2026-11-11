import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show YoutubeExplode, PlaylistId;

import '../core/models.dart';
import '../core/settings.dart';
import 'deezer.dart';
import 'registry.dart';

class ImportItem {
  const ImportItem(this.title, this.artist);
  final String title;
  final String artist;
}

class ImportedPlaylist {
  const ImportedPlaylist(this.name, this.items, {this.ready = const []});
  final String name;
  final List<ImportItem> items;

  /// Tracks that are already complete (Deezer links) and need no matching.
  final List<Track> ready;
}

/// Reads another service's playlist without an account or API key: the public Spotify embed page, the
/// Apple Music playlist page, YouTube / YouTube Music playlists, Deezer playlists, or any pasted list or
/// CSV export (Exportify, TuneMyMusic, Soundiiz...). Browsers need the CORS proxy from Settings.
class PlaylistImporter {
  PlaylistImporter(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;

  static const _ua = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Future<String?> _page(Uri u) async {
    try {
      final r = await _http.get(_settings.proxied(u), headers: _ua).timeout(const Duration(seconds: 15));
      return r.statusCode == 200 ? utf8.decode(r.bodyBytes) : null;
    } catch (_) {
      return null;
    }
  }

  /// Returns null when the link is not recognised or nothing could be read.
  Future<ImportedPlaylist?> fromUrl(String raw) async {
    final url = raw.trim();
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return null;
    final host = u.host.toLowerCase();
    if (host.contains('spotify.com')) return _spotify(u);
    if (host.contains('music.apple.com')) return _apple(u);
    if (host.contains('deezer.com')) return _deezer(u);
    if (host.contains('youtube.com') || host.contains('youtu.be')) return _youtube(u);
    return null;
  }

  // ---- Spotify ----------------------------------------------------------------------------------

  Future<ImportedPlaylist?> _spotify(Uri u) async {
    final segs = u.pathSegments.where((s) => s.isNotEmpty && !s.startsWith('intl-')).toList();
    final i = segs.indexWhere((s) => s == 'playlist' || s == 'album');
    if (i < 0 || i + 1 >= segs.length) return null;
    final html = await _page(Uri.https('open.spotify.com', '/embed/${segs[i]}/${segs[i + 1]}'));
    if (html == null) return null;
    final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', dotAll: true).firstMatch(html);
    if (m == null) return null;
    try {
      final data = jsonDecode(m.group(1)!);
      final entity = _find(data, 'entity');
      final list = _find(data, 'trackList');
      if (list is! List) return null;
      final items = <ImportItem>[];
      for (final t in list) {
        if (t is! Map) continue;
        final title = '${t['title'] ?? ''}'.trim();
        if (title.isEmpty) continue;
        items.add(ImportItem(title, '${t['subtitle'] ?? ''}'.trim()));
      }
      final name = entity is Map ? '${entity['name'] ?? entity['title'] ?? ''}'.trim() : '';
      return items.isEmpty ? null : ImportedPlaylist(name.isEmpty ? 'Spotify playlist' : name, items);
    } catch (_) {
      return null;
    }
  }

  dynamic _find(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  // ---- Apple Music ------------------------------------------------------------------------------

  Future<ImportedPlaylist?> _apple(Uri u) async {
    final html = await _page(u);
    if (html == null) return null;
    for (final m in RegExp(r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', dotAll: true).allMatches(html)) {
      try {
        final j = jsonDecode(m.group(1)!);
        final nodes = j is List ? j : [j];
        for (final n in nodes) {
          if (n is! Map) continue;
          final tracks = n['track'];
          if (tracks is! List) continue;
          final items = <ImportItem>[];
          for (final t in tracks) {
            if (t is! Map) continue;
            final title = '${t['name'] ?? ''}'.trim();
            if (title.isEmpty) continue;
            final by = t['byArtist'];
            final artist = by is Map ? '${by['name'] ?? ''}' : (by is List ? by.whereType<Map>().map((e) => '${e['name']}').join(', ') : '${n['byArtist'] is Map ? n['byArtist']['name'] : ''}');
            items.add(ImportItem(title, artist.trim()));
          }
          if (items.isNotEmpty) return ImportedPlaylist('${n['name'] ?? 'Apple Music playlist'}', items);
        }
      } catch (_) {}
    }
    return null;
  }

  // ---- Deezer -----------------------------------------------------------------------------------

  Future<ImportedPlaylist?> _deezer(Uri u) async {
    final i = u.pathSegments.indexOf('playlist');
    if (i < 0 || i + 1 >= u.pathSegments.length) return null;
    final page = await DeezerApi(_settings).playlist(u.pathSegments[i + 1]);
    if (page == null || page.tracks.isEmpty) return null;
    return ImportedPlaylist(page.title, const [], ready: page.tracks);
  }

  // ---- YouTube / YouTube Music ------------------------------------------------------------------

  Future<ImportedPlaylist?> _youtube(Uri u) async {
    final id = u.queryParameters['list'];
    if (id == null || id.isEmpty) return null;
    if (!kIsWeb) {
      final yt = YoutubeExplode();
      try {
        final pl = await yt.playlists.get(PlaylistId(id));
        final items = <ImportItem>[];
        await for (final v in yt.playlists.getVideos(PlaylistId(id))) {
          items.add(ImportItem(v.title.replaceAll(RegExp(r'\s*[\(\[](official|lyrics?|audio|video|music video)[^\)\]]*[\)\]]', caseSensitive: false), ''), v.author.replaceAll(RegExp(r' - Topic$'), '')));
          if (items.length >= 300) break;
        }
        return items.isEmpty ? null : ImportedPlaylist(pl.title, items);
      } catch (_) {
        return null;
      } finally {
        yt.close();
      }
    }
    for (final host in _settings.invidiousHosts) {
      try {
        final r = await _http.get(_settings.proxied(Uri.parse('$host/api/v1/playlists/$id'))).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) continue;
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final vids = j['videos'] as List? ?? const [];
        final items = [for (final v in vids) if (v is Map) ImportItem('${v['title']}', '${v['author']}'.replaceAll(RegExp(r' - Topic$'), ''))];
        if (items.isNotEmpty) return ImportedPlaylist('${j['title'] ?? 'YouTube playlist'}', items);
      } catch (_) {}
    }
    return null;
  }

  // ---- Pasted text / CSV ------------------------------------------------------------------------

  ImportedPlaylist? fromText(String name, String text) {
    final rows = _csvRows(text);
    if (rows.isEmpty) return null;
    final header = rows.first.map((e) => e.toLowerCase()).toList();
    int col(bool Function(String) f) => header.indexWhere(f);
    var tIdx = col((h) => h == 'track name' || h == 'title' || h == 'song' || h == 'track' || h == 'name' || h == 'song name');
    var aIdx = col((h) => h.startsWith('artist'));
    final items = <ImportItem>[];
    if (tIdx >= 0 && aIdx >= 0) {
      for (final r in rows.skip(1)) {
        if (r.length <= tIdx || r.length <= aIdx) continue;
        final t = r[tIdx].trim();
        if (t.isNotEmpty) items.add(ImportItem(t, r[aIdx].split(';').first.trim()));
      }
    } else {
      // One song per line: "Artist - Title" or "Title - Artist" (the order does not matter for search).
      for (final line in text.split(RegExp(r'\r?\n'))) {
        final l = line.trim().replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '');
        if (l.isEmpty) continue;
        final parts = l.split(RegExp(r'\s[-–—]\s'));
        items.add(parts.length >= 2 ? ImportItem(parts[1].trim(), parts[0].trim()) : ImportItem(l, ''));
      }
    }
    return items.isEmpty ? null : ImportedPlaylist(name.trim().isEmpty ? 'Imported playlist' : name.trim(), items);
  }

  List<List<String>> _csvRows(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cur.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cur.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(cur.toString());
        cur.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cur.toString());
        cur.clear();
        if (row.any((e) => e.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cur.write(c);
      }
    }
    row.add(cur.toString());
    if (row.any((e) => e.isNotEmpty)) rows.add(row);
    return rows;
  }

  // ---- Matching ---------------------------------------------------------------------------------

  /// Finds a playable track for each item through the app's own search (JioSaavn + YouTube).
  Future<({List<Track> matched, List<ImportItem> missed})> match(
    List<ImportItem> items,
    Future<List<Track>> Function(String query) search,
    void Function(int done, int total) onProgress,
  ) async {
    final results = List<Track?>.filled(items.length, null);
    var done = 0;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        final it = items[i];
        try {
          final found = await search('${it.title} ${it.artist}'.trim()).timeout(const Duration(seconds: 15));
          final want = Track(mediaId: 'want', title: it.title, artist: it.artist);
          Track? best;
          var bestScore = 0.0;
          for (final c in found.take(8)) {
            var s = TrackMatch.score(want, Track(mediaId: c.mediaId, title: c.title, artist: c.artist));
            // YouTube titles often read "Artist - Song": accept a contained title when the artist also appears.
            final nt = TrackMatch.normalize(it.title);
            if (nt.isNotEmpty && TrackMatch.normalize(c.title).contains(nt)) {
              final na = TrackMatch.normalize(it.artist).split(' ').first;
              final ok = na.isEmpty || TrackMatch.normalize('${c.title} ${c.artist}').contains(na);
              if (ok && s < 0.7) s = 0.7;
            }
            if (s > bestScore) {
              best = c;
              bestScore = s;
            }
          }
          // Title overlap alone is enough when durations are unknown on the wanted side.
          if (best != null && bestScore >= 0.45) results[i] = best;
        } catch (_) {}
        onProgress(++done, items.length);
      }
    }

    await Future.wait([for (var w = 0; w < 4; w++) worker()]);
    return (
      matched: [for (final r in results) if (r != null) r],
      missed: [for (var i = 0; i < items.length; i++) if (results[i] == null) items[i]],
    );
  }
}
