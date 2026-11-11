import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/settings.dart';
import 'stream_proxy_stub.dart' if (dart.library.io) 'stream_proxy_io.dart' show nativeOnlyYoutube;
import 'source.dart';

/// Last-resort stream lookup through public Piped and Invidious instances, used only when every direct
/// YouTube client has failed. These services extract the stream themselves and hand back a URL.
class YtFallback {
  YtFallback(this._settings);
  final Settings? _settings;
  final _http = http.Client();

  static const _piped = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.private.coffee',
  ];

  Future<Playable?> stream(String id, {int quality = 2}) async {
    for (final host in _piped) {
      final p = await _fromPiped(host, id, quality);
      if (p != null) return p;
    }
    for (final host in (_settings?.invidiousHosts ?? Settings.defaultInvidious)) {
      final p = await _fromInvidious(host, id, quality);
      if (p != null) return p;
    }
    return null;
  }

  Future<Playable?> _fromPiped(String host, String id, int quality) async {
    try {
      final res = await _http.get(Uri.parse('$host/streams/$id')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      var list = (jsonDecode(res.body)['audioStreams'] as List?)?.whereType<Map>().toList() ?? const [];
      if (nativeOnlyYoutube) list = list.where((s) => '${s['mimeType']}'.contains('mp4')).toList(); // native engine: AAC only
      return _pick([for (final s in list) (url: '${s['url']}', bitrate: (s['bitrate'] as num?)?.toInt() ?? 0)], quality);
    } catch (e) {
      debugPrint('Piped $host failed: $e');
      return null;
    }
  }

  Future<Playable?> _fromInvidious(String host, String id, int quality) async {
    try {
      final res = await _http.get(Uri.parse('$host/api/v1/videos/$id?local=true')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final list = (jsonDecode(res.body)['adaptiveFormats'] as List?)
              ?.whereType<Map>()
              .where((f) => '${f['type']}'.startsWith('audio/') && (!nativeOnlyYoutube || '${f['type']}'.contains('mp4')))
              .toList() ??
          const [];
      return _pick([for (final s in list) (url: '${s['url']}', bitrate: int.tryParse('${s['bitrate']}') ?? 0)], quality);
    } catch (e) {
      debugPrint('Invidious $host failed: $e');
      return null;
    }
  }

  Future<Playable?> _pick(List<({String url, int bitrate})> all, int quality) async {
    final usable = all.where((s) => s.url.startsWith('http')).toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (usable.isEmpty) return null;
    final ordered = quality <= 0 ? usable.reversed.toList() : (quality == 1 ? [usable[usable.length ~/ 2], ...usable] : usable);
    for (final s in ordered.take(2)) {
      try {
        final r = await _http.get(Uri.parse(s.url), headers: {'Range': 'bytes=0-1'}).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200 || r.statusCode == 206) return Playable.url(s.url, kbps: (s.bitrate / 1000).round());
      } catch (_) {}
    }
    return null;
  }
}
