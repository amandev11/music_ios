import 'stream_proxy_stub.dart'
    if (dart.library.io) 'stream_proxy_io.dart'
    show nativeOnlyYoutube;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'source.dart';
import 'yt/po_token.dart';
import 'yt_trace.dart';

class InnerTubeClient {
  const InnerTubeClient(
    this.name,
    this.version,
    this.id,
    this.userAgent,
    this.context, {
    this.music = false,
    this.mediaHeaders = true,
  });
  final String name;
  final String version;
  final int id;
  final String userAgent;
  final Map<String, Object> context;

  /// Calls music.youtube.com/youtubei (Metrolist's `useMusicPlayerEndpoint`).
  final bool music;

  /// Whether the media download should carry this client's User-Agent (Metrolist sends none for VISIONOS / ANDROID_VR).
  final bool mediaHeaders;

  /// visionOS 0.1: Metrolist's October 2026 benchmark found it the fastest client for normal audio, tokenless but
  /// needing real visitorData; ios/android are SABR-only or fail on later ranges now.
  static const visionOs = InnerTubeClient(
    'VISIONOS',
    '0.1',
    101,
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15',
    {
      'osName': 'VISION_OS',
      'osVersion': '1.3',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice14,1',
      'platform': 'MOBILE',
    },
    music: true,
    mediaHeaders: false,
  );

  /// Android VR: needs neither a JavaScript player nor a proof-of-origin token, and returns direct URLs.
  static const androidVrNew = InnerTubeClient(
    'ANDROID_VR',
    '1.65.10',
    28,
    'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
      'androidSdkVersion': 32,
    },
  );

  static const androidVr = InnerTubeClient(
    'ANDROID_VR',
    '1.60.19',
    28,
    'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
      'androidSdkVersion': 32,
    },
  );

  static const ios = InnerTubeClient(
    'IOS',
    '20.10.4',
    5,
    'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    {
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    },
  );

  static const all = [visionOs, androidVrNew, androidVr, ios];
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

  String? _visitor;
  DateTime _visitorAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _webUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  /// The visitor id every stream link is bound to (renewed every few hours). Same sources Metrolist uses:
  /// the service-worker data (`sw.js_data`), then the music.youtube.com homepage, then a visitor_id call.
  Future<String?> visitor() async {
    if (_visitor != null &&
        DateTime.now().difference(_visitorAt) < const Duration(hours: 4))
      return _visitor;
    String? v;
    try {
      final res = await _http
          .get(
            Uri.https('www.youtube.com', '/sw.js_data'),
            headers: {
              'User-Agent': _webUa,
              'Accept': 'application/json,text/plain,*/*',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final j = jsonDecode(body.substring(body.indexOf('\n') + 1).trimLeft());
        final x = j[0][2][0][0][13];
        if (x is String && x.isNotEmpty) v = x;
      }
    } catch (_) {}
    if (v == null) {
      try {
        final res = await _http
            .get(
              Uri.https('music.youtube.com', '/'),
              headers: {
                'User-Agent': _webUa,
                'Accept': 'text/html,*/*',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 10));
        final m = RegExp(r'"(?:VISITOR_DATA|visitorData)"\s*:\s*"([^"]+)"')
            .firstMatch(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (m != null) v = m.group(1);
      } catch (_) {}
    }
    if (v == null) {
      try {
        final res = await _http
            .post(
              Uri.https('www.youtube.com', '/youtubei/v1/visitor_id', {
                'prettyPrint': 'false',
              }),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': InnerTubeClient.ios.userAgent,
              },
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'IOS',
                    'clientVersion': InnerTubeClient.ios.version,
                    'hl': 'en',
                    'gl': 'US',
                    ...InnerTubeClient.ios.context,
                  },
                },
              }),
            )
            .timeout(const Duration(seconds: 10));
        final x = jsonDecode(
          utf8.decode(res.bodyBytes),
        )['responseContext']?['visitorData'];
        if (x is String && x.isNotEmpty) v = x;
      } catch (_) {}
    }
    if (v != null) {
      _visitor = v;
      _visitorAt = DateTime.now();
    }
    return _visitor;
  }

  Future<InnerTubeResult> player(
    String videoId,
    InnerTubeClient c, {
    String? visitorData,
    String? playerPot,
  }) async {
    try {
      final res = await _http
          .post(
            Uri.https(
              c.music ? 'music.youtube.com' : 'www.youtube.com',
              '/youtubei/v1/player',
              {'prettyPrint': 'false'},
            ),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': c.userAgent,
              'X-Goog-Api-Format-Version': '1',
              'X-YouTube-Client-Name': '${c.id}',
              'X-YouTube-Client-Version': c.version,
              'Origin': c.music
                  ? 'https://music.youtube.com'
                  : 'https://www.youtube.com',
              'X-Origin': c.music
                  ? 'https://music.youtube.com'
                  : 'https://www.youtube.com',
              'Referer': c.music
                  ? 'https://music.youtube.com/'
                  : 'https://www.youtube.com/',
              if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': c.name,
                  'clientVersion': c.version,
                  'hl': 'en',
                  'gl': 'US',
                  if (visitorData != null) 'visitorData': visitorData,
                  ...c.context,
                },
              },
              if (playerPot != null)
                'serviceIntegrityDimensions': {'poToken': playerPot},
              'videoId': videoId,
              'contentCheckOk': true,
              'racyCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200)
        return InnerTubeResult(c, 'HTTP ${res.statusCode}', '', const []);
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final ps = j['playabilityStatus'];
      final status = ps is Map ? '${ps['status']}' : 'NO_STATUS';
      final reason = ps is Map ? '${ps['reason'] ?? ''}' : '';
      final list = j['streamingData'] is Map
          ? (j['streamingData']['adaptiveFormats'] as List? ?? const [])
          : const [];
      final out = <({String url, int bitrate, String mime})>[];
      for (final f in list) {
        if (f is! Map) continue;
        final mime = '${f['mimeType']}';
        if (!mime.startsWith('audio/') || f['url'] == null) continue;
        out.add((
          url: '${f['url']}',
          bitrate: (f['bitrate'] as num?)?.toInt() ?? 0,
          mime: mime,
        ));
      }
      // Muxed MP4 (itag 18: 360p video + AAC audio) is the one stream YouTube still serves without a PO token;
      // the native player simply reads the audio track out of it. Used only after every audio-only stream.
      final muxed = j['streamingData'] is Map
          ? (j['streamingData']['formats'] as List? ?? const [])
          : const [];
      for (final f in muxed) {
        if (f is! Map) continue;
        final mime = '${f['mimeType']}';
        if (!mime.startsWith('video/mp4') ||
            !mime.contains('mp4a') ||
            f['url'] == null)
          continue;
        out.add((
          url: '${f['url']}',
          bitrate: (f['bitrate'] as num?)?.toInt() ?? 0,
          mime: mime,
        ));
      }
      return InnerTubeResult(c, status, reason, out);
    } catch (e) {
      return InnerTubeResult(c, 'ERROR', '$e', const []);
    }
  }

  /// Audio-only streams in the order wanted for [quality], then (as a last resort for that client) the muxed MP4.
  static List<({String url, int bitrate, String mime})> _order(
    List<({String url, int bitrate, String mime})> formats,
    int quality,
    int audioTake,
  ) {
    final audio = formats.where((f) => f.mime.startsWith('audio/')).toList();
    final mp4 = audio.where((f) => f.mime.contains('mp4')).toList();
    final pool = ((mp4.isNotEmpty || nativeOnlyYoutube) ? mp4 : audio)
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final ordered = pool.isEmpty
        ? <({String url, int bitrate, String mime})>[]
        : (quality <= 0
              ? pool.reversed.toList()
              : (quality == 1 ? [pool[pool.length ~/ 2], ...pool] : pool));
    final muxed = formats.where((f) => f.mime.startsWith('video/')).toList()
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    return [...ordered.take(audioTake), ...muxed.take(1)];
  }

  /// Client attempts in the order they are tried, from Metrolist's live client benchmark (Aug-Nov 2026):
  /// VISIONOS 0.1 (tokenless, needs visitorData) is fastest and sustains full downloads; the Android VR profiles
  /// resolve but may refuse later ranges; IOS now returns SABR-only (no direct URLs) so it is gone, which also
  /// removes the BotGuard start-up from the hot path. `pot: true` steps still work if a client ever needs them.
  static const plan = <({InnerTubeClient client, bool pot})>[
    (client: InnerTubeClient.visionOs, pot: false),
    (client: InnerTubeClient.androidVrNew, pot: false),
    (client: InnerTubeClient.androidVr, pot: false),
  ];

  /// Every stream YouTube offers for [videoId], best candidates first, one client after another.
  Stream<Playable> candidates(String videoId, {int quality = 2}) async* {
    final visitorData = await visitor();
    for (final step in plan) {
      final c = step.client;
      String? gvsPot, playerPot;
      if (step.pot) {
        if (visitorData == null) {
          YtTrace.log('no-visitor');
          continue;
        }
        gvsPot = await PoTokenService.I.mint(visitorData);
        playerPot = await PoTokenService.I.mint(videoId);
        if (gvsPot == null || playerPot == null) {
          YtTrace.log(
            'pot:${PoTokenService.I.lastError.isEmpty ? 'unavailable' : PoTokenService.I.lastError}',
          );
          continue;
        }
      }
      final r = await player(
        videoId,
        c,
        visitorData: visitorData,
        playerPot: playerPot,
      );
      if (r.formats.isEmpty) {
        YtTrace.log('${c.name}${step.pot ? '+pot' : ''}:${r.status}');
        debugPrint('InnerTube ${c.name} ${c.version}: ${r.status} ${r.reason}');
        continue;
      }
      for (final f in _order(r.formats, quality, 2)) {
        final url = gvsPot == null
            ? f.url
            : '${f.url}&pot=${Uri.encodeQueryComponent(gvsPot)}';
        yield Playable.url(
          url,
          headers: c.mediaHeaders
              ? {'User-Agent': c.userAgent}
              : const <String, String>{},
          kbps: (f.bitrate / 1000).round(),
        );
      }
    }
  }

  Future<int> probeStatus(String url, Map<String, String> headers) async {
    try {
      final r = await _http
          .get(Uri.parse(url), headers: {...headers, 'Range': 'bytes=0-1'})
          .timeout(const Duration(seconds: 8));
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
