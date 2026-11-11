import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app.dart';
import '../theme/theme.dart';

/// Pointer position in global coordinates, fed by a root-level Listener (mouse hover, touch, pen).
class ParticleField {
  static final pointer = ValueNotifier<Offset?>(null);
}

/// A grid of dots that drift away from the pointer with eased displacement and brighten with proximity.
/// Pure CustomPainter, so it runs identically on every platform including the web build. It stops its
/// ticker once every dot has settled and no pointer is near.
class ParticleGrid extends StatefulWidget {
  const ParticleGrid({super.key, this.spacing = 34, this.radius = 150, this.maxPush = 30});
  final double spacing;
  final double radius;
  final double maxPush;

  @override
  State<ParticleGrid> createState() => _ParticleGridState();
}

class _ParticleGridState extends State<ParticleGrid> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Float32List _dx = Float32List(0), _dy = Float32List(0), _glow = Float32List(0);
  Size _size = Size.zero;
  int _cols = 0, _rows = 0;
  Offset? _local;
  final _repaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    ParticleField.pointer.addListener(_onPointer);
  }

  @override
  void dispose() {
    ParticleField.pointer.removeListener(_onPointer);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onPointer() {
    final box = context.findRenderObject();
    final g = ParticleField.pointer.value;
    _local = (box is RenderBox && box.attached && g != null) ? box.globalToLocal(g) : null;
    if (!_ticker.isActive) _ticker.start();
  }

  void _layout(Size s) {
    if (s == _size) return;
    _size = s;
    _cols = (s.width / widget.spacing).ceil() + 1;
    _rows = (s.height / widget.spacing).ceil() + 1;
    final n = _cols * _rows;
    _dx = Float32List(n);
    _dy = Float32List(n);
    _glow = Float32List(n);
  }

  final _active = <int>{};

  void _tick(Duration _) {
    final p = _local;
    final r = widget.radius;
    final sp = widget.spacing;
    // Only dots near the pointer or still settling are touched: a few dozen, not the whole grid.
    final todo = <int>{..._active};
    if (p != null) {
      final reach = r + 1;
      final i0 = ((p.dx - reach) / sp).floor().clamp(0, _cols - 1), i1 = ((p.dx + reach) / sp).ceil().clamp(0, _cols - 1);
      final j0 = ((p.dy - reach) / sp).floor().clamp(0, _rows - 1), j1 = ((p.dy + reach) / sp).ceil().clamp(0, _rows - 1);
      for (var j = j0; j <= j1; j++) {
        for (var i = i0; i <= i1; i++) {
          todo.add(j * _cols + i);
        }
      }
    }
    _active.clear();
    for (final k in todo) {
      final i = k % _cols, j = k ~/ _cols;
      final bx = i * sp, by = j * sp;
      var tx = 0.0, ty = 0.0, tg = 0.0;
      if (p != null) {
        final vx = bx - p.dx, vy = by - p.dy;
        final d = sqrt(vx * vx + vy * vy);
        if (d < r && d > 0.001) {
          final f = 1 - d / r;
          final push = f * f * widget.maxPush;
          tx = vx / d * push;
          ty = vy / d * push;
          tg = f;
        }
      }
      _dx[k] += (tx - _dx[k]) * 0.14;
      _dy[k] += (ty - _dy[k]) * 0.14;
      _glow[k] += (tg - _glow[k]) * 0.10;
      if ((tx - _dx[k]).abs() > 0.02 || (ty - _dy[k]).abs() > 0.02 || (tg - _glow[k]).abs() > 0.004) {
        _active.add(k);
      } else {
        _dx[k] = 0;
        _dy[k] = 0;
        _glow[k] = 0;
      }
    }
    _repaint.value++;
    if (_active.isEmpty && p == null) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        _layout(Size(c.maxWidth, c.maxHeight));
        return ValueListenableBuilder<Color?>(
          valueListenable: AppController.I.tint,
          builder: (context, art, _) => RepaintBoundary(
            child: CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _GridPainter(this, Color.lerp(accent, art ?? accent, 0.55)!, _repaint),
            ),
          ),
        );
      }),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.s, this.color, Listenable repaint) : super(repaint: repaint);
  final _ParticleGridState s;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sp = s.widget.spacing;
    // Resting dots in one batched call; only the few displaced ones are drawn individually.
    final idle = <double>[];
    for (var j = 0; j < s._rows; j++) {
      for (var i = 0; i < s._cols; i++) {
        final k = j * s._cols + i;
        if (!s._active.contains(k)) {
          idle.add(i * sp);
          idle.add(j * sp);
        }
      }
    }
    final base = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;
    canvas.drawRawPoints(PointMode.points, Float32List.fromList(idle), base);
    final paint = Paint();
    for (final k in s._active) {
      final i = k % s._cols, j = k ~/ s._cols;
      final g = s._glow[k];
      final a = 0.10 + 0.80 * pow(g, 1.4);
      paint.color = color.withValues(alpha: a.toDouble().clamp(0.0, 1.0));
      canvas.drawCircle(Offset(i * sp + s._dx[k], j * sp + s._dy[k]), 1.15 + 1.5 * g, paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
