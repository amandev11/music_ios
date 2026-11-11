import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';

import '../sources/source.dart';
import 'transport.dart';

Transport? createDesktopYt() => defaultTargetPlatform == TargetPlatform.windows ? WindowsYtTransport() : null;

const _page = '''<!doctype html><html><body style="margin:0;background:#000"><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player, ready = false;
function post(o) { window.chrome.webview.postMessage(o); }
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

/// YouTube's official embedded player inside a hidden WebView2, used as the last resort on Windows when
/// no direct stream can be fetched. No extraction, so it keeps working when YouTube blocks scrapers.
/// Some videos forbid embedding (error 101/150/153); those fail like any other unavailable track.
class WindowsYtTransport implements Transport {
  HttpServer? _server;
  WebviewController? _c;
  Future<void>? _boot;
  final _ready = Completer<void>();
  static bool _envDone = false;

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _position = StreamController<int>.broadcast();
  int _pos = 0, _dur = 0;

  Future<void> _ensure() => _boot ??= _start();

  Future<void> _start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((r) {
      r.response.headers.contentType = ContentType.html;
      r.response.write(_page);
      r.response.close();
    });
    if (!_envDone) {
      _envDone = true;
      try {
        await WebviewController.initializeEnvironment(additionalArguments: '--autoplay-policy=no-user-gesture-required');
      } catch (e) {
        debugPrint('WebView2 environment: $e');
      }
    }
    final c = WebviewController();
    await c.initialize();
    await c.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    c.webMessage.listen(_onMessage);
    _c = c;
    await c.loadUrl('http://127.0.0.1:${_server!.port}/');
    await _ready.future.timeout(const Duration(seconds: 25), onTimeout: () => throw 'YouTube player did not load (is WebView2 installed?)');
  }

  void _onMessage(dynamic m) {
    final Map<dynamic, dynamic> msg = m is String ? (jsonDecode(m) as Map) : (m as Map);
    switch (msg['t']) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'state':
        final s = (msg['v'] as num).toInt(); // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
        _playing.add(s == 1);
        _buffering.add(s == 3 || s == -1);
        if (s == 0) _completed.add(null);
      case 'error':
        _errors.add('YouTube embed error ${msg['v']} (the owner may have disabled embedding)');
      case 'pos':
        _pos = ((msg['v'] as num) * 1000).round();
        _dur = ((msg['d'] as num? ?? 0) * 1000).round();
        _position.add(_pos);
    }
  }

  /// Commands before the first YouTube track are ignored, so WebView2 starts only when it is needed.
  Future<void> _js(String code, {bool boot = false}) async {
    if (_boot == null && !boot) return;
    await _ensure();
    await _c!.executeScript(code);
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
    await _js("player.cueVideoById({videoId:'$id',startSeconds:${startMs / 1000}});", boot: true);
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
  Future<void> setVolume(double volume) => _js('player.setVolume(${(volume.clamp(0.0, 1.0) * 100).round()});');
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
  Future<void> dispose() async {
    await _server?.close(force: true);
    await _c?.dispose();
  }
}
