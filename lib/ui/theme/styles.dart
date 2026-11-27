import 'package:flutter/material.dart';

import '../../app.dart';

/// The six looks the app can wear. Only presentation changes between them: playlists, history, downloads
/// and settings live in [Settings] and are untouched when the style is switched.
enum UiStyle { apollo, classic, orbit, sleeve, sky, verdant, editorial }

/// How the full-screen player lays out the artwork and controls.
enum PlayerStyle { classic, vinyl, orbit, poster, editorial, cassette, grain }

enum NavKind {
  floatingPill,
  capsuleLabel,
  flatBar,
  frostedDock,
  leafDock,
  textRail,
  liquidGlass,
}

enum BackdropKind {
  artMesh,
  orbitGlow,
  sleeveFlat,
  skyGradient,
  greenMesh,
  paper,
}

enum HomeKind { standard, hero, grid, sky, grove, magazine, apollo }

class StyleSpec {
  const StyleSpec({
    required this.style,
    required this.name,
    required this.tagline,
    required this.darkBg,
    required this.lightBg,
    required this.darkSurface,
    required this.lightSurface,
    required this.defaultHue,
    required this.radius,
    required this.font,
    required this.nav,
    required this.backdrop,
    required this.home,
    required this.player,
    this.serifHeadings = false,
    this.particles = true,
  });

  final UiStyle style;
  final String name;
  final String tagline;
  final Color darkBg;
  final Color lightBg;
  final Color darkSurface;
  final Color lightSurface;

  /// Used when the listener has not picked an accent; null means plain white/black ink.
  final Color? defaultHue;
  final double radius;
  final String font;
  final NavKind nav;
  final BackdropKind backdrop;
  final HomeKind home;
  final PlayerStyle player;
  final bool serifHeadings;
  final bool particles;
}

const styleSpecs = <UiStyle, StyleSpec>{
  UiStyle.apollo: StyleSpec(
    style: UiStyle.apollo,
    name: 'Apollo',
    tagline: 'Pure black, a big chart hero and premium shelves',
    darkBg: Color(0xFF000000),
    lightBg: Color(0xFFF2F2F7),
    darkSurface: Color(0xFF1C1C1E),
    lightSurface: Color(0xFFE5E5EA),
    defaultHue: null,
    radius: 18,
    font: 'Inter',
    nav: NavKind.floatingPill,
    backdrop: BackdropKind.sleeveFlat,
    home: HomeKind.apollo,
    player: PlayerStyle.classic,
    particles: false,
  ),
  UiStyle.classic: StyleSpec(
    style: UiStyle.classic,
    name: 'Glass',
    tagline: 'Frosted glass over the colour of what is playing',
    darkBg: Color(0xFF181819),
    lightBg: Color(0xFFF3F3F6),
    darkSurface: Color(0xFF2A2A2C),
    lightSurface: Color(0xFFE6E6EB),
    defaultHue: null,
    radius: 14,
    font: 'Manrope',
    nav: NavKind.liquidGlass,
    backdrop: BackdropKind.artMesh,
    home: HomeKind.standard,
    player: PlayerStyle.classic,
  ),
  UiStyle.orbit: StyleSpec(
    style: UiStyle.orbit,
    name: 'Orbit',
    tagline: 'Deep space, glowing rings, round artwork',
    darkBg: Color(0xFF07080F),
    lightBg: Color(0xFFEFF0FA),
    darkSurface: Color(0xFF14162A),
    lightSurface: Color(0xFFE0E2F4),
    defaultHue: Color(0xFF7C5CFF),
    radius: 22,
    font: 'Space Grotesk',
    nav: NavKind.capsuleLabel,
    backdrop: BackdropKind.orbitGlow,
    home: HomeKind.hero,
    player: PlayerStyle.orbit,
  ),
  UiStyle.sleeve: StyleSpec(
    style: UiStyle.sleeve,
    name: 'Sleeve',
    tagline: 'Square covers, flat colour, record-shop feel',
    darkBg: Color(0xFF111111),
    lightBg: Color(0xFFF2EFEA),
    darkSurface: Color(0xFF1E1E1E),
    lightSurface: Color(0xFFE3DED6),
    defaultHue: Color(0xFFFF5C39),
    radius: 4,
    font: 'DM Sans',
    nav: NavKind.flatBar,
    backdrop: BackdropKind.sleeveFlat,
    home: HomeKind.grid,
    player: PlayerStyle.vinyl,
    particles: false,
  ),
  UiStyle.sky: StyleSpec(
    style: UiStyle.sky,
    name: 'Sky Glass',
    tagline: 'Bright, airy, soft glass on a daylight gradient',
    darkBg: Color(0xFF0A1A33),
    lightBg: Color(0xFFDCEBFF),
    darkSurface: Color(0xFF16294A),
    lightSurface: Color(0xFFC9DEFA),
    defaultHue: Color(0xFF2F80FF),
    radius: 28,
    font: 'Plus Jakarta Sans',
    nav: NavKind.frostedDock,
    backdrop: BackdropKind.skyGradient,
    home: HomeKind.sky,
    player: PlayerStyle.poster,
  ),
  UiStyle.verdant: StyleSpec(
    style: UiStyle.verdant,
    name: 'Verdant Glass',
    tagline: 'Forest greens, rounded leaves, calm glass',
    darkBg: Color(0xFF07140E),
    lightBg: Color(0xFFE4F1E7),
    darkSurface: Color(0xFF12281C),
    lightSurface: Color(0xFFCFE5D5),
    defaultHue: Color(0xFF3DDC84),
    radius: 24,
    font: 'Nunito',
    nav: NavKind.leafDock,
    backdrop: BackdropKind.greenMesh,
    home: HomeKind.grove,
    player: PlayerStyle.cassette,
  ),
  UiStyle.editorial: StyleSpec(
    style: UiStyle.editorial,
    name: 'Editorial',
    tagline: 'Paper, serif headlines, magazine layout',
    darkBg: Color(0xFF0F0E0D),
    lightBg: Color(0xFFF4EFE6),
    darkSurface: Color(0xFF1C1A18),
    lightSurface: Color(0xFFE8E1D3),
    defaultHue: Color(0xFFC8321E),
    radius: 2,
    font: 'Inter',
    nav: NavKind.textRail,
    backdrop: BackdropKind.paper,
    home: HomeKind.magazine,
    player: PlayerStyle.editorial,
    serifHeadings: true,
    particles: false,
  ),
};

/// Twenty accent colours. Index 0 keeps the style's own colour.
const accentPalette = <(String, Color)>[
  ('Style', Color(0x00000000)),
  ('Rose', Color(0xFFFF4D6D)),
  ('Red', Color(0xFFE5383B)),
  ('Coral', Color(0xFFFF6B57)),
  ('Orange', Color(0xFFFF8A1F)),
  ('Amber', Color(0xFFFFB400)),
  ('Yellow', Color(0xFFF2D31B)),
  ('Lime', Color(0xFFA6E22E)),
  ('Green', Color(0xFF34C759)),
  ('Mint', Color(0xFF3DDCA8)),
  ('Teal', Color(0xFF14B8A6)),
  ('Cyan', Color(0xFF22D3EE)),
  ('Sky', Color(0xFF38A3FF)),
  ('Blue', Color(0xFF2F6BFF)),
  ('Indigo', Color(0xFF5B5BFF)),
  ('Violet', Color(0xFF8B5CF6)),
  ('Purple', Color(0xFFB04DFF)),
  ('Magenta', Color(0xFFE040C8)),
  ('Pink', Color(0xFFFF6FB5)),
  ('Slate', Color(0xFF8A94A8)),
];

/// Resolved look for the current frame; carried on [ThemeData] so widgets read it from context.
@immutable
class AuroraTheme extends ThemeExtension<AuroraTheme> {
  const AuroraTheme({
    required this.spec,
    required this.hue,
    required this.amoled,
  });

  final StyleSpec spec;

  /// The brand colour: play buttons, selected tabs, sliders. Falls back to ink for the mono Glass look.
  final Color hue;
  final bool amoled;

  static AuroraTheme of(BuildContext context) =>
      Theme.of(context).extension<AuroraTheme>() ??
      AuroraTheme(
        spec: styleSpecs[UiStyle.classic]!,
        hue: Colors.white,
        amoled: false,
      );

  @override
  AuroraTheme copyWith({StyleSpec? spec, Color? hue, bool? amoled}) =>
      AuroraTheme(
        spec: spec ?? this.spec,
        hue: hue ?? this.hue,
        amoled: amoled ?? this.amoled,
      );

  @override
  AuroraTheme lerp(ThemeExtension<AuroraTheme>? other, double t) {
    if (other is! AuroraTheme) return this;
    return AuroraTheme(
      spec: t < 0.5 ? spec : other.spec,
      hue: Color.lerp(hue, other.hue, t)!,
      amoled: t < 0.5 ? amoled : other.amoled,
    );
  }
}

/// Reads the saved choice. Unknown names (from an older backup) fall back to the classic look.
UiStyle currentUiStyle() {
  final n = AppController.I.settings.uiStyle;
  return UiStyle.values.firstWhere(
    (s) => s.name == n,
    orElse: () => UiStyle.apollo,
  );
}

PlayerStyle currentPlayerStyle() {
  final n = AppController.I.settings.playerStyle;
  for (final p in PlayerStyle.values) {
    if (p.name == n) return p;
  }
  return styleSpecs[currentUiStyle()]!.player;
}

/// Accent index meaning "the colour the listener mixed themselves" (see [customAccent]).
const customAccentIndex = 99;

/// Set from settings by the theme builder.
Color? customAccent;

Color resolveHue(
  UiStyle style,
  int accentIndex,
  Brightness b, {
  Color? custom,
}) {
  final spec = styleSpecs[style]!;
  if (accentIndex == customAccentIndex && (custom ?? customAccent) != null) {
    return (custom ?? customAccent)!;
  }
  if (accentIndex > 0 && accentIndex < accentPalette.length)
    return accentPalette[accentIndex].$2;
  return spec.defaultHue ??
      (b == Brightness.dark ? Colors.white : Colors.black);
}
