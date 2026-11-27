import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/app_icons.dart';
import '../../platform/app_icon.dart';
import '../theme/styles.dart';
import '../theme/theme.dart';
import '../widgets/page_header.dart';

/// Everything about how the app looks: light/dark, one of six styles, accent colour, player layout, app icon.
/// Choices are stored in Settings only; playlists, history and downloads are never touched.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      final cur = currentUiStyle();
      final wide = MediaQuery.sizeOf(context).width > 700;
      return ListView(
        padding: const EdgeInsets.only(bottom: 190),
        children: [
          const PageHeader(
            'Appearance',
            subtitle: 'Make it yours. Your music and playlists stay exactly as they are.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelLabel('Mode'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'system',
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: 'light',
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.themeMode = v.first,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Pure black in dark mode',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Saves battery on OLED screens',
                    style: TextStyle(color: context.secondaryText),
                  ),
                  value: s.amoled,
                  onChanged: (v) => s.amoled = v,
                ),
                const PanelLabel('Style'),
              ],
            ),
          ),
          SizedBox(
            height: wide ? 300 : 276,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: UiStyle.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _StyleCard(
                style: UiStyle.values[i],
                selected: UiStyle.values[i] == cur,
                onTap: () => s.uiStyle = UiStyle.values[i].name,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelLabel('Accent colour'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < accentPalette.length; i++)
                      _Swatch(
                        index: i,
                        selected: s.accentIndex == i,
                        style: cur,
                      ),
                  ],
                ),
                const PanelLabel('Player'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _chip(
                      context,
                      'Match style',
                      s.playerStyle == 'auto',
                      () => s.playerStyle = 'auto',
                      Icons.auto_awesome_rounded,
                    ),
                    _chip(
                      context,
                      'Classic',
                      s.playerStyle == 'classic',
                      () => s.playerStyle = 'classic',
                      Icons.crop_square_rounded,
                    ),
                    _chip(
                      context,
                      'Vinyl',
                      s.playerStyle == 'vinyl',
                      () => s.playerStyle = 'vinyl',
                      Icons.album_rounded,
                    ),
                    _chip(
                      context,
                      'Orbit',
                      s.playerStyle == 'orbit',
                      () => s.playerStyle = 'orbit',
                      Icons.radio_button_checked_rounded,
                    ),
                    _chip(
                      context,
                      'Poster',
                      s.playerStyle == 'poster',
                      () => s.playerStyle = 'poster',
                      Icons.image_rounded,
                    ),
                    _chip(
                      context,
                      'Editorial',
                      s.playerStyle == 'editorial',
                      () => s.playerStyle = 'editorial',
                      Icons.article_outlined,
                    ),
                    _chip(
                      context,
                      'Cassette',
                      s.playerStyle == 'cassette',
                      () => s.playerStyle = 'cassette',
                      Icons.speaker_group_outlined,
                    ),
                    _chip(
                      context,
                      'Grain poster',
                      s.playerStyle == 'grain',
                      () => s.playerStyle = 'grain',
                      Icons.grain_rounded,
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Wide desk layout on phones'),
                  subtitle: const Text(
                    'The Windows-style player: art, queue and controls side by side',
                  ),
                  value: s.deskPlayer,
                  onChanged: (v) => s.deskPlayer = v,
                ),
                const PanelLabel('App icon'),
                Text(
                  AppIconPlatform.supported
                      ? 'Pick the icon on your home screen. Each one has a name.'
                      : 'Home-screen icons can be changed on Android and iPhone. The icon you pick here is also used inside the app.',
                  style: TextStyle(
                    color: context.secondaryText,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (AppIconPlatform.canRename)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Use the icon’s name as the app name',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Off keeps the name “Music” under every icon',
                      style: TextStyle(color: context.secondaryText),
                    ),
                    value: s.iconNamed,
                    onChanged: (v) async {
                      s.iconNamed = v;
                      await AppIconPlatform.set(s.iconId, named: v);
                    },
                  )
                else if (AppIconPlatform.supported)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'iPhone keeps the name “Music” under every icon; only the picture changes.',
                      style: TextStyle(
                        color: context.tertiaryText,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: wide ? 110 : 92,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: appIcons.length,
                  itemBuilder: (context, i) {
                    final ic = appIcons[i];
                    final on = ic.id == s.iconId;
                    return GestureDetector(
                      onTap: () async {
                        s.iconId = ic.id;
                        if (AppIconPlatform.supported) {
                          final ok = await AppIconPlatform.set(
                            ic.id,
                            named: s.iconNamed,
                          );
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'This device could not switch the icon.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: Column(
                        children: [
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: on ? context.hue : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.asset(
                                  ic.asset,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  cacheWidth: 220,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            ic.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: on
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: on
                                  ? context.accent
                                  : context.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const PanelLabel('Effects'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Particle background',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: s.particles,
                  onChanged: (v) => s.particles = v,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Waveform progress bar',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: s.waveformBar,
                  onChanged: (v) => s.waveformBar = v,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Round-thumb slider',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: s.thumbSlider,
                  onChanged: (v) => s.thumbSlider = v,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Light effects',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Fewer glows and animations for older devices',
                    style: TextStyle(color: context.secondaryText),
                  ),
                  value: s.lightEffects,
                  onChanged: (v) => s.lightEffects = v,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _chip(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
    IconData icon,
  ) => ChoiceChip(
    selected: on,
    onSelected: (_) => onTap(),
    avatar: Icon(
      icon,
      size: 18,
      color: on ? context.onHue : context.secondaryText,
    ),
    label: Text(label),
    selectedColor: context.hue,
    labelStyle: TextStyle(
      fontWeight: FontWeight.w700,
      color: on ? context.onHue : context.accent,
    ),
    showCheckmark: false,
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.index,
    required this.selected,
    required this.style,
  });
  final int index;
  final bool selected;
  final UiStyle style;

  @override
  Widget build(BuildContext context) {
    final (name, _) = accentPalette[index];
    final color = resolveHue(style, index, Theme.of(context).brightness);
    return Tooltip(
      message: name,
      child: GestureDetector(
        onTap: () => AppController.I.settings.accentIndex = index,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? context.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: selected
                ? Icon(Icons.check_rounded, size: 20, color: onColor(color))
                : (index == 0
                      ? Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: onColor(color),
                        )
                      : null),
          ),
        ),
      ),
    );
  }
}

/// A small drawn preview of one style: backdrop colour, cover tiles with that style's corner radius, and its nav bar.
class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });
  final UiStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spec = styleSpecs[style]!;
    final dark = context.isDark;
    final bg = dark ? spec.darkBg : spec.lightBg;
    final surf = dark ? spec.darkSurface : spec.lightSurface;
    final ink = dark ? Colors.white : Colors.black;
    final hue = spec.defaultHue ?? ink;
    final r = (spec.radius / 3).clamp(1.0, 9.0);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 170,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected ? context.hue : context.separator,
                    width: selected ? 2.5 : 0.8,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: bg,
                            gradient: switch (spec.backdrop) {
                              BackdropKind.skyGradient => LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  dark
                                      ? const Color(0xFF123A73)
                                      : const Color(0xFF8EC5FF),
                                  bg,
                                ],
                              ),
                              BackdropKind.orbitGlow => RadialGradient(
                                center: const Alignment(0, -0.6),
                                radius: 1,
                                colors: [hue.withValues(alpha: 0.45), bg],
                              ),
                              BackdropKind.greenMesh => RadialGradient(
                                center: const Alignment(-0.8, -0.6),
                                radius: 1.1,
                                colors: [hue.withValues(alpha: 0.4), bg],
                              ),
                              BackdropKind.artMesh => LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.lerp(
                                    bg,
                                    const Color(0xFFB04DFF),
                                    0.35,
                                  )!,
                                  bg,
                                ],
                              ),
                              BackdropKind.sleeveFlat => LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.center,
                                colors: [hue.withValues(alpha: 0.35), bg],
                              ),
                              BackdropKind.paper => null,
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 70,
                              height: 9,
                              decoration: BoxDecoration(
                                color: ink.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (var i = 0; i < 2; i++) ...[
                                  Expanded(
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: i == 0
                                              ? hue.withValues(alpha: 0.75)
                                              : surf,
                                          borderRadius: BorderRadius.circular(
                                            r,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (i == 0) const SizedBox(width: 8),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < 2; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: surf,
                                        borderRadius: BorderRadius.circular(r),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: ink.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _NavMock(
                          kind: spec.nav,
                          hue: hue,
                          surf: surf,
                          ink: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  spec.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.accent,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: context.hue,
                  ),
                ],
              ],
            ),
            Text(
              spec.tagline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavMock extends StatelessWidget {
  const _NavMock({
    required this.kind,
    required this.hue,
    required this.surf,
    required this.ink,
  });
  final NavKind kind;
  final Color hue;
  final Color surf;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final dots = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < 4; i++)
          kind == NavKind.textRail
              ? Container(
                  width: 16,
                  height: 3,
                  color: i == 0 ? hue : ink.withValues(alpha: 0.3),
                )
              : Container(
                  width: i == 0 && kind == NavKind.capsuleLabel ? 26 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i == 0 ? hue : ink.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
      ],
    );
    final floating =
        kind == NavKind.floatingPill ||
        kind == NavKind.capsuleLabel ||
        kind == NavKind.frostedDock ||
        kind == NavKind.liquidGlass ||
        kind == NavKind.leafDock;
    if (floating) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            color: surf.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(
              kind == NavKind.leafDock ? 10 : 14,
            ),
          ),
          child: dots,
        ),
      );
    }
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: surf,
        border: Border(top: BorderSide(color: ink.withValues(alpha: 0.2))),
      ),
      child: dots,
    );
  }
}
