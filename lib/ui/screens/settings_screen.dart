import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import '../../engine/automix/analyzer.dart';

import '../../app.dart';
import '../../core/network_quality.dart';
import '../../core/settings.dart';
import '../theme/theme.dart';
import 'diagnostics_screen.dart';
import '../widgets/common.dart';
import 'equalizer_screen.dart';
import 'home.dart';
import 'import_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Settings s = AppController.I.settings;
  late final _proxy = TextEditingController(text: s.proxyUrl);
  late final _hosts = TextEditingController(text: s.invidiousHosts.join('\n'));

  @override
  void dispose() {
    _proxy.dispose();
    _hosts.dispose();
    super.dispose();
  }

  Widget _label(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 30, 0, 10),
        child: Text(t, style: TextStyle(fontSize: 13, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: context.secondaryText)),
      );

  Widget _row(BuildContext context, {required Widget leading, required String title, required String sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            SizedBox(width: 44, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 14, color: context.secondaryText)),
              ]),
            ),
            if (trailing != null) trailing,
          ]),
        ),
      );

  static const _zones = <(String, int)>[
    ('UTC−12:00', -720), ('UTC−11:00 Pago Pago', -660), ('UTC−10:00 Honolulu', -600), ('UTC−09:00 Anchorage', -540),
    ('UTC−08:00 Los Angeles', -480), ('UTC−07:00 Denver', -420), ('UTC−06:00 Chicago, Mexico City', -360),
    ('UTC−05:00 New York, Bogotá', -300), ('UTC−04:00 Santiago, Halifax', -240), ('UTC−03:00 São Paulo, Buenos Aires', -180),
    ('UTC−01:00 Azores', -60), ('UTC+00:00 London, Lisbon', 0), ('UTC+01:00 Paris, Berlin, Lagos', 60),
    ('UTC+02:00 Cairo, Athens, Johannesburg', 120), ('UTC+03:00 Moscow, Riyadh, Nairobi', 180), ('UTC+03:30 Tehran', 210),
    ('UTC+04:00 Dubai, Baku', 240), ('UTC+04:30 Kabul', 270), ('UTC+05:00 Karachi, Tashkent', 300),
    ('UTC+05:30 India, Sri Lanka', 330), ('UTC+05:45 Kathmandu', 345), ('UTC+06:00 Dhaka, Almaty', 360),
    ('UTC+06:30 Yangon', 390), ('UTC+07:00 Bangkok, Jakarta', 420), ('UTC+08:00 Singapore, Beijing, Perth', 480),
    ('UTC+09:00 Tokyo, Seoul', 540), ('UTC+09:30 Adelaide, Darwin', 570), ('UTC+10:00 Sydney, Brisbane', 600),
    ('UTC+11:00 Solomon Islands', 660), ('UTC+12:00 Auckland, Fiji', 720), ('UTC+13:00 Tonga', 780),
  ];

  static String _tzLabel(int? min) {
    if (min == null) return 'Automatic (this device)';
    for (final z in _zones) {
      if (z.$2 == min) return z.$1;
    }
    return 'UTC${min < 0 ? '−' : '+'}${(min.abs() ~/ 60).toString().padLeft(2, '0')}:${(min.abs() % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _pickZone(BuildContext context, Settings s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(controller: controller, children: [
          ListTile(
            leading: Icon(s.tzOffsetMin == null ? Icons.radio_button_checked : Icons.radio_button_off),
            title: const Text('Automatic (this device)'),
            onTap: () {
              setState(() => s.tzOffsetMin = null);
              Navigator.of(ctx).pop();
            },
          ),
          for (final z in _zones)
            ListTile(
              leading: Icon(s.tzOffsetMin == z.$2 ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(z.$1),
              onTap: () {
                setState(() => s.tzOffsetMin = z.$2);
                Navigator.of(ctx).pop();
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    const qualities = ['Low', 'Medium', 'High', 'Lossless', 'Auto'];
    const order = [4, 0, 1, 2, 3];
    const qualityNote = [
      '96 kbps. Saves data.',
      '160 kbps.',
      'Up to 320 kbps where the source has it.',
      'Best available. Neither JioSaavn nor YouTube Music serves lossless audio.',
      'Follows your network: a slow connection gets a smaller stream so songs start fast, a fast one gets the best.',
    ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, kListBottomPad), children: [
          const Text('Settings', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          _label(context, 'APPEARANCE'),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => setState(() => s.themeMode = v.first),
            ),
          ),
          _row(
            context,
            leading: const Icon(Icons.blur_on_rounded, size: 26),
            title: 'Particle grid',
            sub: 'Dots that react to your pointer in the background',
            trailing: Switch(value: s.particles, onChanged: (v) => setState(() => s.particles = v)),
          ),
          _label(context, 'GREETING'),
          _row(
            context,
            leading: const Icon(Icons.schedule_rounded, size: 26),
            title: 'Time zone',
            sub: _tzLabel(s.tzOffsetMin),
            trailing: Icon(Icons.chevron_right_rounded, color: context.secondaryText),
            onTap: () => _pickZone(context, s),
          ),
          _label(context, 'LIBRARY'),
          _row(
            context,
            leading: const Icon(Icons.playlist_add_rounded, size: 26),
            title: 'Import a playlist',
            sub: 'From Spotify, Apple Music, YouTube, Deezer, or a CSV',
            trailing: Icon(Icons.chevron_right_rounded, color: context.secondaryText),
            onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const ImportScreen())),
          ),
          _label(context, 'PLAYBACK'),
          _row(
            context,
            leading: const Icon(Icons.equalizer_rounded, size: 26),
            title: 'Equalizer',
            sub: s.eqEnabled ? 'On · ${s.eqPreset}' : 'Off',
            trailing: Icon(Icons.chevron_right_rounded, color: context.secondaryText),
            onTap: () async {
              await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const EqualizerScreen()));
              setState(() {});
            },
          ),
          _row(
            context,
            leading: const Icon(Icons.auto_awesome_rounded, size: 26),
            title: 'Autoplay',
            sub: 'When the queue ends, keep playing songs you are likely to enjoy',
            trailing: Switch(value: s.autoplay, onChanged: (v) => setState(() => s.autoplay = v)),
          ),
          _row(
            context,
            leading: const Icon(Icons.lyrics_rounded, size: 26),
            title: 'Word-by-word lyrics',
            sub: 'Experimental. Off keeps clean line-by-line lyrics',
            trailing: Switch(value: s.wordLyrics, onChanged: (v) => setState(() => s.wordLyrics = v)),
          ),
          _row(
            context,
            leading: const Icon(Icons.shield_rounded, size: 26),
            title: 'Speaker protection',
            sub: 'Cuts inaudible sub-bass, limits peaks and keeps headroom so loud songs never clip or trip a speaker or receiver',
            trailing: Switch(
              value: s.outputProtection,
              onChanged: (v) {
                setState(() => s.outputProtection = v);
                unawaited(AppController.I.backend.setOutputProtection(v));
              },
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb)
            _row(
              context,
              leading: const Icon(Icons.memory_rounded, size: 26),
              title: 'Compatibility audio engine',
              sub: 'Off: native iPhone engine (recommended). On: the older mpv player. Restart the app after changing',
              trailing: Switch(value: s.iosCompatEngine, onChanged: (v) => setState(() => s.iosCompatEngine = v)),
            ),
          _row(
            context,
            leading: const Icon(Icons.tune_rounded, size: 26),
            title: 'DJ filters in Automix (beta)',
            sub: 'Bass swap and filter sweeps. Turns itself off if your player rejects them',
            trailing: Switch(value: s.mixFilters, onChanged: (v) => setState(() => s.mixFilters = v)),
          ),
          _row(
            context,
            leading: const Icon(Icons.bug_report_outlined, size: 26),
            title: 'YouTube diagnostics',
            sub: 'Test every YouTube route and see which one fails',
            onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const DiagnosticsScreen())),
          ),
          _row(
            context,
            leading: const Icon(Icons.all_inclusive_rounded, size: 26),
            title: 'Song transitions',
            sub: !s.automix
                ? 'Off: each song plays to its end'
                : s.crossfadeOnly
                    ? 'Crossfade: a plain fade into the next song'
                    : 'Automix: DJ-style blend, length picked for each song',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 8, bottom: 6),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Off')),
                ButtonSegment(value: 1, label: Text('Crossfade')),
                ButtonSegment(value: 2, label: Text('Automix')),
              ],
              selected: {!s.automix ? 0 : (s.crossfadeOnly ? 1 : 2)},
              onSelectionChanged: (v) {
                final m = v.first;
                setState(() {
                  s.automix = m != 0;
                  if (m != 0) s.crossfadeOnly = m == 1;
                });
                unawaited(AppController.I.applyMix());
              },
            ),
          ),
          if (s.automix && s.crossfadeOnly)
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Row(children: [
                const Text('Crossfade length'),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: '${s.crossfadeSeconds.round()} s',
                    value: s.crossfadeSeconds.clamp(1.0, 12.0),
                    onChanged: (v) => setState(() => s.crossfadeSeconds = v),
                    onChangeEnd: (_) => unawaited(AppController.I.applyMix()),
                  ),
                ),
                Text('${s.crossfadeSeconds.round()} s'),
              ]),
            ),
          if (s.automix && !s.crossfadeOnly) ...[
            _row(
              context,
              leading: const Icon(Icons.auto_fix_high_rounded, size: 26),
              title: 'Pick the length for me',
              sub: 'From each song\'s tempo and length, on whole bars when the beat is known',
              trailing: Switch(
                value: s.automixAuto,
                onChanged: (v) {
                  setState(() => s.automixAuto = v);
                  unawaited(AppController.I.applyMix());
                },
              ),
            ),
            if (!s.automixAuto)
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Row(children: [
                  const Text('Max blend'),
                  Expanded(
                    child: Slider(
                      min: 2,
                      max: 30,
                      divisions: 28,
                      label: '${s.automixSeconds.round()} s',
                      value: s.automixSeconds.clamp(2.0, 30.0),
                      onChanged: (v) => setState(() => s.automixSeconds = v),
                      onChangeEnd: (_) => unawaited(AppController.I.applyMix()),
                    ),
                  ),
                  Text('${s.automixSeconds.round()} s'),
                ]),
              ),
            if (AutomixAnalyzer.supported)
              Padding(
                padding: const EdgeInsets.only(left: 56, right: 20, bottom: 8),
                child: ValueListenableBuilder<String>(
                  valueListenable: AutomixAnalyzer.status,
                  builder: (_, v, __) => Text(v, style: TextStyle(fontSize: 13, color: context.secondaryText)),
                ),
              ),
          ],
          _label(context, 'SOURCES, TRIED IN THIS ORDER'),
          _row(
            context,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('1', style: TextStyle(color: context.secondaryText)),
              const SizedBox(width: 10),
              const Icon(Icons.graphic_eq_rounded, size: 22),
            ]),
            title: 'JioSaavn',
            sub: 'Up to 320 kbps · applies after restart',
            trailing: Switch(value: s.saavnEnabled, onChanged: (v) => setState(() => s.saavnEnabled = v)),
          ),
          _row(
            context,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('2', style: TextStyle(color: context.secondaryText)),
              const SizedBox(width: 10),
              const Icon(Icons.play_circle_fill_rounded, size: 24),
            ]),
            title: 'YouTube Music',
            sub: 'Lossy · Full catalogue · applies after restart',
            trailing: Switch(value: s.youtubeEnabled, onChanged: (v) => setState(() => s.youtubeEnabled = v)),
          ),
          _label(context, 'AUDIO QUALITY'),
          Wrap(spacing: 10, children: [
            for (final i in order)
              ChoiceChip(
                label: Text(qualities[i]),
                selected: s.qualityMode == i,
                showCheckmark: false,
                selectedColor: context.accent,
                labelStyle: TextStyle(color: s.quality == i ? context.onAccent : context.accent, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => s.quality = i),
              ),
          ]),
          const SizedBox(height: 10),
          Text(
            s.qualityMode == 4
                ? '${qualityNote[4]} Now: ${qualities[s.quality]} (speed ${NetworkQuality.describe}).'
                : qualityNote[s.qualityMode],
            style: TextStyle(fontSize: 13, color: context.secondaryText)),
          if (backend.canAddMusic) ...[
            _label(context, 'THIS DEVICE'),
            _row(
              context,
              leading: const Icon(Icons.create_new_folder_outlined, size: 26),
              title: 'Add Music',
              sub: s.musicFolders.isEmpty ? 'Pick a folder or files' : s.musicFolders.join('\n'),
              onTap: backend.addMusic,
            ),
            _row(context, leading: const Icon(Icons.refresh_rounded, size: 26), title: 'Rescan Library', sub: 'Look for new files', onTap: backend.refreshLibrary),
          ],
          _label(context, 'WEB BUILD'),
          Text(
            'Browsers block direct calls to JioSaavn. Point this at a CORS proxy (tools/cors_proxy_worker.js) '
            'ending in ?url= . YouTube search uses the Invidious hosts below; playback uses the YouTube player.',
            style: TextStyle(color: context.secondaryText, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _proxy,
            decoration: const InputDecoration(labelText: 'Proxy URL', hintText: 'https://worker.example.workers.dev/?url='),
            onChanged: (v) => s.proxyUrl = v,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hosts,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Invidious hosts (one per line)'),
            onChanged: (v) => s.invidiousHosts = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          ),
          _label(context, 'ABOUT'),
          Text(
            backend.hasBeatEngine
                ? 'Audio engine: native Media3 with on-device beat detection (Beat This!, ONNX).'
                : (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb && !s.iosCompatEngine)
                    ? 'Audio engine: native iPhone engine (AVAudioEngine): 10-band equalizer, HRTF spatial audio, beat-matched Automix, speaker protection.'
                    : 'Audio engine: mpv (Dart) with tempo and beat analysis for Automix, equalizer and spatial widening.',
            style: TextStyle(color: context.secondaryText, fontSize: 13),
          ),
        ]),
      ),
    );
  }
}
