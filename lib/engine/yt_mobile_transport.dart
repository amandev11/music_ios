import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../sources/source.dart';
import 'transport.dart';

const _mobilePage = '''<!doctype html><html><body style="margin:0;background:#000"><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player, ready = false;
function post(o) { Bridge.postMessage(JSON.stringify(o)); }
function onYouTubeIframeAPIReady() {
  player = new YT.Player('p', {
    height: '200', width: '200',
    playerVars: { controls: 0, playsinline: 1, rel: 0, origin: location.origin },
    events: {
      onReady: function () { ready = true; post({ t: 'ready' }); },
      onStateChange: function (e) { post({ t: 'state', v: e.data }); },
      onError: function (e) { post({ t: 'error', v: e.data }); }
    }
  });
}
setInterval(function () {
  if (ready && player.getCurrentTime) post({ t: 'pos', v: player.getCurrentTime(), d: player.getDuration() });
}, 250);
</script></body></html>''';

/// YouTube's official embedded player inside a hidden WKWebView (iPhone/iPad/macOS) or Android WebView.
/// Used as the last resort when no direct stream can be fetched (YouTube's bot check / 403s), because it
/// needs no extraction. Limits: videos with embedding disabled fail (error 101/150/153), and iOS may
/// pause web audio when the app is backgrounded or the screen locks.
class MobileYtTransport implements Transport {
  WebViewController? _c;
  Future<void>? _boot;
  final _ready = Completer<void>();

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _position = StreamController<int>.broadcast();
  int _pos = 0, _dur = 0;

  Future<void> _ensure() => _boot ??= _start();

  Future<void> _start() async {
    late PlatformWebViewControllerCreationParams params;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final c = WebViewController.fromPlatformCreationParams(params);
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.addJavaScriptChannel(
      'Bridge',
      onMessageReceived: (m) => _onMessage(m.message),
    );
    _c = c;
    await c.loadHtmlString(_mobilePage, baseUrl: 'https://www.youtube.com');
    await _ready.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw 'YouTube player did not load',
    );
  }

  void _onMessage(String m) {
    final Map<dynamic, dynamic> msg = jsonDecode(m) as Map;
    switch (msg['t']) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'state':
        final s = (msg['v'] as num).toInt();
        _playing.add(s == 1);
        _buffering.add(s == 3 || s == -1);
        if (s == 0) _completed.add(null);
      case 'error':
        _errors.add(
          'YouTube embed error ${msg['v']} (the owner may have disabled embedding)',
        );
      case 'pos':
        _pos = ((msg['v'] as num) * 1000).round();
        _dur = ((msg['d'] as num? ?? 0) * 1000).round();
        _position.add(_pos);
    }
  }

  Future<void> _js(String code, {bool boot = false}) async {
    if (_boot == null && !boot) return;
    await _ensure();
    await _c!.runJavaScript(code);
  }

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<int> get positionMs => _position.stream;
  @override
  int get durationMs => _dur;
  @override
  int get currentPositionMs => _pos;
  @override
  bool get supportsEq => false;
  @override
  bool get supportsMixFilter => false;
  @override
  bool canPlay(Playable p) => p.youtubeId != null;

  @override
  Future<void> open(Playable p, {int startMs = 0}) async {
    final id = p.youtubeId!.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    _pos = 0;
    _dur = 0;
    await _js(
      "player.loadVideoById({videoId:'$id',startSeconds:${startMs / 1000}});",
      boot: true,
    );
  }

  @override
  Future<void> play() => _js('player.playVideo();', boot: true);
  @override
  Future<void> pause() => _js('player.pauseVideo();');
  @override
  Future<void> seek(int ms) => _js('player.seekTo(${ms / 1000}, true);');
  @override
  Future<void> setSpeed(double speed) => _js('player.setPlaybackRate($speed);');
  @override
  Future<void> setVolume(double volume) =>
      _js('player.setVolume(${(volume.clamp(0.0, 1.0) * 100).round()});');
  @override
  Future<void> setEq(bool enabled, List<double> gainsDb) async {}
  @override
  bool get supportsSpatial => false;
  @override
  Future<void> setSpatial(bool on) async {}
  @override
  Future<void> setProtection(bool on) async {}
  @override
  Future<void> setMixChain(bool on) async {}
  @override
  Future<void> setMixFilter(double highpassHz, double lowpassHz) async {}
  @override
  Future<List<AudioOutput>> outputs() async => const [];
  @override
  Future<void> setOutput(String id) async {}
  @override
  Future<void> dispose() async {}
}
