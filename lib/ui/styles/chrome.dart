import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../theme/styles.dart';
import '../theme/theme.dart';
import '../widgets/glass.dart';
import '../widgets/particle_grid.dart';

/// Page background, one per style. All of them take a little colour from the artwork that is playing.
class StyledBackdrop extends StatelessWidget {
  const StyledBackdrop({super.key, required this.particles});
  final bool particles;

  @override
  Widget build(BuildContext context) {
    final spec = context.spec;
    final light = AppController.I.settings.lightEffects;
    return ValueListenableBuilder<Color?>(
      valueListenable: AppController.I.tint,
      builder: (context, art, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: art ?? context.hue),
        duration: const Duration(milliseconds: 700),
        builder: (context, c, _) {
          final tint = c ?? context.hue;
          final bg = context.bg;
          final dark = context.isDark;
          switch (spec.backdrop) {
            case BackdropKind.artMesh:
              return _Mesh(
                c: art == null ? null : tint,
                particles: particles && !light,
              );
            case BackdropKind.orbitGlow:
              return DecoratedBox(
                decoration: BoxDecoration(color: bg),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.55),
                          radius: 1.0,
                          colors: [
                            Color.lerp(
                              context.hue,
                              tint,
                              0.5,
                            )!.withValues(alpha: dark ? 0.42 : 0.28),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _RingsPainter(
                        context.hue.withValues(alpha: dark ? 0.12 : 0.1),
                      ),
                    ),
                    if (particles && !light) const ParticleGrid(),
                  ],
                ),
              );
            case BackdropKind.sleeveFlat:
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color.lerp(bg, tint, dark ? 0.32 : 0.22)!, bg],
                  ),
                ),
              );
            case BackdropKind.skyGradient:
              final top = dark
                  ? const Color(0xFF123A73)
                  : const Color(0xFF8EC5FF);
              final bottom = dark
                  ? const Color(0xFF050E1F)
                  : const Color(0xFFEAF4FF);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(top, tint, 0.18)!, bottom],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Cloud(
                      const Alignment(-0.8, -0.7),
                      0.9,
                      dark ? 0.08 : 0.55,
                    ),
                    _Cloud(const Alignment(0.9, -0.2), 0.7, dark ? 0.06 : 0.45),
                    _Cloud(const Alignment(-0.2, 0.7), 1.0, dark ? 0.05 : 0.4),
                  ],
                ),
              );
            case BackdropKind.greenMesh:
              final g = Color.lerp(context.hue, tint, 0.35)!;
              return DecoratedBox(
                decoration: BoxDecoration(color: bg),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Cloud(
                      const Alignment(-0.9, -0.6),
                      1.0,
                      dark ? 0.32 : 0.35,
                      color: g,
                    ),
                    _Cloud(
                      const Alignment(0.9, 0.7),
                      0.9,
                      dark ? 0.22 : 0.28,
                      color: HSLColor.fromColor(g)
                          .withHue((HSLColor.fromColor(g).hue + 38) % 360)
                          .toColor(),
                    ),
                    if (particles && !light) const ParticleGrid(),
                  ],
                ),
              );
            case BackdropKind.paper:
              return ColoredBox(color: bg);
          }
        },
      ),
    );
  }
}

class _Mesh extends StatelessWidget {
  const _Mesh({required this.c, required this.particles});
  final Color? c;
  final bool particles;

  @override
  Widget build(BuildContext context) {
    final bg = context.bg;
    final dark = context.isDark;
    final base = c ?? bg;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(bg, base, dark ? 0.55 : 0.35)!,
            bg,
            Color.lerp(bg, base, dark ? 0.25 : 0.15)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -0.5),
                radius: 0.9,
                colors: [
                  base.withValues(alpha: dark ? 0.55 : 0.35),
                  base.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, 0.8),
                radius: 0.8,
                colors: [
                  HSLColor.fromColor(base)
                      .withHue((HSLColor.fromColor(base).hue + 40) % 360)
                      .toColor()
                      .withValues(alpha: dark ? 0.4 : 0.25),
                  base.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          if (particles) const ParticleGrid(),
        ],
      ),
    );
  }
}

class _Cloud extends StatelessWidget {
  const _Cloud(this.at, this.size, this.alpha, {this.color = Colors.white});
  final Alignment at;
  final double size;
  final double alpha;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: at,
        radius: size,
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final c = Offset(size.width / 2, size.height * 0.22);
    final maxR = math.max(size.width, size.height) * 0.9;
    for (var i = 1; i <= 6; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: c,
          width: maxR * i / 3.2,
          height: maxR * i / 3.2 * 0.62,
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.color != color;
}

/// One bottom-navigation item.
class NavTab {
  const NavTab(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Geometry the shell needs to place the mini player above the bar.
class NavMetrics {
  const NavMetrics(this.height, this.sideMargin, this.bottomGap);
  final double height;
  final double sideMargin;
  final double bottomGap;

  static NavMetrics of(NavKind k) => switch (k) {
    NavKind.floatingPill || NavKind.capsuleLabel => const NavMetrics(64, 12, 8),
    NavKind.frostedDock => const NavMetrics(70, 18, 10),
    NavKind.leafDock => const NavMetrics(66, 14, 8),
    NavKind.flatBar => const NavMetrics(58, 0, 0),
    NavKind.textRail => const NavMetrics(52, 0, 0),
    NavKind.liquidGlass => const NavMetrics(68, 20, 10),
  };
}

class StyledNavBar extends StatelessWidget {
  const StyledNavBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelect,
  });
  final List<NavTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final kind = context.spec.nav;
    final inset = MediaQuery.paddingOf(context).bottom;
    final m = NavMetrics.of(kind);
    switch (kind) {
      case NavKind.flatBar:
      case NavKind.textRail:
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: m.height + inset,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.surface2.withValues(
                alpha: kind == NavKind.flatBar ? 0.97 : 0.98,
              ),
              border: Border(
                top: BorderSide(
                  color: context.separator,
                  width: kind == NavKind.textRail ? 1 : 0.5,
                ),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(bottom: inset),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(child: _flat(context, i, kind)),
                ],
              ),
            ),
          ),
        );
      case NavKind.liquidGlass:
        return Positioned(
          left: m.sideMargin,
          right: m.sideMargin,
          bottom: inset + m.bottomGap,
          height: m.height,
          child: _LiquidGlassBar(tabs: tabs, index: index, onSelect: onSelect),
        );
      case NavKind.floatingPill:
      case NavKind.capsuleLabel:
      case NavKind.frostedDock:
      case NavKind.leafDock:
        final radius = switch (kind) {
          NavKind.frostedDock => 36.0,
          NavKind.leafDock => 26.0,
          _ => 32.0,
        };
        return Positioned(
          left: m.sideMargin,
          right: m.sideMargin,
          bottom: inset + m.bottomGap,
          height: m.height,
          child: Glass(
            radius: BorderRadius.circular(radius),
            blur: kind == NavKind.frostedDock ? 42 : 30,
            border: true,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(child: _floating(context, i, kind)),
              ],
            ),
          ),
        );
    }
  }

  Widget _flat(BuildContext context, int i, NavKind kind) {
    final on = i == index;
    final t = tabs[i];
    return InkResponse(
      onTap: () => onSelect(i),
      child: kind == NavKind.textRail
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.6,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? context.accent : context.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2,
                  width: on ? 22 : 0,
                  color: context.hue,
                ),
              ],
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      on ? t.activeIcon : t.icon,
                      size: 24,
                      color: on ? context.hue : context.secondaryText,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: on ? context.accent : context.secondaryText,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 3,
                    width: on ? 26 : 0,
                    color: context.hue,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _floating(BuildContext context, int i, NavKind kind) {
    final on = i == index;
    final t = tabs[i];
    final icon = Icon(
      on ? t.activeIcon : t.icon,
      size: 24,
      color: on
          ? (kind == NavKind.capsuleLabel ? context.onHue : context.hue)
          : context.secondaryText,
    );
    return InkResponse(
      onTap: () => onSelect(i),
      child: switch (kind) {
        NavKind.capsuleLabel => Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: on ? 14 : 8,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: on ? context.hue : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (on) ...[
                  const SizedBox(width: 6),
                  Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.onHue,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        NavKind.leafDock => Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on
                  ? context.hue.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: on ? context.accent : context.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        NavKind.frostedDock => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: on ? 1.15 : 1,
              duration: const Duration(milliseconds: 200),
              child: icon,
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: on ? 18 : 4,
              height: 4,
              decoration: BoxDecoration(
                color: on ? context.hue : context.separator,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
        _ => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              on ? t.activeIcon : t.icon,
              size: 25,
              color: on ? context.accent : context.secondaryText,
            ),
            const SizedBox(height: 2),
            Text(
              t.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: on ? context.accent : context.secondaryText,
              ),
            ),
          ],
        ),
      },
    );
  }
}

/// Liquid Glass tab bar: a blurred, refractive capsule with a glass lens that slides under the active tab.
class _LiquidGlassBar extends StatelessWidget {
  const _LiquidGlassBar({
    required this.tabs,
    required this.index,
    required this.onSelect,
  });
  final List<NavTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final edge = (dark ? Colors.white : Colors.white).withValues(
      alpha: dark ? 0.28 : 0.8,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final n = tabs.length;
        final cell = c.maxWidth / n;
        return ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.16 : 0.55),
                    Colors.white.withValues(alpha: dark ? 0.05 : 0.25),
                  ],
                ),
                border: Border.all(color: edge, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutBack,
                    left: cell * index + 5,
                    top: 5,
                    bottom: 5,
                    width: cell - 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: dark ? 0.32 : 0.9),
                            Colors.white.withValues(alpha: dark ? 0.08 : 0.35),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: dark ? 0.4 : 0.9,
                          ),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.hue.withValues(alpha: 0.25),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: InkResponse(
                            onTap: () => onSelect(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  i == index
                                      ? tabs[i].activeIcon
                                      : tabs[i].icon,
                                  size: 23,
                                  color: i == index
                                      ? context.hue
                                      : context.secondaryText,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tabs[i].label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: i == index
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: i == index
                                        ? context.hue
                                        : context.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
