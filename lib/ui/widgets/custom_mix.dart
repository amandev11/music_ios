import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';

/// Per-song custom transition (like Spotify's custom mix): how this song hands over to the next one.
Future<void> showCustomMixDialog(BuildContext context, Track t) async {
  final settings = AppController.I.settings;
  final current = settings.mixOverrides[t.mediaId];
  var mode = '${current?['mode'] ?? 'auto'}';
  var sec = ((current?['sec'] as num?)?.toDouble() ?? 12).clamp(1.0, 30.0);
  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Custom transition'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How "${t.title}" hands over to the next song.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [
                ('auto', 'Auto'),
                ('crossfade', 'Crossfade'),
                ('beat', 'Beat-matched'),
                ('none', 'No blend'),
              ])
                ChoiceChip(label: Text(m.$2), selected: mode == m.$1, onSelected: (_) => setState(() => mode = m.$1)),
            ]),
            if (mode == 'crossfade' || mode == 'beat') ...[
              const SizedBox(height: 14),
              Row(children: [
                const Text('Length'),
                Expanded(
                  child: Slider(min: 1, max: 30, divisions: 29, value: sec, label: '${sec.round()} s', onChanged: (v) => setState(() => sec = v)),
                ),
                Text('${sec.round()} s'),
              ]),
            ],
            const SizedBox(height: 6),
            Text(
              switch (mode) {
                'crossfade' => 'A smooth fade of the length you choose.',
                'beat' => 'Matches the tempo and bar lines of both songs (falls back to a crossfade if they can\'t be analysed).',
                'none' => 'This song plays to its end with no overlap.',
                _ => 'Uses the Automix settings.',
              },
              style: const TextStyle(fontSize: 12),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              settings.setMixOverride(t.mediaId, null);
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              settings.setMixOverride(t.mediaId, mode == 'auto' ? null : {'mode': mode, 'sec': sec});
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
