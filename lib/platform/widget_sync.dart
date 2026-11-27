import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../app.dart';
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
  String _group = appGroup;
  static const _live = MethodChannel('aurora/liveactivity');

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _init() async {
    try {
      var group = appGroup;
      try {
        // Sideloaded installs get a renamed App Group; the native side reports the real one.
        group =
            (await const MethodChannel('aurora/pcm')
                .invokeMethod<String>('appGroup')) ??
            appGroup;
      } catch (_) {}
      _group = group;
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

  Future<void> _write(
    String? title,
    String? artist,
    String? art,
    bool playing,
  ) async {
    try {
      await HomeWidget.saveWidgetData<String>('title', title ?? '');
      await HomeWidget.saveWidgetData<String>('artist', artist ?? '');
      await HomeWidget.saveWidgetData<String>(
        'art',
        (art != null && art.startsWith('http')) ? art : '',
      );
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.updateWidget(iOSName: iosWidgetName);
      // Lock Screen poster (Live Activity): ends itself when nothing is loaded or the setting is off.
      final on = AppController.I.settings.lockPoster;
      await _live.invokeMethod<void>('update', {
        'title': on ? (title ?? '') : '',
        'artist': artist ?? '',
        'playing': playing,
        'art': art ?? '',
        'group': _group,
      });
    } catch (e) {
      debugPrint('widget update failed: $e');
    }
  }

  /// Tells the iPhone widget which look to use (Android is told through the native bridge).
  static Future<void> setTheme(String name) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await HomeWidget.saveWidgetData<String>('theme', name);
      await HomeWidget.updateWidget(iOSName: iosWidgetName);
    } catch (e) {
      debugPrint('widget theme failed: $e');
    }
  }

  void dispose() => _backend.snapshot.removeListener(_push);
}
