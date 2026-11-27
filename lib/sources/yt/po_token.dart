import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Proof-of-origin tokens ("PO tokens"): YouTube refuses most stream links that are not accompanied by a token
/// minted by Google's BotGuard script. Every serious YouTube client (NewPipe, Metrolist, yt-dlp's providers)
/// solves it the same way, and so do we: BotGuard's VM runs inside a hidden WebView whose base URL is
/// youtube.com, Dart performs the two network calls (challenge, integrity token), and tokens are minted on
/// demand for a content binding (the visitor id for stream links, the video id for player requests).
///
/// Works on iPhone/iPad/macOS (WKWebView). Elsewhere [available] is false and callers simply go without tokens.
class PoTokenService {
  PoTokenService._();
  static final PoTokenService I = PoTokenService._();

  static const _requestKey = 'O43z0dpjhgX20SCx4KAo';
  static const String _apiKey = String.fromEnvironment(
    'YOUTUBE_WAA_API_KEY',
    defaultValue: '',
  );
  static const _base =
      'https://jnn-pa.googleapis.com/\$rpc/google.internal.waa.v1.Waa';
  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1';

  static bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  final _http = http.Client();
  WebViewController? _web;
  Future<bool>? _boot;
  DateTime _bootedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _ttl = const Duration(hours: 5);
  int _seq = 0;
  final _calls = <int, Completer<String>>{};
  final _cache = <String, (String, DateTime)>{};
  String lastError = '';

  /// Starts BotGuard (once; renewed before the integrity token expires). Completes with false when unavailable.
  Future<bool> ensure() {
    if (!available) return Future.value(false);
    final stale = DateTime.now().difference(_bootedAt) > _ttl;
    if (_boot == null || stale) {
      _boot = _start().timeout(
        const Duration(seconds: 40),
        onTimeout: () {
          lastError = 'BotGuard timed out';
          return false;
        },
      );
    }
    return _boot!;
  }

  Future<bool> _start() async {
    try {
      final params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
      final c = WebViewController.fromPlatformCreationParams(params);
      await c.setJavaScriptMode(JavaScriptMode.unrestricted);
      await c.setUserAgent(_ua);
      await c.addJavaScriptChannel(
        'Pot',
        onMessageReceived: (m) {
          final d = jsonDecode(m.message) as Map;
          final done = _calls.remove((d['id'] as num).toInt());
          if (done == null) return;
          d['ok'] == true
              ? done.complete('${d['value']}')
              : done.completeError('${d['value']}');
        },
      );
      final script = await rootBundle.loadString('assets/pot/aurora_pot.js');
      final loaded = Completer<void>();
      await c.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      );
      await c.loadHtmlString(
        '<!doctype html><html><head></head><body><script>$script</script></body></html>',
        baseUrl: 'https://www.youtube.com',
      );
      await loaded.future.timeout(const Duration(seconds: 15));
      _web = c;

      // 1) challenge  2) run BotGuard's VM in the page  3) trade its answer for an integrity token
      final raw = await _post('Create', [_requestKey]);
      final snapshot = await _call('begin', raw);
      final it = await _post('GenerateIT', [_requestKey, snapshot]);
      final parsed = jsonDecode(it) as List;
      final token = '${parsed[0]}';
      if (parsed.length > 1 && parsed[1] is num) {
        final secs = (parsed[1] as num).toInt();
        _ttl = Duration(seconds: (secs * 0.8).round().clamp(600, 6 * 3600));
      }
      await _call('finish', token);
      _bootedAt = DateTime.now();
      _cache.clear();
      lastError = '';
      return true;
    } catch (e) {
      lastError = '$e'.split('\n').first;
      debugPrint('PoToken: start failed: $lastError');
      _web = null;
      return false;
    }
  }

  Future<String> _post(String method, List<Object> body) async {
    final res = await _http
        .post(
          Uri.parse('$_base/$method'),
          headers: {
            'content-type': 'application/json+protobuf',
            'x-goog-api-key': _apiKey,
            'x-user-agent': 'grpc-web-javascript/0.1',
            'user-agent': _ua,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw 'WAA $method HTTP ${res.statusCode}';
    return utf8.decode(res.bodyBytes);
  }

  Future<String> _call(String fn, String arg) {
    final id = ++_seq;
    final c = Completer<String>();
    _calls[id] = c;
    unawaited(_web!.runJavaScript('AuroraPot.$fn($id, ${jsonEncode(arg)});'));
    return c.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _calls.remove(id);
        throw '$fn timed out';
      },
    );
  }

  /// A token bound to [binding] (visitor id or video id), or null when BotGuard is unavailable.
  Future<String?> mint(String binding) async {
    if (!await ensure() || _web == null) return null;
    final hit = _cache[binding];
    if (hit != null &&
        DateTime.now().difference(hit.$2) < const Duration(minutes: 30))
      return hit.$1;
    try {
      final t = await _call('mint', binding);
      _cache[binding] = (t, DateTime.now());
      return t;
    } catch (e) {
      lastError = '$e'.split('\n').first;
      return null;
    }
  }
}
