import 'dart:async';
import 'package:flutter/material.dart' hide RepeatMode;

import '../../app.dart';
import '../../core/models.dart';
import '../widgets/artwork.dart';

/// Up Next: drag to reorder (committed on drop), swipe to remove, tap to jump.
class QueueView extends StatelessWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<Snapshot>(
      valueListenable: backend.snapshot,
      builder: (context, snap, _) {
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(children: [
              const Expanded(child: Text('Playing Next', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
              _Toggle(
                icon: Icons.all_inclusive_rounded,
                on: snap.automix,
                onTap: () {
                  final settings = AppController.I.settings;
                  settings.automix = !snap.automix;
                  unawaited(AppController.I.applyMix());
                },
              ),
              const SizedBox(width: 8),
              _Toggle(icon: Icons.shuffle_rounded, on: snap.shuffle, onTap: () => backend.setShuffle(!snap.shuffle)),
              const SizedBox(width: 8),
              _Toggle(
                icon: snap.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                on: snap.repeat != RepeatMode.off,
                onTap: backend.cycleRepeat,
              ),
            ]),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 120),
              buildDefaultDragHandles: false,
              itemCount: snap.queue.length,
              onReorder: (from, to) {
                if (to > from) to -= 1;
                backend.move(from, to);
              },
              proxyDecorator: (child, _, __) => Material(color: Colors.transparent, elevation: 6, child: child),
              itemBuilder: (context, i) {
                final t = snap.queue[i];
                final current = i == snap.currentIndex;
                return Dismissible(
                  key: ValueKey('${t.mediaId}#$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: const Color(0xFFFA243C),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) => backend.remove(i),
                  child: InkWell(
                    onTap: () => backend.skipTo(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(children: [
                        Artwork(t, size: 46, radius: 6, px: 160),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: current ? const Color(0xFFFF5A6E) : Colors.white)),
                            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0x99FFFFFF))),
                          ]),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded, color: Color(0x80FFFFFF)),
                          ),
                        ),
                      ]),
                    ),
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

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.on, required this.onTap});
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: on ? Colors.white : const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: on ? Colors.black : Colors.white),
        ),
      );
}
