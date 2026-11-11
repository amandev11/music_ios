import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';

/// Apple-style thin scrubber that thickens while dragged. Position comes from the extrapolating
/// clock; while the thumb is down it shows the finger, and the seek is sent on release only.
class Scrubber extends StatefulWidget {
  const Scrubber({super.key, this.waveform});
  final List<double>? waveform;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final clock = AppController.I.clock;
    final backend = AppController.I.backend;
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final dur = clock.durationMs;
        final f = _drag ?? clock.fraction;
        final pos = (_drag != null ? _drag! * dur : clock.positionMs.toDouble()).round();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          LayoutBuilder(builder: (context, c) {
            void setFrom(double dx) => setState(() => _drag = (dx / c.maxWidth).clamp(0.0, 1.0));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => setFrom(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => setFrom(d.localPosition.dx),
              onHorizontalDragEnd: (_) {
                final target = ((_drag ?? 0) * dur).round();
                setState(() => _drag = null);
                backend.seek(target);
              },
              onTapUp: (d) => backend.seek(((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0) * dur).round()),
              child: SizedBox(
                height: 28,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: _drag != null ? 10 : 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(fit: StackFit.expand, children: [
                        const ColoredBox(color: Color(0x4DFFFFFF)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: f.clamp(0.0, 1.0),
                          child: const ColoredBox(color: Color(0xE6FFFFFF)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(formatTime(pos), style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF), fontFeatures: [FontFeature.tabularFigures()])),
            Text('-${formatTime((dur - pos).clamp(0, 1 << 30))}',
                style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF), fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ]);
      },
    );
  }
}
