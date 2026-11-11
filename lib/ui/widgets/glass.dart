import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../theme/theme.dart';

/// Mist glass: backdrop blur under a 50 %-opacity tint. The tint is the current artwork colour mixed
/// into a neutral base, so every glass surface in the app picks up the colour of what is playing.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = BorderRadius.zero,
    this.blur = 18,
    this.tint,
    this.border = false,
  });

  final Widget child;
  final BorderRadius radius;
  final double blur;

  /// Overrides the artwork-derived tint (opacity is still forced to 50 %).
  final Color? tint;
  final bool border;

  static Color base(BuildContext context, Color? art) {
    final dark = context.isDark;
    final neutral = dark ? const Color(0xFF1A1A1C) : const Color(0xFFF6F6F9);
    if (art == null) return neutral;
    return Color.lerp(neutral, art, dark ? 0.38 : 0.28)!;
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return ValueListenableBuilder<Color?>(
      valueListenable: AppController.I.tint,
      builder: (context, art, _) {
        final fill = (tint ?? base(context, art)).withValues(alpha: 0.5);
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.09 : 0.35),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
                border: border ? Border.all(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.55), width: 0.8) : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
