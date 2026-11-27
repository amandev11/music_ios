import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/models.dart';
import '../widgets/artwork.dart';

/// A cassette tape: label with the cover, a window with two reels that turn while playing.
class CassetteArt extends StatefulWidget {
  const CassetteArt({super.key, required this.track, required this.playing});
  final Track? track;
  final bool playing;

  @override
  State<CassetteArt> createState() => _CassetteArtState();
}

class _CassetteArtState extends State<CassetteArt>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _a = ValueNotifier<double>(0);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _a.dispose();
    super.dispose();
  }

  void _tick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = t;
    if (widget.playing) _a.value = (_a.value + dt * 2.6) % (math.pi * 2);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.biggest.width;
        final h = w * 0.64;
        return Center(
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.04),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B3B40), Color(0xFF18181B)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Paper label with the cover.
                Positioned(
                  left: w * 0.06,
                  right: w * 0.06,
                  top: h * 0.07,
                  height: h * 0.5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(w * 0.02),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0xFFEDE6D6)),
                        Artwork(
                          widget.track,
                          radius: 0,
                          px: 700,
                          shadow: false,
                        ),
                        Container(color: const Color(0x33EDE6D6)),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: h * 0.14,
                          child: const ColoredBox(color: Color(0xCCEDE6D6)),
                        ),
                      ],
                    ),
                  ),
                ),
                // Window with reels.
                Positioned(
                  left: w * 0.22,
                  right: w * 0.22,
                  top: h * 0.63,
                  height: h * 0.25,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C0C0E),
                      borderRadius: BorderRadius.circular(h * 0.125),
                      border: Border.all(color: const Color(0x55FFFFFF)),
                    ),
                    child: ValueListenableBuilder<double>(
                      valueListenable: _a,
                      builder: (_, a, __) => CustomPaint(painter: _Reels(a)),
                    ),
                  ),
                ),
                // Screws.
                for (final o in const [
                  Offset(0.03, 0.05),
                  Offset(0.97, 0.05),
                  Offset(0.03, 0.95),
                  Offset(0.97, 0.95),
                ])
                  Positioned(
                    left: w * o.dx - 4,
                    top: h * o.dy - 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF777780),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Reels extends CustomPainter {
  _Reels(this.a);
  final double a;

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.height * 0.38;
    for (final cx in [s.width * 0.25, s.width * 0.75]) {
      final c = Offset(cx, s.height / 2);
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE9E9EE));
      canvas.drawCircle(c, r * 0.55, Paint()..color = const Color(0xFF0C0C0E));
      for (var i = 0; i < 6; i++) {
        final t = a + i * math.pi / 3;
        canvas.drawLine(
          c + Offset(math.cos(t), math.sin(t)) * (r * 0.5),
          c + Offset(math.cos(t), math.sin(t)) * (r * 0.95),
          Paint()
            ..color = const Color(0xFFE9E9EE)
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Reels o) => o.a != a;
}
