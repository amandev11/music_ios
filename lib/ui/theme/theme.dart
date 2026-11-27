import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import 'styles.dart';

/// Palette constants (class name kept for older call sites).
class Apple {
  static const darkBg = Color(0xFF181819);
  static const lightBg = Color(0xFFF3F3F6);
  static const darkSurface = Color(0xFF2A2A2C);
  static const lightSurface = Color(0xFFE6E6EB);
  // Fallbacks for non-themed code; prefer the BuildContext getters below.
  static const red = Color(0xFFFFFFFF);
  static const pink = Color(0xFFFFFFFF);
}

ThemeData buildTheme(
  Brightness b, {
  UiStyle? style,
  int? accent,
  bool? amoled,
}) {
  final st = style ?? currentUiStyle();
  final spec = styleSpecs[st]!;
  final dark = b == Brightness.dark;
  final black = amoled ?? AppController.I.settings.amoled;
  final cs = AppController.I.settings.accentCustom;
  customAccent = cs == 0 ? null : Color(cs);
  final hue = resolveHue(st, accent ?? AppController.I.settings.accentIndex, b);
  final ink = dark ? Colors.white : Colors.black;
  final bg = dark ? (black ? Colors.black : spec.darkBg) : spec.lightBg;
  final surface = dark
      ? (black ? const Color(0xFF111111) : spec.darkSurface)
      : spec.lightSurface;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: hue, brightness: b).copyWith(
      primary: hue,
      onPrimary: onColor(hue),
      secondary: hue,
      surface: bg,
      onSurface: ink,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: surface,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: dark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
    dialogTheme: DialogThemeData(
      backgroundColor: Color.lerp(
        surface,
        dark ? Colors.black : Colors.white,
        0.15,
      )!.withValues(alpha: 0.94),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spec.radius + 6),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Color.lerp(
        surface,
        dark ? Colors.black : Colors.white,
        0.1,
      )!.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spec.radius + 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? onColor(hue) : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? hue : null,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [AuroraTheme(spec: spec, hue: hue, amoled: black)],
  );
  var text = GoogleFonts.getTextTheme(
    spec.font,
    base.textTheme,
  ).apply(bodyColor: ink, displayColor: ink);
  if (spec.serifHeadings) {
    final serif = GoogleFonts.getTextTheme('Playfair Display', base.textTheme);
    text = text.copyWith(
      displayLarge: serif.displayLarge?.copyWith(color: ink),
      displayMedium: serif.displayMedium?.copyWith(color: ink),
      displaySmall: serif.displaySmall?.copyWith(color: ink),
      headlineLarge: serif.headlineLarge?.copyWith(color: ink),
      headlineMedium: serif.headlineMedium?.copyWith(color: ink),
      headlineSmall: serif.headlineSmall?.copyWith(color: ink),
      titleLarge: serif.titleLarge?.copyWith(color: ink),
    );
  }
  return base.copyWith(textTheme: text);
}

/// Black or white, whichever reads better on [c].
Color onColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
    ? Colors.white
    : Colors.black;

extension ThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get accent => isDark ? Colors.white : Colors.black;
  Color get onAccent => isDark ? Colors.black : Colors.white;
  AuroraTheme get aurora => AuroraTheme.of(this);
  StyleSpec get spec => aurora.spec;

  /// Brand colour of the chosen style/accent (ink for the mono Glass look).
  Color get hue => aurora.hue;
  Color get onHue => onColor(aurora.hue);
  double get cardRadius => aurora.spec.radius;
  Color get bg => isDark
      ? (aurora.amoled ? Colors.black : aurora.spec.darkBg)
      : aurora.spec.lightBg;
  Color get secondaryText =>
      isDark ? const Color(0x99EBEBF5) : const Color(0x99000000);
  Color get tertiaryText =>
      isDark ? const Color(0x4DEBEBF5) : const Color(0x4D000000);
  Color get separator =>
      isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
  Color get surface2 => isDark
      ? (aurora.amoled ? const Color(0xFF111111) : aurora.spec.darkSurface)
      : aurora.spec.lightSurface;

  /// Translucent chip/field fill that works on glass in both themes.
  Color get chipFill =>
      isDark ? const Color(0x26FFFFFF) : const Color(0x14000000);
}

/// "Music" wordmark in a display serif.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    'Music',
    style: GoogleFonts.playfairDisplay(
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.5,
      color: context.accent,
    ),
  );
}
