import 'package:flutter/material.dart';

import '../app.dart';
import 'viz_scenes.dart';

/// Scene picker, presets and the intensity and speed sliders, shown over the visualizer.
Future<void> showVizSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(0xE6101014),
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _VizSheet(),
);

class _VizSheet extends StatelessWidget {
  const _VizSheet();

  @override
  Widget build(BuildContext context) {
    final s = AppController.I.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text(
              'Scene',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final sc in vizScenes)
                  ChoiceChip(
                    avatar: Icon(
                      sc.icon,
                      size: 18,
                      color: s.vizScene == sc.id
                          ? Colors.black
                          : Colors.white70,
                    ),
                    label: Text(sc.name),
                    selected: s.vizScene == sc.id,
                    onSelected: (_) => s.vizScene = sc.id,
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: s.vizScene == sc.id ? Colors.black : Colors.white,
                    ),
                    backgroundColor: const Color(0x22FFFFFF),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Preset',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final p in vizPresets)
                  ChoiceChip(
                    label: Text(p.name),
                    selected: s.vizPreset == p.id,
                    onSelected: (_) {
                      s.vizPreset = p.id;
                      s.vizIntensity = p.intensity;
                      s.vizSpeed = p.speed;
                    },
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: s.vizPreset == p.id ? Colors.black : Colors.white,
                    ),
                    backgroundColor: const Color(0x22FFFFFF),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _slider('Response intensity', s.vizIntensity, 0.3, 2.0, (v) {
              s.vizIntensity = v;
              if (s.vizPreset != 'custom') s.vizPreset = 'custom';
            }),
            _slider('Motion speed', s.vizSpeed, 0.3, 2.0, (v) {
              s.vizSpeed = v;
              if (s.vizPreset != 'custom') s.vizPreset = 'custom';
            }),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double v,
    double min,
    double max,
    ValueChanged<double> on,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          Text(
            v.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
      Slider(value: v.clamp(min, max), min: min, max: max, onChanged: on),
    ],
  );
}
