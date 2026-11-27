import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iPhone output routing: the current route and Apple's own picker (AirPlay, Bluetooth, speaker).
class AudioRoute {
  static const _c = MethodChannel('aurora/audioroute');

  static bool get isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<({String name, String type})> current() async {
    try {
      final m = await _c.invokeMapMethod<String, dynamic>('current');
      return (
        name: '${m?['name'] ?? 'iPhone'}',
        type: '${m?['type'] ?? 'speaker'}',
      );
    } catch (_) {
      return (name: 'iPhone', type: 'speaker');
    }
  }

  static Future<bool> showPicker() async {
    try {
      return (await _c.invokeMethod<bool>('showPicker')) ?? false;
    } catch (_) {
      return false;
    }
  }
}
