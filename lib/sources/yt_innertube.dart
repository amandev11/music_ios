import 'stream_proxy_stub.dart' if (dart.library.io) 'stream_proxy_io.dart' show nativeOnlyYoutube;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'source.dart';

class InnerTubeClient {
  const InnerTubeClient(this.name, this.version, this.id, this.userAgent, this.context);
  final String name;
  final String version;
  final int id;
  final String userAgent;
  final Map<String, Object> context;

  /// Android VR: needs neither a JavaScript player nor a proof-of-origin token, and returns direct URLs.
  static const androidVrNew = InnerTubeClient(
    'ANDROID_VR',
    '1.65.10',
    28,
    'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {'deviceMake': 'Oculus', 'deviceModel': 'Quest 3', 'osName': 'Android', 'osVersion': '12L', 'androidSdkVersion': 32},
  );

  static const androidVr = InnerTubeClient(
    'ANDROID_VR',
    '1.60.19',
    28,
    'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {'deviceMake': 'Oculus', 'deviceModel': 'Quest 3', 'osName': 'Android', 'osVersion': '12L', 'androidSdkVersion': 32},
  );

  static const ios = InnerTubeClient(
    'IOS',
    '20.10.4',
    5,
    'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    {'deviceMake': 'Apple', 'deviceModel': 'iPhone16,2', 'osName': 'iPhone', 'osVersion': '18.3.2.22D82'},
  );

  static const all = [androidVrNew, androidVr, ios];
}

class InnerTubeResult {
  InnerTubeResult(this.client, this.status, this.reason, this.formats);
  final InnerTubeClient client;
  final String status;
  final String reason;
  final List<({String url, int bitrate, String mime})> formats;
}

/// Direct calls to YouTube's `player` endpoint, the same requests the mobile apps make.
class YtInnerTube {
  YtInnerTube({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Future<InnerTubeResult> player(String videoId, InnerTubeClient c) async {
    try {
      final res = await _http
          .post(
            Uri.https('www.youtube.com', '/youtubei/v1/player', {'prettyPrint': 'false'}),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': c.userAgent,
              'X-YouTube-Client-Name': '${c.id}',
              'X-YouTube-Client-Version': c.version,
              'Origin': 'https://www.youtube.com',
            },
            body: jsonEncode({
              'context': {
                'client': {'clientName': c.name, 'clientVersion': c.version, 'hl': 'en', 'gl': 'US', ...c.context},
              },
              'videoId': videoId,
              'contentCheckOk': true,
              'racyCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return InnerTubeResult(c, 'HTTP ${res.statusCode}', '', const []);
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final ps = j['playabilityStatus'];
      final status = ps is Map ? '${ps['status']}' : 'NO_STATUS';
      final reason = ps is Map ? '${ps['reason'] ?? ''}' : '';
      final list = j['streamingData'] is Map ? (j['streamingData']['adaptiveFormats'] as List? ?? const []) : const [];
      final out = <({String url, int bitrate, String mime})>[];
      for (final f in list) {
        if (f is! Map) continue;
        final mime = '${f['mimeType']}';
        if (!mime.startsWith('audio/') || f['url'] == null) continue;
        out.add((url: '${f['url']}', bitrate: (f['bitrate'] as num?)?.toInt() ?? 0, mime: mime));
      }
      // Muxed MP4 (itag 18: 360p video + AAC audio) is the one stream YouTube still serves without a PO token;
      // the native player simply reads the audio track out of it. Used only after every audio-only stream.
      final muxed = j['streamingData'] is Map ? (j['streamingData']['formats'] as List? ?? const []) : const [];
      for (final f in muxed) {
        if (f is! Map) continue;
        final mime = '${f['mimeType']}';
        if (!mime.startsWith('video/mp4') || !mime.contains('mp4a') || f['url'] == null) continue;
        out.add((url: '${f['url']}', bitrate: (f['bitrate'] as num?)?.toInt() ?? 0, mime: mime));
      }
      return InnerTubeResult(c, status, reason, out);
    } catch (e) {
      return InnerTubeResult(c, 'ERROR', '$e', const []);
    }
  }

  /// Audio-only streams in the order wanted for [quality], then (as a last resort for that client) the muxed MP4.
  static List<({String url, int bitrate, String mime})> _order(List<({String url, int bitrate, String mime})> formats, int quality, int audioTake) {
    final audio = formats.where((f) => f.mime.startsWith('audio/')).toList();
    final mp4 = audio.where((f) => f.mime.contains('mp4')).toList();
    final pool = ((mp4.isNotEmpty || nativeOnlyYoutube) ? mp4 : audio)..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final ordered = pool.isEmpty
        ? <({String url, int bitrate, String mime})>[]
        : (quality <= 0 ? pool.reversed.toList() : (quality == 1 ? [pool[pool.length ~/ 2], ...pool] : pool));
    final muxed = formats.where((f) => f.mime.startsWith('video/')).toList()..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    return [...ordered.take(audioTake), ...muxed.take(1)];
  }

  /// Every audio stream YouTube offers for [videoId], best candidates first, one client after another.
  Stream<Playable> candidates(String videoId, {int quality = 2}) async* {
    for (final c in InnerTubeClient.all) {
      final r = await player(videoId, c);
      if (r.formats.isEmpty) {
        debugPrint('InnerTube ${c.name} ${c.version}: ${r.status} ${r.reason}');
        continue;
      }
      for (final f in _order(r.formats, quality, 2)) {
        yield Playable.url(f.url, headers: {'User-Agent': c.userAgent}, kbps: (f.bitrate / 1000).round());
      }
    }
  }

  /// Best reachable audio stream for [videoId], or null. [quality]: 0 low, 1 medium, 2+ high.
  Future<Playable?> stream(String videoId, {int quality = 2}) async {
    for (final c in InnerTubeClient.all) {
      final r = await player(videoId, c);
      if (r.formats.isEmpty) {
        debugPrint('InnerTube ${c.name}: ${r.status} ${r.reason}');
        continue;
      }
      final ordered = _order(r.formats, quality, 3);
      for (final f in ordered) {
        final headers = {'User-Agent': c.userAgent};
        if (await probe(f.url, headers)) return Playable.url(f.url, headers: headers, kbps: (f.bitrate / 1000).round());
      }
    }
    return null;
  }

  Future<int> probeStatus(String url, Map<String, String> headers) async {
    try {
      final r = await _http.get(Uri.parse(url), headers: {...headers, 'Range': 'bytes=0-1'}).timeout(const Duration(seconds: 8));
      return r.statusCode;
    } catch (_) {
      return -1;
    }
  }

  Future<bool> probe(String url, Map<String, String> headers) async {
    final s = await probeStatus(url, headers);
    return s == 200 || s == 206;
  }
}
