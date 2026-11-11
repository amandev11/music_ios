import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import 'home.dart';

/// Recently played, newest first, with the same row actions as the desktop reference.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppController.I.settings,
        builder: (context, _) {
          final tracks = AppController.I.recentTracks;
          if (tracks.isEmpty) {
            return const EmptyState(icon: Icons.history_rounded, title: 'No History Yet', message: 'Songs you play show up here.');
          }
          final backend = AppController.I.backend;
          return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad, top: 8), children: [
            for (var i = 0; i < tracks.length; i++)
              InkWell(
                onTap: () => backend.playTracks(tracks, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Row(children: [
                    Artwork(tracks[i], size: 66, radius: 8, px: 200),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text('${tracks[i].artist}${tracks[i].durationMs > 0 ? ' · ${formatTime(tracks[i].durationMs)}' : ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: context.secondaryText)),
                      ]),
                    ),
                    TrackMenu(track: tracks[i]),
                  ]),
                ),
              ),
          ]);
        },
      );
}
