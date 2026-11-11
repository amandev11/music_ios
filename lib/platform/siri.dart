import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../backend/backend.dart';

/// "Hey Siri, play <song> on Music": the native App Intent hands over the spoken text; this searches and plays it.
class SiriBridge with WidgetsBindingObserver {
  SiriBridge(this._backend) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'siri' && call.arguments is String) {
        unawaited(_play(call.arguments as String));
        return true;
      }
      return null;
    });
    WidgetsBinding.instance.addObserver(this);
    unawaited(_take());
    // A cold start through Siri can finish launching a moment after the intent ran.
    Timer(const Duration(seconds: 2), () => unawaited(_take()));
  }

  static const _ch = MethodChannel('aurora/pcm');
  final Backend _backend;
  String? _lastQuery;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_take());
  }

  Future<void> _take() async {
    try {
      final q = await _ch.invokeMethod<String>('takeSiri');
      if (q != null && q.trim().isNotEmpty) await _play(q);
    } catch (_) {}
  }

  Future<void> _play(String query) async {
    final q = query.trim();
    // The same request can arrive by notification and by the stored copy: play it once.
    if (q == _lastQuery && DateTime.now().difference(_lastAt) < const Duration(seconds: 5)) return;
    _lastQuery = q;
    _lastAt = DateTime.now();
    try {
      var found = await _backend.searchRemote(q);
      if (found.isEmpty) found = await _backend.searchLocal(q);
      if (found.isEmpty) return;
      await _backend.playTracks(found, 0);
    } catch (e) {
      debugPrint('Siri play failed: $e');
    }
  }
}
