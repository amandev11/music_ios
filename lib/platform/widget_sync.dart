import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../backend/backend.dart';

/// Mirrors the current song into the iOS WidgetKit extension (home screen and lock screen widgets).
/// Android widgets are fed natively by the playback service; other platforms have no widget host.
class WidgetSync {
  WidgetSync(this._backend) {
    if (!_supported) return;
    unawaited(_init());
    _backend.snapshot.addListener(_push);
  }

  static const appGroup = 'group.com.aurora.music';
  static const iosWidgetName = 'AuroraNowPlaying';

  final Backend _backend;
  String? _last;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _init() async {
    try {
      var group = appGroup;
      try {
        // Sideloaded installs get a renamed App Group; the native side reports the real one.
        group = (await const MethodChannel('aurora/pcm').invokeMethod<String>('appGroup')) ?? appGroup;
      } catch (_) {}
      await HomeWidget.setAppGroupId(group);
      _push();
    } catch (e) {
      debugPrint('widget init failed: $e');
    }
  }

  void _push() {
    final s = _backend.snapshot.value;
    final t = s.current;
    final key = '${t?.mediaId}|${s.isPlaying}';
    if (key == _last) return;
    _last = key;
    unawaited(_write(t?.title, t?.artist, t?.artworkUri, s.isPlaying));
  }

  Future<void> _write(String? title, String? artist, String? art, bool playing) async {
    try {
      await HomeWidget.saveWidgetData<String>('title', title ?? '');
      await HomeWidget.saveWidgetData<String>('artist', artist ?? '');
      await HomeWidget.saveWidgetData<String>('art', (art != null && art.startsWith('http')) ? art : '');
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.updateWidget(iOSName: iosWidgetName);
    } catch (e) {
      debugPrint('widget update failed: $e');
    }
  }

  void dispose() => _backend.snapshot.removeListener(_push);
}
