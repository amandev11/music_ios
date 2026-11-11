import 'dart:async';
import 'package:flutter/material.dart' hide RepeatMode;

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/glass.dart';
import 'lyrics_view.dart';

/// Right-hand panel on wide layouts: the queue or the synced lyrics, with a close button.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.title, required this.child, required this.onClose});
  final String title;
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Glass(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
          ),
          Expanded(child: child),
        ]),
      );
}

class LyricsPanel extends StatelessWidget {
  const LyricsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<Snapshot>(
      valueListenable: backend.snapshot,
      builder: (context, snap, _) => Column(children: [
        Expanded(child: LyricsView(track: snap.current, fontSize: 26, blur: true, topPad: 20)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Text('Lyrics by LRCLIB',
              style: TextStyle(fontSize: 14, color: context.secondaryText, decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }
}

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<Snapshot>(
      valueListenable: backend.snapshot,
      builder: (context, snap, _) {
        final cur = snap.currentIndex;
        final current = snap.current;
        final start = cur + 1;
        final upcoming = start < snap.queue.length ? snap.queue.sublist(start) : const <Track>[];
        final settings = AppController.I.settings;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
            child: Text('Now playing', style: TextStyle(fontSize: 17, color: context.secondaryText)),
          ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
              child: Row(children: [
                Artwork(current, size: 54, radius: 6, px: 160),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    Text(current.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: context.secondaryText)),
                  ]),
                ),
                Icon(snap.isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded, size: 22),
              ]),
            )
          else
            Padding(padding: const EdgeInsets.all(24), child: Text('Nothing is playing.', style: TextStyle(color: context.secondaryText))),
          ListTile(
            leading: const Icon(Icons.all_inclusive_rounded),
            title: const Text('Automix', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Crossfade into the next song'),
            trailing: Switch(
              value: snap.automix,
              onChanged: (v) {
                settings.automix = v;
                unawaited(AppController.I.applyMix());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 2),
            child: Text(upcoming.isEmpty ? '' : 'Up next', style: TextStyle(fontSize: 17, color: context.secondaryText)),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              buildDefaultDragHandles: false,
              itemCount: upcoming.length,
              onReorder: (from, to) {
                if (to > from) to -= 1;
                backend.move(start + from, start + to);
              },
              proxyDecorator: (child, _, __) => Material(color: Colors.transparent, elevation: 6, child: child),
              itemBuilder: (context, i) {
                final t = upcoming[i];
                return InkWell(
                  key: ValueKey('${t.mediaId}#${start + i}'),
                  onTap: () => backend.skipTo(start + i),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded, color: context.tertiaryText)),
                      ),
                      Artwork(t, size: 54, radius: 6, px: 160),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: context.secondaryText)),
                        ]),
                      ),
                      IconButton(onPressed: () => backend.remove(start + i), icon: const Icon(Icons.close_rounded, size: 20)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
