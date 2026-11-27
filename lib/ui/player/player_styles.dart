import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/styles.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import 'cassette_art.dart';
import 'vinyl_deck.dart';

/// The accent colour as seen on the always-dark player: near-black accents (Glass in light mode) become white.
Color playerHue(BuildContext context) {
  final h = context.hue;
  return ThemeData.estimateBrightnessForColor(h) == Brightness.dark
      ? Colors.white
      : h;
}

/// Artwork block for each player style. The caller sizes it; the widget draws inside a square.
class PlayerArt extends StatelessWidget {
  const PlayerArt({
    super.key,
    required this.style,
    required this.track,
    required this.playing,
  });
  final PlayerStyle style;
  final Track? track;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case PlayerStyle.vinyl:
        return VinylDeck(track: track, playing: playing);
      case PlayerStyle.orbit:
        return AspectRatio(
          aspectRatio: 1,
          child: _OrbitArt(track: track, playing: playing),
        );
      case PlayerStyle.editorial:
        return AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Transform.translate(
                    offset: const Offset(12, 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: playerHue(context).withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Artwork(track, radius: 0, px: 900, shadow: false),
                ),
              ],
            ),
          ),
        );
      case PlayerStyle.cassette:
        return CassetteArt(track: track, playing: playing);
      case PlayerStyle.grain:
        return AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(track, radius: 0, px: 900, shadow: false),
                const CustomPaint(painter: _GrainPainter()),
              ],
            ),
          ),
        );
      case PlayerStyle.poster:
      case PlayerStyle.classic:
        return Artwork(
          track,
          radius: style == PlayerStyle.poster ? 28 : 14,
          px: 900,
          shadow: true,
        );
    }
  }
}

/// A record that spins while music plays: grooves, the cover as the centre label, a spindle hole.
class _Vinyl extends StatefulWidget {
  const _Vinyl({required this.track, required this.playing});
  final Track? track;
  final bool playing;

  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(_Vinyl old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _spin,
    child: LayoutBuilder(
      builder: (context, c) {
        final d = c.biggest.shortestSide;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: d,
              height: d,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0B0B0B),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: CustomPaint(painter: _GroovePainter()),
            ),
            ClipOval(
              child: SizedBox(
                width: d * 0.42,
                height: d * 0.42,
                child: Artwork(widget.track, radius: 0, px: 400),
              ),
            ),
            Container(
              width: d * 0.05,
              height: d * 0.05,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0B0B0B),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x22FFFFFF);
    for (var f = 0.46; f < 0.98; f += 0.035) {
      canvas.drawCircle(c, r * f, p);
    }
    final sheen = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0x00FFFFFF),
          Color(0x26FFFFFF),
          Color(0x00FFFFFF),
          Color(0x26FFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: const [0, 0.12, 0.5, 0.62, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, sheen);
  }

  @override
  bool shouldRepaint(_GroovePainter old) => false;
}

/// Round artwork inside a progress ring, with a halo that breathes on the beat.
class _OrbitArt extends StatelessWidget {
  const _OrbitArt({required this.track, required this.playing});
  final Track? track;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final b = AppController.I.backend;
    return LayoutBuilder(
      builder: (context, c) {
        final d = c.biggest.shortestSide;
        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: b.frame,
              builder: (_, __) => Container(
                width: d * (0.9 + 0.04 * b.frame.envelope),
                height: d * (0.9 + 0.04 * b.frame.envelope),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: playerHue(context)
                          .withValues(alpha: 0.35 + 0.3 * b.frame.envelope),
                      blurRadius: 50,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<Progress>(
              valueListenable: b.progress,
              builder: (_, p, __) => CustomPaint(
                size: Size.square(d),
                painter: _RingPainter(p.fraction, playerHue(context)),
              ),
            ),
            ClipOval(
              child: SizedBox(
                width: d * 0.8,
                height: d * 0.8,
                child: Artwork(track, radius: 0, px: 800),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color);
  final double f;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 4,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0x33FFFFFF);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    final on = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, on);
    if (f > 0) {
      final a = -math.pi / 2 + math.pi * 2 * f;
      canvas.drawCircle(
        Offset(
          rect.center.dx + rect.width / 2 * math.cos(a),
          rect.center.dy + rect.height / 2 * math.sin(a),
        ),
        7,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.f != f || old.color != color;
}

/// Full-bleed artwork behind the player (Poster style).
class PosterBackdrop extends StatelessWidget {
  const PosterBackdrop({super.key, required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Colors.black),
      Artwork(track, radius: 0, px: 1200),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.35, 0.72, 1],
            colors: [
              Color(0x66000000),
              Color(0x00000000),
              Color(0xB3000000),
              Color(0xF2000000),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The big play/pause control, shaped by the style.
class StyledPlayButton extends StatelessWidget {
  const StyledPlayButton({
    super.key,
    required this.playing,
    required this.buffering,
    required this.onTap,
    required this.style,
    this.size = 76,
  });
  final bool playing;
  final bool buffering;
  final VoidCallback onTap;
  final PlayerStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final filled = style != PlayerStyle.classic;
    final fg = filled ? onColor(playerHue(context)) : Colors.white;
    final Widget inner = buffering && !playing
        ? SizedBox(
            width: size * 0.45,
            height: size * 0.45,
            child: CircularProgressIndicator(color: fg, strokeWidth: 3),
          )
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: filled ? size * 0.6 : size * 0.95,
              color: fg,
            ),
          );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: filled
            ? BoxDecoration(
                color: playerHue(context),
                shape: style == PlayerStyle.editorial
                    ? BoxShape.rectangle
                    : BoxShape.circle,
                borderRadius: style == PlayerStyle.editorial
                    ? BorderRadius.circular(4)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: playerHue(context).withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              )
            : null,
        child: inner,
      ),
    );
  }
}

/// Film grain and a soft vignette over the cover, like a printed poster.
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(7);
    final p = Paint();
    final n = (s.width * s.height / 38).clamp(500, 9000).toInt();
    for (var i = 0; i < n; i++) {
      p.color = Color.fromRGBO(
        r.nextBool() ? 255 : 0,
        r.nextBool() ? 255 : 0,
        255,
        0.07 + r.nextDouble() * 0.08,
      );
      canvas.drawCircle(
        Offset(r.nextDouble() * s.width, r.nextDouble() * s.height),
        0.7,
        p,
      );
    }
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x00000000), Color(0x66000000)],
          stops: const [0.6, 1.0],
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter o) => false;
}
