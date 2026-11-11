import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../core/models.dart';
import '../core/settings.dart';
import 'source.dart';

class SaavnStream {
  const SaavnStream(this.url, this.kbps);
  final String url;
  final int? kbps;
}

/// Picks the highest rendition the CDN really has: the encrypted URL names the 96 kbps object, and
/// the catalogue says whether a parallel 320 exists.
SaavnStream? selectBestSaavnStream(String decrypted, bool supports320, {int maxKbps = 320}) {
  if (decrypted.isEmpty) return null;
  final m = RegExp(r'_(48|96|160|320)\.(mp4|aac|mp3)(?=[?#]|$)', caseSensitive: false).firstMatch(decrypted);
  if (m == null) return SaavnStream(decrypted, null);
  final offered = int.parse(m.group(1)!);
  if (!supports320 || maxKbps < 320) {
    // Lower tiers: the named object (96) or its 160 sibling, never above the cap.
    final want = maxKbps >= 160 ? 160 : offered;
    if (want == offered || !supports320) return SaavnStream(decrypted, offered);
    return SaavnStream(decrypted.replaceRange(m.start, m.end, '_160.${m.group(2)}'), 160);
  }
  return SaavnStream(decrypted.replaceRange(m.start, m.end, '_320.${m.group(2)}'), 320);
}

class JioSaavnSource implements MusicSource {
  JioSaavnSource(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  final Settings _settings;
  final http.Client _http;

  @override
  SourceKind get kind => SourceKind.saavn;

  static const _base = 'https://www.jiosaavn.com/api.php';
  static const _desKey = '38346591';
  static const _minUsableKbps = 96;

  final Map<String, (String, bool)> _encrypted = {};

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final body = await _call('search.getResults', {'q': query, 'p': '1', 'n': '${limit.clamp(1, 30)}'});
    if (body == null) return const [];
    final results = (body['results'] as List?)?.whereType<Map>().toList() ?? const [];
    results.sort((a, b) => (_explicit(b) ? 1 : 0).compareTo(_explicit(a) ? 1 : 0));
    return results.map(_toTrack).whereType<Track>().take(limit).toList();
  }

  @override
  Future<Playable?> stream(String rawId) async {
    final cached = _encrypted[rawId] ?? await _fetchDetails(rawId);
    if (cached == null) return null;
    final chosen = selectBestSaavnStream(_decrypt(cached.$1), cached.$2, maxKbps: _settings.qualityKbps);
    if (chosen == null) return null;
    if (chosen.kbps != null && chosen.kbps! <= _minUsableKbps) return null;
    return Playable.url(chosen.url, kbps: chosen.kbps);
  }

  Future<(String, bool)?> _fetchDetails(String id) async {
    final root = await _call('song.getDetails', {'pids': id});
    if (root == null) return null;
    Map? song;
    final songs = root['songs'];
    if (songs is List && songs.isNotEmpty && songs.first is Map) {
      song = songs.first as Map;
    } else if (root[id] is Map) {
      song = root[id] as Map;
    } else {
      for (final v in root.values) {
        if (v is Map) {
          song = v;
          break;
        }
      }
    }
    final info = song?['more_info'];
    if (info is! Map) return null;
    final enc = (info['encrypted_media_url'] as String?) ?? '';
    if (enc.isEmpty) return null;
    final entry = (enc, '${info['320kbps']}'.toLowerCase() == 'true');
    _encrypted[id] = entry;
    return entry;
  }

  Track? _toTrack(Map song) {
    final id = (song['id'] as String?) ?? '';
    if (id.isEmpty) return null;
    final info = (song['more_info'] as Map?) ?? const {};
    final enc = (info['encrypted_media_url'] as String?) ?? '';
    if (enc.isNotEmpty) _encrypted[id] = (enc, '${info['320kbps']}'.toLowerCase() == 'true');

    final primary = ((info['artistMap'] as Map?)?['primary_artists'] as List?) ?? const [];
    final artist = primary
        .whereType<Map>()
        .map((a) => (a['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');

    var image = (song['image'] as String?) ?? '';
    image = image.replaceAll(RegExp(r'150x150|50x50'), '500x500').replaceFirst(RegExp(r'^http://'), 'https://');

    return Track(
      mediaId: TrackKeys.saavn(id),
      title: decodeEntities((song['title'] as String?) ?? ''),
      artist: artist.isEmpty ? 'Unknown Artist' : decodeEntities(artist),
      album: decodeEntities((info['album'] as String?) ?? ''),
      albumId: id.hashCode,
      durationMs: (int.tryParse('${info['duration']}') ?? 0) * 1000,
      artworkUri: image.isEmpty ? null : image,
      uri: TrackKeys.saavn(id),
      mimeType: 'audio/mp4',
    );
  }

  bool _explicit(Map song) {
    final v = '${song['explicit_content']}'.toLowerCase();
    return v == '1' || v == 'true';
  }

  Future<Map<String, dynamic>?> _call(String method, Map<String, String> params) async {
    try {
      final url = Uri.parse(_base).replace(queryParameters: {
        '__call': method,
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'android',
        ...params,
      });
      final res = await _http
          .get(_settings.proxied(url), headers: const {
            'Accept': 'application/json',
            'Accept-Language': 'en-IN,en;q=0.9',
          })
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// The catalogue's own client-side obfuscation: DES/ECB over a base64 URL.
  String _decrypt(String encryptedUrl) {
    try {
      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(DESedeEngine()))
        ..init(false, PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
            KeyParameter(Uint8List.fromList(utf8.encode(_desKey * 3))), null));
      return utf8.decode(cipher.process(base64.decode(encryptedUrl))).trim();
    } catch (_) {
      return '';
    }
  }
}
