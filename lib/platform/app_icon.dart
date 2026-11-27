import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Home-screen icon switching. Android flips activity-aliases (and can swap the launcher label too);
/// iOS uses alternate icons (the label cannot change there). Desktop and web have no switchable icon.
class AppIconPlatform {
  static const _ch = MethodChannel('aurora/appicon');

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Only Android can show the icon's own name as the launcher label.
  static bool get canRename =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> set(String id, {bool named = false}) async {
    if (!supported) return false;
    try {
      return (await _ch.invokeMethod<bool>('set', {
            'id': id,
            'named': named && canRename,
          })) ??
          false;
    } catch (e) {
      debugPrint('App icon switch failed: $e');
      return false;
    }
  }
}
