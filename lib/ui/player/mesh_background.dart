import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../backend/backend.dart';
import '../../core/models.dart';
import '../widgets/artwork.dart';

/// Slowly drifting colour blobs derived from the artwork, pulsing with the beat when a beat engine
/// is available. Painted on the GPU with plain radial gradients, so it works on every platform.
class MeshBackground extends StatefulWidget {
  const MeshBackground({super.key, required this.track, required this.frame});
  final Track? track;
  final AudioFrame frame;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground> with TickerProviderStateMixin {
  // Slow drift advanced at ~15 fps by a timer instead of a 60 fps ticker: the blobs move 1 % per second.
  final _drift = _Drift();
  Timer? _driftTimer;
  List<Color> _from = ArtworkColors.fallback;
  List<Color> _to = ArtworkColors.fallback;
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: 1);

  @override
  void initState() {
    super.initState();
    _driftTimer = Timer.periodic(const Duration(milliseconds: 66), (_) => _drift.advance(0.066 / 40));
    _load();
  }

  @override
  void didUpdateWidget(MeshBackground old) {
    super.didUpdateWidget(old);
    if (old.track?.artKey != widget.track?.artKey) _load();
  }

  Future<void> _load() async {
    final colors = await ArtworkColors.of(widget.track);
    if (!mounted) return;
    _from = _lerp(_from, _to, _fade.value);
    _to = colors;
    _fade.forward(from: 0);
  }

  List<Color> _lerp(List<Color> a, List<Color> b, double t) =>
      List.generate(4, (i) => Color.lerp(a[i % a.length], b[i % b.length], t)!);

  @override
  void dispose() {
    _driftTimer?.cancel();
    _drift.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _MeshPainter(
            drift: _drift,
            fade: _fade,
            frame: widget.frame,
            colors: () => _lerp(_from, _to, Curves.easeInOut.transform(_fade.value)),
          ),
          size: Size.infinite,
        ),
      );
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.drift, required this.fade, required this.frame, required this.colors})
      : super(repaint: Listenable.merge([drift, fade]));

  final _Drift drift;
  final Animation<double> fade;
  final AudioFrame frame;
  final List<Color> Function() colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors();
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(c[0], Colors.black, 0.35)!,
            Color.lerp(c[1 % c.length], Colors.black, 0.5)!,
            Color.lerp(c[2 % c.length], Colors.black, 0.6)!,
          ],
        ).createShader(rect),
    );

    final t = drift.value * 2 * pi;
    final pulse = 1 + 0.08 * frame.envelope + 0.05 * frame.rms;
    final longest = max(size.width, size.height);
    final blobs = [
      (Offset(0.25 + 0.15 * sin(t), 0.2 + 0.1 * cos(t * 1.3)), c[0], 0.75),
      (Offset(0.8 + 0.1 * cos(t * 0.8), 0.35 + 0.15 * sin(t)), c[1 % c.length], 0.65),
      (Offset(0.3 + 0.12 * cos(t * 1.1), 0.75 + 0.1 * sin(t * 0.9)), c[3 % c.length], 0.7),
      (Offset(0.75 + 0.1 * sin(t * 1.4), 0.85 + 0.08 * cos(t)), c[0], 0.55),
    ];
    for (final (pos, color, r) in blobs) {
      final center = Offset(pos.dx * size.width, pos.dy * size.height);
      final radius = longest * r * pulse;
      final paint = Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
    // Keep text legible regardless of artwork brightness.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x14000000), Color(0x66000000)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) => false;
}

/// A looping 0..1 value that notifies listeners when advanced.
class _Drift extends ChangeNotifier {
  double value = 0;
  void advance(double d) {
    value = (value + d) % 1;
    notifyListeners();
  }
}
