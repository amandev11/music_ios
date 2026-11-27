import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../backend/backend.dart';
import '../../core/models.dart';
import 'player_styles.dart' show playerHue;
import '../theme/theme.dart';

/// Apple-style thin scrubber that thickens while dragged. Position comes from the extrapolating
/// clock; while the thumb is down it shows the finger, and the seek is sent on release only.
class Scrubber extends StatefulWidget {
  const Scrubber({super.key, this.waveform});
  final List<double>? waveform;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  /// White on the Glass look; the accent colour on the other styles.
  Color _fill(BuildContext context) =>
      context.spec.defaultHue == null &&
          AppController.I.settings.accentIndex == 0
      ? Colors.white
      : playerHue(context);

  double? _drag;

  @override
  Widget build(BuildContext context) {
    final clock = AppController.I.clock;
    final backend = AppController.I.backend;
    return ValueListenableBuilder<List<double>>(
      valueListenable: AppController.I.waveform,
      builder: (context, wave, _) => _build(
        context,
        clock,
        backend,
        AppController.I.settings.waveformBar && wave.isNotEmpty ? wave : null,
      ),
    );
  }

  /// Thin track + round thumb that grows while held, with a floating time bubble (Instagram / WhatsApp style).
  Widget _thumbTrack(double width, double f, int posMs) {
    final dragging = _drag != null;
    final thumb = dragging ? 20.0 : 13.0;
    final x = (f * width).clamp(0.0, width);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        Positioned.fill(
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: dragging ? 5 : 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0x4DFFFFFF)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: f,
                      child: ColoredBox(color: _fill(context)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: x - thumb / 2,
          top: 0,
          bottom: 0,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: thumb,
              height: thumb,
              decoration: BoxDecoration(
                color: _fill(context),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x66000000),
                    blurRadius: dragging ? 8 : 3,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (dragging)
          Positioned(
            left: (x - 24).clamp(0.0, (width - 48).clamp(0.0, double.infinity)),
            top: -30,
            child: Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xE6222222),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                formatTime(posMs),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _build(
    BuildContext context,
    PositionClock clock,
    Backend backend,
    List<double>? wave,
  ) {
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final dur = clock.durationMs;
        final f = _drag ?? clock.fraction;
        final pos = (_drag != null ? _drag! * dur : clock.positionMs.toDouble())
            .round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                void setFrom(double dx) =>
                    setState(() => _drag = (dx / c.maxWidth).clamp(0.0, 1.0));
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) => setFrom(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => setFrom(d.localPosition.dx),
                  onHorizontalDragEnd: (_) {
                    final target = ((_drag ?? 0) * dur).round();
                    setState(() => _drag = null);
                    backend.seek(target);
                  },
                  onTapUp: (d) => backend.seek(
                    ((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0) * dur)
                        .round(),
                  ),
                  child: SizedBox(
                    height: wave != null && wave.isNotEmpty ? 44 : 28,
                    child: wave != null && wave.isNotEmpty
                        ? CustomPaint(
                            size: Size.infinite,
                            painter: _WavePainter(
                              wave,
                              f.clamp(0.0, 1.0),
                              _drag != null,
                            ),
                          )
                        : (AppController.I.settings.thumbSlider
                              ? _thumbTrack(c.maxWidth, f.clamp(0.0, 1.0), pos)
                              : Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    height: _drag != null ? 10 : 5,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          const ColoredBox(
                                            color: Color(0x4DFFFFFF),
                                          ),
                                          FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: f.clamp(0.0, 1.0),
                                            child: ColoredBox(
                                              color: _fill(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )),
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatTime(pos),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0x99FFFFFF),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '-${formatTime((dur - pos).clamp(0, 1 << 30))}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0x99FFFFFF),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.bars, this.progress, this.dragging);
  final List<double> bars;
  final double progress;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    final slot = size.width / n;
    final w = (slot * 0.62).clamp(1.5, 5.0);
    final done = Paint()..color = const Color(0xF2FFFFFF);
    final todo = Paint()..color = const Color(0x4DFFFFFF);
    final mid = size.height / 2;
    final maxH = size.height * (dragging ? 1.0 : 0.86);
    for (var i = 0; i < n; i++) {
      final h = (bars[i] * maxH).clamp(3.0, maxH);
      final x = i * slot + slot / 2;
      final played = (i + 0.5) / n <= progress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, mid), width: w, height: h),
          Radius.circular(w / 2),
        ),
        played ? done : todo,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.progress != progress || o.bars != bars || o.dragging != dragging;
}
