import 'package:flutter/material.dart';

import '../../app.dart';
import '../../backend/native_backend.dart';
import '../../engine/transport.dart' show AudioOutput;
import '../../platform/audio_route.dart';
import '../theme/theme.dart';

/// Thin white volume slider bound to the backend's master volume.
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key, this.width});
  final double? width;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    final slider = ValueListenableBuilder<double>(
      valueListenable: backend.volume,
      builder: (context, v, _) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: context.accent,
          inactiveTrackColor: context.separator,
          thumbColor: context.accent,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 0,
            disabledThumbRadius: 0,
          ),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: v,
          onChanged: (x) => backend.setVolume(x),
          onChangeEnd: (x) => AppController.I.settings.volume = x,
        ),
      ),
    );
    return width == null ? slider : SizedBox(width: width, child: slider);
  }
}

/// "Audio output - changes take effect immediately." picker. Desktop lists the real devices mpv
/// reports; platforms where the OS owns routing show only "System default".
Future<void> showOutputDialog(BuildContext context) async {
  final backend = AppController.I.backend;
  if (AudioRoute.isIos) {
    final cur = await AudioRoute.current();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _IosOutputDialog(initial: cur),
    );
    return;
  }
  final outputs = await backend.outputs();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _OutputDialog(outputs: outputs),
  );
}

class _OutputDialog extends StatefulWidget {
  const _OutputDialog({required this.outputs});
  final List<AudioOutput> outputs;

  @override
  State<_OutputDialog> createState() => _OutputDialogState();
}

class _OutputDialogState extends State<_OutputDialog> {
  String _selected = AppController.I.settings.outputDevice;

  Future<void> _pick(String id) async {
    setState(() => _selected = id);
    AppController.I.settings.outputDevice = id;
    await AppController.I.backend.setOutput(id);
  }

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      for (final o in widget.outputs)
        (o.id, o.id == 'auto' ? 'System default' : o.name),
    ];
    if (!items.any((e) => e.$1 == 'auto'))
      items.insert(0, ('auto', 'System default'));
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audio output',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Changes take effect immediately.',
                style: TextStyle(color: context.secondaryText),
              ),
              const SizedBox(height: 14),
              for (final (id, name) in items)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _pick(id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (_selected == id)
                          const Icon(Icons.check_rounded, size: 22),
                      ],
                    ),
                  ),
                ),
              if (AppController.I.backend is NativeBackend) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => (AppController.I.backend as NativeBackend)
                      .openOutputSwitcher(),
                  icon: const Icon(Icons.bluetooth_audio_rounded),
                  label: const Text('Bluetooth and cast devices'),
                ),
              ],
              if (widget.outputs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    'This device routes audio itself; change the output from the system sound controls.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iPhone: shows where sound is going and opens Apple's route picker (AirPlay, Bluetooth, speaker).
class _IosOutputDialog extends StatefulWidget {
  const _IosOutputDialog({required this.initial});
  final ({String name, String type}) initial;

  @override
  State<_IosOutputDialog> createState() => _IosOutputDialogState();
}

class _IosOutputDialogState extends State<_IosOutputDialog> {
  late ({String name, String type}) _cur = widget.initial;

  IconData get _icon => switch (_cur.type) {
    'airplay' => Icons.airplay_rounded,
    'bluetooth' => Icons.bluetooth_audio_rounded,
    'headphones' => Icons.headphones_rounded,
    'usb' => Icons.usb_rounded,
    'hdmi' => Icons.tv_rounded,
    _ => Icons.speaker_rounded,
  };

  Future<void> _pick() async {
    await AudioRoute.showPicker();
    // Refresh once the sheet has had time to change the route.
    for (final ms in const [1500, 4000, 9000]) {
      await Future<void>.delayed(
        Duration(milliseconds: ms == 1500 ? 1500 : 2500),
      );
      final c = await AudioRoute.current();
      if (!mounted) return;
      setState(() => _cur = c);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audio output',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(_icon, size: 30, color: context.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _cur.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Playing here now',
                        style: TextStyle(color: context.secondaryText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.airplay_rounded),
                label: const Text('Choose AirPlay or Bluetooth device'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
