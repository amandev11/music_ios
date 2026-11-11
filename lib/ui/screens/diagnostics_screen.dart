import 'package:flutter/material.dart';

import '../../app.dart';
import '../../sources/yt_diag.dart';
import '../theme/theme.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _lines = <String>[];
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _lines.clear();
      _running = true;
    });
    await for (final l in runYouTubeDiagnostics(AppController.I.settings)) {
      if (!mounted) return;
      setState(() => _lines.add(l));
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('YouTube diagnostics'), backgroundColor: Colors.transparent),
        backgroundColor: Colors.transparent,
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Checks every YouTube route and shows which one fails. Send a screenshot of the result.',
              style: TextStyle(color: context.secondaryText)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _running ? null : _run, child: Text(_running ? 'Running…' : 'Run test')),
          const SizedBox(height: 16),
          for (final l in _lines) SelectableText(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5)),
        ]),
      );
}
