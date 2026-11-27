import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../backend/native_backend.dart';
import '../../core/app_icons.dart';
import '../../platform/app_icon.dart';
import '../../platform/widget_sync.dart';
import '../theme/styles.dart';
import '../theme/theme.dart';
import 'appearance_screen.dart';
import '../widgets/audio_controls.dart';
import '../../engine/automix/analyzer.dart';
import 'diagnostics_screen.dart';
import 'downloads_screen.dart';
import 'equalizer_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// Profile and its pages, laid out like the Apollo app: Profile > Appearance (App icon, Backgrounds, Themes,
/// Mini player button, Widget Theme, Smooth animations), Account, Audio, Data (Backup & Restore),
/// Support. Every control writes to the same settings as before, so nothing a listener saved is lost.
void pushHub(BuildContext context, Widget page) => Navigator.of(context).push(
  CupertinoPageRoute(
    builder: (_) => Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(bottom: false, child: page),
    ),
  ),
);

void openProfileHub(BuildContext context) =>
    pushHub(context, const ProfileHubScreen());

// ---- Building blocks -------------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.children,
    this.centered = false,
    this.trailing,
  });
  final String title;
  final bool centered;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final back = GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.isDark ? const Color(0xFF0B0B0C) : Colors.white,
          border: Border.all(color: context.separator, width: 1.5),
        ),
        child: const Icon(Icons.chevron_left_rounded, size: 30),
      ),
    );
    return Column(
      children: [
        if (centered)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.separator)),
            ),
            child: Row(
              children: [
                back,
                Expanded(
                  child: Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                back,
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
            children: children,
          ),
        ),
      ],
    );
  }
}

Color _groupColor(BuildContext c) =>
    c.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE9E9EE);

class _Section extends StatelessWidget {
  const _Section({this.label, required this.children, this.footer});
  final String? label;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 15,
                letterSpacing: 0.6,
                color: context.secondaryText,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: _groupColor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 70,
                    color: context.separator.withValues(alpha: 0.6),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
              footer!,
              style: TextStyle(fontSize: 14.5, color: context.secondaryText),
            ),
          ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    this.value,
    this.onTap,
    this.trailing,
    this.leading,
    this.badge,
  });
  final IconData? icon;
  final Widget? leading;
  final Color color;
  final String title;
  final String? value;
  final String? badge;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          leading ??
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(title, style: const TextStyle(fontSize: 18)),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.separator,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: context.secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, color: context.secondaryText),
                ),
              ),
            ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: context.tertiaryText,
              size: 26,
            ),
        ],
      ),
    ),
  );
}

/// Opens a rounded menu next to [anchor] (the tapped row), like the pop-up menus of the Apollo app.
Future<T?> _menu<T>(
  BuildContext anchor,
  List<(T, IconData, String)> items,
  T selected,
) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(
    Offset(24, box.size.height * 0.55),
    ancestor: overlay,
  );
  final bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  return showMenu<T>(
    context: anchor,
    position: RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    ),
    color: anchor.isDark ? const Color(0xFF2A2A2D) : Colors.white,
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    items: [
      for (final it in items)
        PopupMenuItem<T>(
          value: it.$1,
          height: 52,
          child: Row(
            children: [
              Icon(it.$2, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(it.$3, style: const TextStyle(fontSize: 17)),
              ),
              if (it.$1 == selected) const Icon(Icons.check_rounded, size: 24),
            ],
          ),
        ),
    ],
  );
}

// ---- Profile ---------------------------------------------------------------------------------------

class ProfileHubScreen extends StatelessWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppController.I;
    return ListenableBuilder(
      listenable: c.settings,
      builder: (context, _) {
        final s = c.settings;
        final style = styleSpecs[currentUiStyle()]!.name;
        return _Page(
          title: 'Profile',
          centered: true,
          children: [
            _Section(
              label: 'APPEARANCE',
              footer: 'Themes, backgrounds, widget, animations',
              children: [
                _Tile(
                  icon: Icons.brush_rounded,
                  color: const Color(0xFFAF52DE),
                  title: 'Appearance',
                  value: style,
                  onTap: () => pushHub(context, const AppearanceHub()),
                ),
              ],
            ),
            _Section(
              label: 'ACCOUNT',
              footer:
                  'Recommendations are built from what you play on this device',
              children: [
                _Tile(
                  icon: Icons.person_rounded,
                  color: const Color(0xFF8E8E93),
                  title: 'Your name',
                  value: s.profileName.isEmpty ? 'Add' : s.profileName,
                  onTap: () => _name(context),
                ),
                _Tile(
                  icon: Icons.insights_rounded,
                  color: const Color(0xFF30B0C7),
                  title: 'Listening stats & photo',
                  onTap: () => pushHub(context, const ProfileScreen()),
                ),
                _Tile(
                  icon: Icons.smart_display_rounded,
                  color: const Color(0xFFEF5440),
                  title: 'Music sources',
                  value: s.youtubeEnabled ? 'YouTube Music' : 'Off',
                  onTap: () => pushHub(context, const _SourcesScreen()),
                ),
              ],
            ),
            _Section(
              label: 'AUDIO',
              footer: 'Quality, shuffle, endless music, automix, equalizer',
              children: [
                _Tile(
                  icon: Icons.tune_rounded,
                  color: const Color(0xFFEF3E5C),
                  title: 'Audio preferences',
                  onTap: () => pushHub(context, const AudioHub()),
                ),
              ],
            ),
            _Section(
              label: 'DATA',
              footer: 'Sync your data across devices',
              children: [
                _Tile(
                  icon: Icons.cloud_rounded,
                  color: const Color(0xFF4DB6CF),
                  title: 'Backup & Restore',
                  onTap: () => pushHub(context, const BackupHub()),
                ),
                _Tile(
                  icon: Icons.download_for_offline_rounded,
                  color: const Color(0xFF34C759),
                  title: 'Downloads',
                  value: '${c.downloads.tracks.length} saved',
                  onTap: () => pushHub(context, const DownloadsScreen()),
                ),
              ],
            ),
            _Section(
              label: 'SUPPORT',
              children: [
                _Tile(
                  icon: Icons.bug_report_rounded,
                  color: const Color(0xFFFF9F0A),
                  title: 'YouTube diagnostics',
                  onTap: () => pushHub(context, const DiagnosticsScreen()),
                ),
                _Tile(
                  icon: Icons.settings_rounded,
                  color: const Color(0xFF636366),
                  title: 'All settings',
                  onTap: () => pushHub(context, const SettingsScreen()),
                ),
              ],
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Aurora 2.0',
                  style: TextStyle(color: context.tertiaryText),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _name(BuildContext context) async {
    final s = AppController.I.settings;
    final ctl = TextEditingController(text: s.profileName);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            const Expanded(child: Text('Your name')),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: InputDecoration(
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) s.profileName = v;
  }
}

class _SourcesScreen extends StatelessWidget {
  const _SourcesScreen();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      return _Page(
        title: 'Sources',
        children: [
          _Section(
            footer: 'YouTube Music feeds the charts, trending playlists and new releases. No login is needed.',
            children: [
              _Tile(
                icon: Icons.smart_display_rounded,
                color: const Color(0xFFEF5440),
                title: 'YouTube Music',
                trailing: Switch(
                  value: s.youtubeEnabled,
                  onChanged: (v) => s.youtubeEnabled = v,
                ),
              ),
              _Tile(
                icon: Icons.album_rounded,
                color: const Color(0xFF30B0C7),
                title: 'JioSaavn',
                trailing: Switch(
                  value: s.saavnEnabled,
                  onChanged: (v) => s.saavnEnabled = v,
                ),
              ),
              _Tile(
                icon: Icons.graphic_eq_rounded,
                color: const Color(0xFFCC0FE0),
                title: 'Audius',
                trailing: Switch(
                  value: s.audiusEnabled,
                  onChanged: (v) => s.audiusEnabled = v,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

// ---- Appearance ------------------------------------------------------------------------------------

class AppearanceHub extends StatelessWidget {
  const AppearanceHub({super.key});

  static const _minis = <(String, IconData, String)>[
    ('like', Icons.favorite_border_rounded, 'Like'),
    ('next', Icons.skip_next_rounded, 'Next track'),
    ('previous', Icons.skip_previous_rounded, 'Previous track'),
    ('playlist', Icons.playlist_add_rounded, 'Add to playlist'),
    ('output', Icons.airplay_rounded, 'Audio output'),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      final icon = appIcons.firstWhere(
        (i) => i.id == s.iconId,
        orElse: () => appIcons.firstWhere((i) => i.id == defaultIconId),
      );
      final mini = _minis.firstWhere(
        (m) => m.$1 == s.miniButton,
        orElse: () => _minis.first,
      );
      final cur = currentUiStyle();
      return _Page(
        title: 'Appearance',
        children: [
          _Section(
            children: [
              _Tile(
                icon: null,
                color: Colors.transparent,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(icon.asset, width: 42, height: 42),
                ),
                title: 'App icon',
                value: icon.id == defaultIconId ? 'Default' : icon.name,
                onTap: () => pushHub(context, const IconPickerScreen()),
              ),
              _Tile(
                icon: Icons.brush_rounded,
                color: const Color(0xFFAF52DE),
                title: 'Backgrounds',
                onTap: () => pushHub(context, const BackgroundsScreen()),
              ),
              Builder(
                builder: (ctx) => _Tile(
                  icon: Icons.music_note_rounded,
                  color: const Color(0xFFFF2D55),
                  title: 'Themes',
                  value: styleSpecs[cur]!.name,
                  onTap: () async {
                    final pick = await _menu<String>(ctx, [
                      for (final st in UiStyle.values)
                        (st.name, _styleIcon(st), '${styleSpecs[st]!.name} UI'),
                      (
                        'gallery',
                        Icons.grid_view_rounded,
                        'Preview all styles…',
                      ),
                    ], cur.name);
                    if (pick == null || !ctx.mounted) return;
                    if (pick == 'gallery') {
                      pushHub(ctx, const AppearanceScreen());
                    } else {
                      s.uiStyle = pick;
                    }
                  },
                ),
              ),
              Builder(
                builder: (ctx) => _Tile(
                  icon: Icons.favorite_border_rounded,
                  color: const Color(0xFF30B8C9),
                  title: 'Mini player button',
                  value: mini.$3.split(' ').first,
                  onTap: () async {
                    final pick = await _menu<String>(ctx, _minis, s.miniButton);
                    if (pick != null) s.miniButton = pick;
                  },
                ),
              ),
              _Tile(
                icon: Icons.widgets_rounded,
                color: const Color(0xFF5856D6),
                title: 'Widget Theme',
                value: _cap(s.widgetTheme),
                onTap: () => pushHub(context, const WidgetThemeScreen()),
              ),
            ],
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            _Section(
              footer: 'A poster of the playing song on the Lock Screen and Dynamic Island',
              children: [
                _Tile(
                  icon: Icons.lock_clock_rounded,
                  color: const Color(0xFF0A84FF),
                  title: 'Lock Screen poster',
                  trailing: Switch(
                    value: s.lockPoster,
                    onChanged: (v) => s.lockPoster = v,
                  ),
                ),
              ],
            ),
          _Section(
            footer: 'Fade between tabs when you switch',
            children: [
              _Tile(
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF34C759),
                title: 'Smooth animations',
                trailing: Switch(
                  value: s.smoothAnimations,
                  onChanged: (v) => s.smoothAnimations = v,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  static IconData _styleIcon(UiStyle st) => switch (st) {
    UiStyle.apollo => Icons.library_music_rounded,
    UiStyle.classic => Icons.blur_on_rounded,
    UiStyle.orbit => Icons.radio_button_checked_rounded,
    UiStyle.sleeve => Icons.album_rounded,
    UiStyle.sky => Icons.cloud_rounded,
    UiStyle.verdant => Icons.eco_rounded,
    UiStyle.editorial => Icons.article_rounded,
  };
}

String _cap(String v) =>
    v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';

// ---- App icon --------------------------------------------------------------------------------------

class IconPickerScreen extends StatelessWidget {
  const IconPickerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      return _Page(
        title: 'App icon',
        children: [
          if (AppIconPlatform.canRename)
            _Section(
              footer: 'Also shows the icon\'s name under it on the home screen',
              children: [
                _Tile(
                  icon: Icons.label_rounded,
                  color: const Color(0xFF3478F6),
                  title: 'Use icon name as app name',
                  trailing: Switch(
                    value: s.iconNamed,
                    onChanged: (v) async {
                      s.iconNamed = v;
                      await AppIconPlatform.set(s.iconId, named: v);
                    },
                  ),
                ),
              ],
            ),
          LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 96).floor().clamp(3, 8);
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final i in appIcons)
                    GestureDetector(
                      onTap: () async {
                        s.iconId = i.id;
                        final ok = await AppIconPlatform.set(
                          i.id,
                          named: s.iconNamed,
                        );
                        if (!ok &&
                            AppIconPlatform.supported &&
                            context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not change the icon'),
                            ),
                          );
                        }
                      },
                      child: SizedBox(
                        width: w,
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(w * 0.24),
                                border: Border.all(
                                  color: s.iconId == i.id
                                      ? context.hue
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(w * 0.22),
                                child: Image.asset(
                                  i.asset,
                                  width: w - 10,
                                  height: w - 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              i.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: s.iconId == i.id
                                    ? null
                                    : context.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}

// ---- Backgrounds -----------------------------------------------------------------------------------

class BackgroundsScreen extends StatelessWidget {
  const BackgroundsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      final modes = const [
        ('system', 'System'),
        ('light', 'Light'),
        ('dark', 'Dark'),
      ];
      final dark = Theme.of(context).brightness;
      return _Page(
        title: 'Backgrounds',
        trailing: IconButton(
          tooltip: 'Reset',
          icon: const Icon(Icons.restart_alt_rounded, size: 28),
          onPressed: () {
            s.themeMode = 'dark';
            s.accentIndex = 0;
            s.amoled = false;
          },
        ),
        children: [
          _Section(
            label: 'THEME',
            children: [
              for (final m in modes)
                InkWell(
                  onTap: () => s.themeMode = m.$1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.$2,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        if (s.themeMode == m.$1)
                          Icon(
                            Icons.check_rounded,
                            color: context.secondaryText,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          _Section(
            children: [
              _Tile(
                icon: Icons.contrast_rounded,
                color: const Color(0xFF636366),
                title: 'Pure black (AMOLED)',
                trailing: Switch(
                  value: s.amoled,
                  onChanged: (v) => s.amoled = v,
                ),
              ),
            ],
          ),
          _Section(
            label: 'PRIMARY COLOR',
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < accentPalette.length; i++)
                      _Swatch(
                        color: accentPalette[i].$2.a == 0
                            ? const Color(0xFF8E8E93)
                            : resolveHue(currentUiStyle(), i, dark),
                        selected: s.accentIndex == i,
                        onTap: () => s.accentIndex = i,
                        label: accentPalette[i].$1,
                      ),
                    _CustomSwatch(
                      selected: s.accentIndex == customAccentIndex,
                      onTap: () => _custom(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            label: 'HOME THEME',
            children: [
              _Tile(
                icon: Icons.layers_rounded,
                color: const Color(0xFF4DB6CF),
                title: 'Home layout',
                onTap: () => pushHub(context, const HomeLayoutScreen()),
              ),
            ],
          ),
        ],
      );
    },
  );

  Future<void> _custom(BuildContext context) async {
    final s = AppController.I.settings;
    var hsv = HSVColor.fromColor(
      s.accentCustom == 0 ? const Color(0xFF2F6BFF) : Color(s.accentCustom),
    );
    final res = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('Custom colour'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Slider(
                value: hsv.hue,
                max: 359,
                activeColor: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                onChanged: (v) => set(() => hsv = hsv.withHue(v)),
              ),
              Slider(
                value: hsv.saturation,
                onChanged: (v) => set(() => hsv = hsv.withSaturation(v)),
              ),
              Slider(
                value: hsv.value,
                min: 0.25,
                onChanged: (v) => set(() => hsv = hsv.withValue(v)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, hsv.toColor()),
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );
    if (res == null) return;
    s.accentCustom = res.toARGB32();
    s.accentIndex = customAccentIndex;
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.label,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color == const Color(0x00000000)
              ? const Color(0xFF4D4D4F)
              : color,
          border: selected ? Border.all(color: Colors.white, width: 3.5) : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    ),
  );
}

class _CustomSwatch extends StatelessWidget {
  const _CustomSwatch({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const SweepGradient(
          colors: [
            Color(0xFFFF3B30),
            Color(0xFFFFCC00),
            Color(0xFF34C759),
            Color(0xFF00C7BE),
            Color(0xFF0A84FF),
            Color(0xFFBF5AF2),
            Color(0xFFFF3B30),
          ],
        ),
        border: selected ? Border.all(color: Colors.white, width: 3.5) : null,
      ),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );
}

class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  static const _rows = <(String, String, IconData)>[
    ('hero', 'Chart hero', Icons.view_carousel_rounded),
    ('quick', 'Quick picks', Icons.bolt_rounded),
    ('charts', 'Chart songs', Icons.leaderboard_rounded),
    ('playlists', 'Playlists', Icons.queue_music_rounded),
    ('releases', 'New releases & albums', Icons.new_releases_rounded),
    ('artists', 'Artists', Icons.people_rounded),
    ('recent', 'Recently played', Icons.history_rounded),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      return _Page(
        title: 'Home layout',
        children: [
          _Section(
            footer: 'Applies to the Apollo style. Other styles keep their own Home.',
            children: [
              for (final r in _rows)
                _Tile(
                  icon: r.$3,
                  color: const Color(0xFF4DB6CF),
                  title: r.$2,
                  trailing: Switch(
                    value: s.homeShows(r.$1),
                    onChanged: (v) => s.setHomeSection(r.$1, v),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}

// ---- Widget theme ----------------------------------------------------------------------------------

Future<void> applyWidgetTheme(String name) async {
  final c = AppController.I;
  c.settings.widgetTheme = name;
  await WidgetSync.setTheme(name);
  final b = c.backend;
  if (b is NativeBackend) {
    try {
      await b.setWidgetTheme(name);
    } catch (_) {}
  }
}

class WidgetThemeScreen extends StatelessWidget {
  const WidgetThemeScreen({super.key});

  static const _names = [
    'minimal',
    'classic',
    'gradient',
    'glass',
    'vinyl',
    'neon',
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final cur = AppController.I.settings.widgetTheme;
      return _Page(
        title: 'Widget Theme',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 22),
            child: Text(
              'Choose a style for your home screen widget',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.secondaryText,
              ),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              for (final n in _names)
                GestureDetector(
                  onTap: () => unawaited(applyWidgetTheme(n)),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    decoration: BoxDecoration(
                      color: _groupColor(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: cur == n
                            ? context.secondaryText
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(child: _WidgetMock(theme: n)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_cap(n), style: const TextStyle(fontSize: 17)),
                            if (cur == n) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: context.secondaryText,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}

class _WidgetMock extends StatelessWidget {
  const _WidgetMock({required this.theme});
  final String theme;

  @override
  Widget build(BuildContext context) {
    final BoxDecoration deco = switch (theme) {
      'minimal' => BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: BorderRadius.circular(18),
      ),
      'gradient' => BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B2EE6), Color(0xFF2E5CD9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      'glass' => BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x55FFFFFF)),
      ),
      'vinyl' => BoxDecoration(
        color: const Color(0xFF14100E),
        borderRadius: BorderRadius.circular(18),
      ),
      'neon' => BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF06323B), Color(0xFF020A0D)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x5522D3EE)),
      ),
      _ => BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A2D), Color(0xFF0E0E10)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
    };
    final play = theme == 'neon'
        ? const Color(0xFF22D3EE)
        : const Color(0xFFB8B8BC);
    return Container(
      decoration: deco,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: theme == 'vinyl'
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF4A3A30),
                      width: 3,
                    ),
                  )
                : BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: const Icon(
              Icons.music_note_rounded,
              size: 16,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D0D4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 5),
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0x66FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, color: play),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Audio -----------------------------------------------------------------------------------------

/// Every music and sound control of the app on one page: quality, song transitions (crossfade, automix
/// and its DJ options), endless music, equalizer and spatial sound, output, player controls and offline.
class AudioHub extends StatelessWidget {
  const AudioHub({super.key});

  static const _qualityNames = ['Data saver', 'Normal', 'High', 'Best'];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final c = AppController.I;
      final s = c.settings;
      final b = c.backend;
      final mode = !s.automix ? 0 : (s.crossfadeOnly ? 1 : 2);
      final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      return _Page(
        title: 'Audio',
        children: [
          _Section(
            label: 'QUALITY',
            footer: s.qualityMode == 4
                ? 'Automatic: ${_qualityNames[s.quality.clamp(0, 3)]}, about ${s.qualityKbps} kbps right now'
                : '${_qualityNames[s.qualityMode.clamp(0, 3)]}, about ${s.qualityKbps} kbps',
            children: [
              _Tile(
                icon: Icons.speaker_rounded,
                color: const Color(0xFFFF2D55),
                title: 'Audio quality',
                value: s.qualityMode == 4
                    ? 'Auto'
                    : _qualityNames[s.qualityMode.clamp(0, 3)],
                onTap: () => _quality(context),
              ),
            ],
          ),
          _Section(
            label: 'PLAYBACK',
            footer: 'When your queue ends, keep playing songs you are likely to enjoy',
            children: [
              _Tile(
                icon: Icons.all_inclusive_rounded,
                color: const Color(0xFF34C759),
                title: 'Endless music',
                trailing: Switch(
                  value: s.autoplay,
                  onChanged: (v) => s.autoplay = v,
                ),
              ),
            ],
          ),
          _Section(
            label: 'SONG TRANSITIONS',
            footer: mode == 0
                ? 'Off: each song plays to its end'
                : mode == 1
                ? 'Crossfade: a plain fade into the next song'
                : 'Automix: DJ-style blend, tempo matched, on the beat, length picked for each song',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Off')),
                      ButtonSegment(value: 1, label: Text('Crossfade')),
                      ButtonSegment(value: 2, label: Text('Automix')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) {
                      final m = v.first;
                      s.automix = m != 0;
                      s.crossfadeOnly = m == 1;
                      unawaited(c.applyMix());
                    },
                  ),
                ),
              ),
              if (mode == 1)
                _slider(
                  context,
                  'Crossfade length',
                  s.crossfadeSeconds,
                  1,
                  12,
                  11,
                  (v) => s.crossfadeSeconds = v,
                  c,
                ),
              if (mode == 2) ...[
                _Tile(
                  icon: Icons.album_rounded,
                  color: const Color(0xFF5856D6),
                  title: 'DJ style',
                  value: const [
                    'Smooth',
                    'Club',
                    'Quick cut',
                  ][s.djStyle.clamp(0, 2)],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Smooth')),
                        ButtonSegment(value: 1, label: Text('Club')),
                        ButtonSegment(value: 2, label: Text('Quick cut')),
                      ],
                      selected: {s.djStyle.clamp(0, 2)},
                      onSelectionChanged: (v) => s.djStyle = v.first,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    const [
                      'A long, gentle overlap that follows the songs\' tempo.',
                      'Beat-matched on the bar. The next song comes in early and the old one leaves late.',
                      'A short four-beat cut on the beat.',
                    ][s.djStyle.clamp(0, 2)],
                    style: TextStyle(
                      fontSize: 13.5,
                      color: context.secondaryText,
                    ),
                  ),
                ),
                _Tile(
                  icon: Icons.auto_fix_high_rounded,
                  color: const Color(0xFF5856D6),
                  title: 'Pick the length for me',
                  trailing: Switch(
                    value: s.automixAuto,
                    onChanged: (v) {
                      s.automixAuto = v;
                      unawaited(c.applyMix());
                    },
                  ),
                ),
                if (!s.automixAuto)
                  _slider(
                    context,
                    'Max blend',
                    s.automixSeconds,
                    2,
                    30,
                    28,
                    (v) => s.automixSeconds = v,
                    c,
                  ),
                _Tile(
                  icon: Icons.tune_rounded,
                  color: const Color(0xFFFF9F0A),
                  title: 'DJ filters',
                  badge: 'BETA',
                  trailing: Switch(
                    value: s.mixFilters,
                    onChanged: (v) => s.mixFilters = v,
                  ),
                ),
                if (b.canMixNow)
                  _Tile(
                    icon: Icons.fast_forward_rounded,
                    color: const Color(0xFFEF3E5C),
                    title: 'Mix into the next song now',
                    onTap: () => unawaited(b.mixNow()),
                  ),
                if (AutomixAnalyzer.supported)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: ValueListenableBuilder<String>(
                      valueListenable: AutomixAnalyzer.status,
                      builder: (_, v, __) => Text(
                        v,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.secondaryText,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          _Section(
            label: 'SOUND',
            children: [
              _Tile(
                icon: Icons.equalizer_rounded,
                color: const Color(0xFF8E8E93),
                title: 'Equalizer',
                value: s.eqEnabled ? 'On · ${s.eqPreset}' : 'Off',
                onTap: () => pushHub(context, const EqualizerScreen()),
              ),
              _Tile(
                icon: Icons.surround_sound_rounded,
                color: const Color(0xFF5856D6),
                title: 'Spatial sound',
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: b.spatial,
                  builder: (_, on, __) => Switch(
                    value: on,
                    onChanged: (_) => unawaited(b.toggleSpatial()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.shield_rounded,
                color: const Color(0xFF34C759),
                title: 'Speaker protection',
                trailing: Switch(
                  value: s.outputProtection,
                  onChanged: (v) {
                    s.outputProtection = v;
                    unawaited(b.setOutputProtection(v));
                  },
                ),
              ),
              Builder(
                builder: (ctx) => _Tile(
                  icon: Icons.airplay_rounded,
                  color: const Color(0xFF3478F6),
                  title: 'Audio output',
                  onTap: () => showOutputDialog(ctx),
                ),
              ),
              if (ios)
                _Tile(
                  icon: Icons.memory_rounded,
                  color: const Color(0xFF636366),
                  title: 'Compatibility engine',
                  trailing: Switch(
                    value: s.iosCompatEngine,
                    onChanged: (v) => s.iosCompatEngine = v,
                  ),
                ),
            ],
            footer: ios
                ? 'Compatibility engine uses the older mpv player. Restart the app after changing it.'
                : null,
          ),
          _Section(
            label: 'PLAYER',
            children: [
              _Tile(
                icon: Icons.lyrics_rounded,
                color: const Color(0xFF30B0C7),
                title: 'Word-by-word lyrics',
                trailing: Switch(
                  value: s.wordLyrics,
                  onChanged: (v) => s.wordLyrics = v,
                ),
              ),
              _Tile(
                icon: Icons.linear_scale_rounded,
                color: const Color(0xFF30B0C7),
                title: 'Round slider',
                trailing: Switch(
                  value: s.thumbSlider,
                  onChanged: (v) => s.thumbSlider = v,
                ),
              ),
              _Tile(
                icon: Icons.graphic_eq_rounded,
                color: const Color(0xFF30B0C7),
                title: 'Waveform progress bar',
                trailing: Switch(
                  value: s.waveformBar,
                  onChanged: (v) => s.waveformBar = v,
                ),
              ),
            ],
          ),
          _Section(
            label: 'OFFLINE',
            footer: s.downloadWifiOnly
                ? 'Downloads wait for Wi-Fi. Downloaded songs play without internet.'
                : 'Downloads use mobile data when there is no Wi-Fi. Downloaded songs play without internet.',
            children: [
              Builder(
                builder: (ctx) => _Tile(
                  icon: Icons.high_quality_rounded,
                  color: const Color(0xFFFF2D55),
                  title: 'Download quality',
                  value: const {
                    3: 'Best',
                    2: 'High',
                    1: 'Normal',
                    0: 'Data saver',
                    -1: 'Same as streaming',
                  }[s.downloadQuality],
                  onTap: () async {
                    final pick = await _menu<int>(ctx, const [
                      (3, Icons.diamond_outlined, 'Best'),
                      (2, Icons.graphic_eq_rounded, 'High'),
                      (1, Icons.equalizer_rounded, 'Normal'),
                      (0, Icons.data_saver_on_rounded, 'Data saver'),
                      (-1, Icons.sync_alt_rounded, 'Same as streaming'),
                    ], s.downloadQuality);
                    if (pick != null) s.downloadQuality = pick;
                  },
                ),
              ),
              _Tile(
                icon: Icons.signal_cellular_alt_rounded,
                color: const Color(0xFF34C759),
                title: 'Download over mobile data',
                trailing: Switch(
                  value: !s.downloadWifiOnly,
                  onChanged: (v) => s.downloadWifiOnly = !v,
                ),
              ),
              _Tile(
                icon: Icons.favorite_rounded,
                color: const Color(0xFFFF2D55),
                title: 'Save liked songs offline',
                trailing: Switch(
                  value: s.autoDownloadLiked,
                  onChanged: (v) => s.autoDownloadLiked = v,
                ),
              ),
              _Tile(
                icon: Icons.download_for_offline_rounded,
                color: const Color(0xFF34C759),
                title: 'Downloads',
                value: '${c.downloads.tracks.length} saved',
                onTap: () => pushHub(context, const DownloadsScreen()),
              ),
            ],
          ),
        ],
      );
    },
  );

  Widget _slider(
    BuildContext context,
    String label,
    double v,
    double min,
    double max,
    int div,
    void Function(double) set,
    AppController c,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Column(
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: context.secondaryText)),
            const Spacer(),
            Text(
              '${v.round()} s',
              style: TextStyle(color: context.secondaryText),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: div,
          value: v.clamp(min, max),
          onChanged: set,
          onChangeEnd: (_) => unawaited(c.applyMix()),
        ),
      ],
    ),
  );

  Future<void> _quality(BuildContext context) async {
    final s = AppController.I.settings;
    final pick = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final q in const [
              (4, 'Auto', 'Follows your connection'),
              (0, 'Data saver', 'About 96 kbps'),
              (1, 'Normal', 'About 160 kbps'),
              (2, 'High', 'About 320 kbps'),
              (3, 'Best', 'The highest the source offers'),
            ])
              ListTile(
                title: Text(q.$2),
                subtitle: Text(q.$3),
                trailing: s.qualityMode == q.$1
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(ctx, q.$1),
              ),
          ],
        ),
      ),
    );
    if (pick != null) s.quality = pick;
  }
}

// ---- Backup & Restore ------------------------------------------------------------------------------

class BackupHub extends StatelessWidget {
  const BackupHub({super.key});

  Future<void> _backup(BuildContext context) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final bytes = Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent(' ')
              .convert(AppController.I.settings.exportBackup()),
        ),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup',
        fileName: 'aurora_backup.json',
        bytes: bytes,
      );
      if (path != null)
        msg.showSnackBar(const SnackBar(content: Text('Backup saved')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final data = r?.files.single.bytes;
      if (data == null) return;
      final n = AppController.I.settings.importBackup(
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
      );
      msg.showSnackBar(SnackBar(content: Text('Restored $n playlists')));
    } catch (e) {
      msg.showSnackBar(
        SnackBar(content: Text('That file is not an Aurora backup ($e)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Backup & Restore',
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Icon(
          Icons.cloud_rounded,
          size: 70,
          color: context.secondaryText,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
        child: Text(
          'Back up your playlists, listening history, and settings to a file. Restore on any device without an account.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, color: context.secondaryText),
        ),
      ),
      _Section(
        label: 'BACKUP',
        footer: 'Export playlists, history, and settings',
        children: [
          _Tile(
            icon: Icons.cloud_upload_rounded,
            color: const Color(0xFF8E8E93),
            title: 'Backup data',
            onTap: () => _backup(context),
          ),
        ],
      ),
      _Section(
        label: 'RESTORE',
        footer: 'Import from a backup file',
        children: [
          _Tile(
            icon: Icons.cloud_download_rounded,
            color: const Color(0xFF8E8E93),
            title: 'Restore data',
            onTap: () => _restore(context),
          ),
        ],
      ),
    ],
  );
}
