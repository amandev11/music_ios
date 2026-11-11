import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'ui/shell.dart';
import 'ui/theme/theme.dart';

/// Last startup/runtime errors, shown on the error screen so a bug report is one tap away.
final List<String> startupLog = <String>[];

void _record(Object error, StackTrace? stack, {String where = 'app'}) {
  final line = '[$where] $error${stack == null ? '' : '\n$stack'}';
  debugPrint(line);
  if (startupLog.length > 20) startupLog.removeAt(0);
  startupLog.add(line);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nothing below may take the app down silently: log and keep running.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _record(details.exception, details.stack, where: 'flutter');
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    _record(error, stack, where: 'async');
    return true;
  };

  runApp(const _Boot());
}

/// Paints immediately, then brings the engine up. A failure shows a retry screen instead of a crash
/// or an endless blank frame.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late Future<void> _ready = _start();

  Future<void> _start() async {
    // libmpv is only used on desktop/iOS; Android plays through the native Media3 engine.
    if (!kIsWeb && !isNativeAndroid) {
      try {
        MediaKit.ensureInitialized();
      } catch (e, s) {
        _record(e, s, where: 'media_kit');
      }
    }
    await AppController.create().timeout(const Duration(seconds: 20));
  }

  void _retry() => setState(() => _ready = _start());

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Splash();
          if (snap.hasError) {
            _record(snap.error!, snap.stackTrace, where: 'startup');
            return _StartupError(onRetry: _retry);
          }
          return const AuroraApp();
        },
      );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF181819),
        child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Music could not start', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Expanded(child: SingleChildScrollView(child: SelectableText(startupLog.join('\n\n'), style: const TextStyle(fontSize: 12)))),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      );
}

class AuroraApp extends StatelessWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppController.I.settings,
        builder: (context, _) => MaterialApp(
          title: 'Music',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: switch (AppController.I.settings.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          home: const Shell(),
        ),
      );
}
