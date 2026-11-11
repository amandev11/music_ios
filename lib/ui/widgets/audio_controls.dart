import 'package:flutter/material.dart';

import '../../app.dart';
import '../../engine/transport.dart' show AudioOutput;
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
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0, disabledThumbRadius: 0),
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
      for (final o in widget.outputs) (o.id, o.id == 'auto' ? 'System default' : o.name),
    ];
    if (!items.any((e) => e.$1 == 'auto')) items.insert(0, ('auto', 'System default'));
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Audio output', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Changes take effect immediately.', style: TextStyle(color: context.secondaryText)),
            const SizedBox(height: 14),
            for (final (id, name) in items)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _pick(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(children: [
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500))),
                    if (_selected == id) const Icon(Icons.check_rounded, size: 22),
                  ]),
                ),
              ),
            if (widget.outputs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text('This device routes audio itself; change the output from the system sound controls.',
                    style: TextStyle(fontSize: 13, color: context.secondaryText)),
              ),
          ]),
        ),
      ),
    );
  }
}
