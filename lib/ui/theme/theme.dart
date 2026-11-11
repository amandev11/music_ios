import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final accent = dark ? Colors.white : Colors.black;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A8A8A), brightness: b).copyWith(
      primary: accent,
      onPrimary: dark ? Colors.black : Colors.white,
      surface: dark ? Apple.darkBg : Apple.lightBg,
      onSurface: accent,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: dark ? Apple.darkSurface : Apple.lightSurface,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: dark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
    dialogTheme: DialogThemeData(
      backgroundColor: (dark ? const Color(0xFF222224) : const Color(0xFFF7F7FA)).withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: (dark ? const Color(0xFF262628) : const Color(0xFFF7F7FA)).withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
    }),
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: accent, displayColor: accent),
  );
}

extension ThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get accent => isDark ? Colors.white : Colors.black;
  Color get onAccent => isDark ? Colors.black : Colors.white;
  Color get bg => isDark ? Apple.darkBg : Apple.lightBg;
  Color get secondaryText => isDark ? const Color(0x99EBEBF5) : const Color(0x99000000);
  Color get tertiaryText => isDark ? const Color(0x4DEBEBF5) : const Color(0x4D000000);
  Color get separator => isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
  Color get surface2 => isDark ? Apple.darkSurface : Apple.lightSurface;

  /// Translucent chip/field fill that works on glass in both themes.
  Color get chipFill => isDark ? const Color(0x26FFFFFF) : const Color(0x14000000);
}

/// "Music" wordmark in a display serif.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        'Music',
        style: GoogleFonts.playfairDisplay(fontSize: size, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, letterSpacing: -0.5, color: context.accent),
      );
}
