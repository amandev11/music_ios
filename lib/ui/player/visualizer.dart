import 'dart:math';

import 'package:flutter/material.dart';

import '../../backend/backend.dart';

/// Mirrored spectrum bars. With the native engine the bars follow the real PCM spectrum and flash
/// on detected beats; elsewhere they are the backend's placeholder animation.
class BeatVisualizer extends StatelessWidget {
  const BeatVisualizer({super.key, required this.frame, this.height = 44, this.color = Colors.white});
  final AudioFrame frame;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _BarsPainter(frame, color)),
      );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.frame, this.color) : super(repaint: frame);
  final AudioFrame frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = frame.spectrum.length;
    final gap = 3.0;
    final w = (size.width - gap * (n - 1)) / n;
    final mid = size.height / 2;
    final flash = frame.envelope;
    final paint = Paint()..color = color.withValues(alpha: 0.55 + 0.4 * flash);
    for (var i = 0; i < n; i++) {
      final v = frame.spectrum[i].clamp(0.0, 1.0);
      final h = max(3.0, v * size.height * (0.85 + 0.15 * flash));
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h / 2, w, h), Radius.circular(w / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => false;
}

/// Four dots for the bar position; the active one is the current beat, the first is the downbeat.
class BeatDots extends StatelessWidget {
  const BeatDots({super.key, required this.frame});
  final AudioFrame frame;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 10,
        width: 80,
        child: CustomPaint(painter: _DotsPainter(frame)),
      );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.frame) : super(repaint: frame);
  final AudioFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final n = frame.beatsPerBar.clamp(2, 8);
    final step = size.width / n;
    for (var i = 0; i < n; i++) {
      final active = frame.beatLocked && i == frame.beatInBar;
      final r = active ? 3.5 + 1.5 * frame.envelope : 2.5;
      canvas.drawCircle(
        Offset(step * (i + 0.5), size.height / 2),
        r,
        Paint()..color = Colors.white.withValues(alpha: active ? 0.95 : 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}
