import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../widgets/artwork.dart';

/// A turntable seen from above: a wooden plinth, a platter with a spinning record whose label is the
/// album cover, a start/stop knob with a lamp, and a tonearm that swings out of its rest, lowers onto
/// the lead-in groove and creeps toward the centre as the song plays. It lifts back to rest on pause.
class VinylDeck extends StatefulWidget {
  const VinylDeck({super.key, required this.track, required this.playing});
  final Track? track;
  final bool playing;

  @override
  State<VinylDeck> createState() => _VinylDeckState();
}

class _VinylDeckState extends State<VinylDeck>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _angle = ValueNotifier<double>(0);
  double _omega = 0; // radians per second
  Duration _last = Duration.zero;

  // 33 1/3 rpm = 3.49 rad/s.
  static const _fullSpeed = 3.49;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  void _tick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = t;
    // The platter spins up in about a second and coasts down more slowly, like a real motor.
    final target = widget.playing ? _fullSpeed : 0.0;
    final rate = widget.playing ? 3.0 : 1.2;
    _omega += (target - _omega) * (1 - math.exp(-rate * dt));
    if (_omega < 0.002 && !widget.playing) {
      _omega = 0;
      return;
    }
    _angle.value = (_angle.value + _omega * dt) % (math.pi * 2);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.biggest.shortestSide;
        final center = Offset(w * 0.43, w * 0.55);
        final record = w * 0.335;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PlinthPainter(
                  playing: widget.playing,
                  center: center,
                ),
              ),
            ),
            // Grooves and sheen stay put: a real record looks the same while it turns.
            Positioned(
              left: center.dx - record,
              top: center.dy - record,
              width: record * 2,
              height: record * 2,
              child: const CustomPaint(painter: _RecordPainter()),
            ),
            // The label turns, so you can see the speed.
            Positioned(
              left: center.dx - record * 0.38,
              top: center.dy - record * 0.38,
              width: record * 0.76,
              height: record * 0.76,
              child: ValueListenableBuilder<double>(
                valueListenable: _angle,
                builder: (_, a, child) =>
                    Transform.rotate(angle: a, child: child),
                child: _Label(track: widget.track),
              ),
            ),
            Positioned.fill(
              child: ListenableBuilder(
                listenable: AppController.I.clock,
                builder: (context, _) {
                  final f = AppController.I.clock.fraction.clamp(0.0, 1.0);
                  // 0.5 % steps: the arm eases between them instead of twitching with every sample.
                  final q = (f * 200).roundToDouble() / 200;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.playing ? q : -1),
                    duration: widget.playing
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 1100),
                    curve: Curves.easeInOutCubic,
                    builder: (context, p, _) => CustomPaint(
                      painter: _ArmPainter(
                        center: center,
                        progress: p,
                        down: widget.playing,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      ClipOval(child: Artwork(track, radius: 0, px: 400)),
      // Spindle hole and a ring around the label edge.
      Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFD7D7DB),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x66000000), width: 1.5),
        ),
      ),
    ],
  );
}

class _PlinthPainter extends CustomPainter {
  _PlinthPainter({required this.playing, required this.center});
  final bool playing;
  final Offset center;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final body = RRect.fromRectAndRadius(
      Offset.zero & s,
      Radius.circular(w * 0.045),
    );
    // Walnut-like plinth with a soft top light.
    canvas.drawShadow(
      Path()..addRRect(body),
      const Color(0xFF000000),
      18,
      true,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A382B), Color(0xFF2B1F17), Color(0xFF1C1410)],
        ).createShader(Offset.zero & s),
    );
    // Wood grain: fine, slightly wavy horizontal lines.
    final grain = Paint()
      ..color = const Color(0x10FFFFFF)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRRect(body);
    for (var y = 3.0; y < s.height; y += 5.5) {
      final p = Path()..moveTo(0, y);
      for (var x = 0.0; x <= w; x += w / 10) {
        p.lineTo(x, y + math.sin(x * 0.03 + y * 0.2) * 1.4);
      }
      canvas.drawPath(p, grain);
    }
    canvas.restore();
    // Bevelled edge.
    canvas.drawRRect(
      body.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x33FFFFFF),
    );

    // Platter: dark metal ring, then the slip mat.
    final r = w * 0.355;
    canvas.drawCircle(
      center.translate(2, 4),
      r + 3,
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      r + 3,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF8A8A90),
            Color(0xFF3C3C40),
            Color(0xFFB4B4BA),
            Color(0xFF3C3C40),
            Color(0xFF8A8A90),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r + 3)),
    );
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF111113));

    // Start/stop knob with its lamp, and the speed marking.
    final knob = Offset(w * 0.1, w * 0.9);
    canvas.drawCircle(
      knob.translate(1, 2),
      w * 0.045,
      Paint()..color = const Color(0x88000000),
    );
    canvas.drawCircle(
      knob,
      w * 0.045,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE8E8EC), Color(0xFF8A8A90)],
        ).createShader(Rect.fromCircle(center: knob, radius: w * 0.045)),
    );
    canvas.drawLine(
      knob,
      knob.translate(0, -w * 0.034),
      Paint()
        ..color = const Color(0xFF222226)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final lamp = knob.translate(w * 0.085, 0);
    canvas.drawCircle(
      lamp,
      w * 0.012,
      Paint()
        ..color = playing ? const Color(0xFF3DDC84) : const Color(0xFF4A2A2A),
    );
    if (playing) {
      canvas.drawCircle(
        lamp,
        w * 0.03,
        Paint()
          ..color = const Color(0x553DDC84)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    _text(
      canvas,
      '33',
      Offset(w * 0.2, w * 0.885),
      w * 0.03,
      const Color(0xCCFFFFFF),
    );
    _text(
      canvas,
      'KEYSTONE',
      Offset(w * 0.64, w * 0.89),
      w * 0.032,
      const Color(0x99FFFFFF),
      spacing: 3,
    );
  }

  void _text(
    Canvas c,
    String t,
    Offset at,
    double size,
    Color color, {
    double spacing = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: spacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(_PlinthPainter old) => old.playing != playing;
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0A0A0B));
    // Grooves: many hairline rings with a little variation, like real track gaps.
    final g = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 70; i++) {
      final rr = r * (0.42 + 0.57 * i / 70);
      g
        ..strokeWidth = 0.6
        ..color = Color.fromRGBO(
          255,
          255,
          255,
          0.035 + 0.03 * ((i * 37) % 7) / 7,
        );
      canvas.drawCircle(c, rr, g);
    }
    // Wider dark bands between tracks.
    for (final f in const [0.56, 0.7, 0.83]) {
      canvas.drawCircle(
        c,
        r * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = const Color(0xCC000000),
      );
    }
    // Two opposite light sheens, fixed in space.
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const SweepGradient(
          transform: GradientRotation(-0.9),
          colors: [
            Color(0x00FFFFFF),
            Color(0x33FFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x26FFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, 0.08, 0.18, 0.5, 0.58, 0.68, 1.0],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x44FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_RecordPainter old) => false;
}

class _ArmPainter extends CustomPainter {
  _ArmPainter({
    required this.center,
    required this.progress,
    required this.down,
  });
  final Offset center;

  /// 0 = outer groove, 1 = run-out; negative = parked on the rest.
  final double progress;
  final bool down;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final pivot = Offset(w * 0.9, w * 0.17);
    final armLen = w * 0.66;
    final record = w * 0.335;

    // Stylus distance from the platter centre for the current progress; parked is well off the record.
    final rOut = record * 0.93, rIn = record * 0.47, rRest = record * 1.45;
    final r = progress < 0
        ? rRest +
              (progress + 1) *
                  0 // parked
        : rOut + (rIn - rOut) * progress;
    // While the arm is crossing from the rest to the record, `progress` is mid-tween (-1 .. 0).
    final rr = progress >= 0 ? r : rRest + (rOut - rRest) * (progress + 1);

    final d = (center - pivot).distance;
    final phi = math.atan2(center.dy - pivot.dy, center.dx - pivot.dx);
    final cosv = ((d * d + armLen * armLen - rr * rr) / (2 * d * armLen)).clamp(
      -1.0,
      1.0,
    );
    final theta = phi + math.acos(cosv);
    final tip = pivot + Offset(math.cos(theta), math.sin(theta)) * armLen;
    final dir = Offset(math.cos(theta), math.sin(theta));
    final lowered = progress >= 0;

    // Rest post.
    final restTheta =
        phi +
        math.acos(
          ((d * d + armLen * armLen - rRest * rRest) / (2 * d * armLen)).clamp(
            -1.0,
            1.0,
          ),
        );
    final restTip =
        pivot + Offset(math.cos(restTheta), math.sin(restTheta)) * armLen;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: restTip.translate(-w * 0.012, w * 0.03),
          width: w * 0.04,
          height: w * 0.05,
        ),
        Radius.circular(w * 0.01),
      ),
      Paint()..color = const Color(0xFF3A3A3E),
    );

    // Shadow: sits close when lowered and drifts away when the arm is lifted.
    final lift = lowered ? 0.0 : 1.0;
    final shadowOff = Offset(
      w * (0.008 + 0.012 * lift),
      w * (0.012 + 0.016 * lift),
    );
    final shadow = Paint()
      ..color = Color.fromRGBO(0, 0, 0, 0.42 - 0.12 * lift)
      ..strokeWidth = w * 0.016
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        w * (0.008 + 0.01 * lift),
      );
    canvas.drawLine(pivot + shadowOff, tip + shadowOff, shadow);

    // Counterweight behind the pivot.
    final back = pivot - dir * (w * 0.1);
    canvas.drawLine(
      pivot,
      back,
      Paint()
        ..color = const Color(0xFF9A9AA0)
        ..strokeWidth = w * 0.016
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      back + dir * (w * 0.01),
      back - dir * (w * 0.035),
      Paint()
        ..color = const Color(0xFF55555B)
        ..strokeWidth = w * 0.05
        ..strokeCap = StrokeCap.round,
    );

    // Arm tube, a metallic gradient.
    final tube = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.014
      ..shader = const LinearGradient(
        colors: [Color(0xFFE6E6EA), Color(0xFF8C8C92)],
      ).createShader(Rect.fromPoints(pivot, tip));
    final shell = tip - dir * (w * 0.045);
    canvas.drawLine(pivot, shell, tube);

    // Headshell with the cartridge, angled a little off the arm axis.
    final side = Offset(-dir.dy, dir.dx);
    final p = Path()
      ..moveTo((shell + side * (w * 0.016)).dx, (shell + side * (w * 0.016)).dy)
      ..lineTo((tip + side * (w * 0.011)).dx, (tip + side * (w * 0.011)).dy)
      ..lineTo((tip - side * (w * 0.011)).dx, (tip - side * (w * 0.011)).dy)
      ..lineTo((shell - side * (w * 0.016)).dx, (shell - side * (w * 0.016)).dy)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF1B1B1E));
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66FFFFFF),
    );
    canvas.drawCircle(
      tip - dir * (w * 0.006),
      w * 0.0045,
      Paint()
        ..color = lowered ? const Color(0xFFFF8A3D) : const Color(0xFFB0B0B5),
    );

    // Pivot base with a bearing cap on top.
    canvas.drawCircle(
      pivot.translate(1.5, 2.5),
      w * 0.052,
      Paint()..color = const Color(0x77000000),
    );
    canvas.drawCircle(
      pivot,
      w * 0.05,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFD9D9DE), Color(0xFF5A5A60)],
          center: Alignment(-0.3, -0.4),
        ).createShader(Rect.fromCircle(center: pivot, radius: w * 0.05)),
    );
    canvas.drawCircle(
      pivot,
      w * 0.02,
      Paint()..color = const Color(0xFF2A2A2E),
    );
  }

  @override
  bool shouldRepaint(_ArmPainter old) =>
      old.progress != progress || old.down != down;
}
