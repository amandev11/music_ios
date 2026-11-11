import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/recommender.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/playlists.dart';
import 'home.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: AppController.I.settings,
          builder: (context, _) {
            final p = UserPlaylists.all().where((e) => e['id'] == id).firstOrNull;
            if (p == null) return const Center(child: Text('Playlist not found.'));
            final tracks = UserPlaylists.tracks(p);
            final backend = AppController.I.backend;
            return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
              LargeTitle(p['name'] as String,
                  trailing: id == UserPlaylists.likedId
                      ? const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.push_pin_rounded, size: 20))
                      : IconButton(
                    tooltip: 'Delete playlist',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () {
                      UserPlaylists.delete(id);
                      Navigator.of(context).maybePop();
                    },
                  )),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(children: [
                  if (tracks.isNotEmpty) ...[
                    AccentButton(icon: Icons.play_arrow_rounded, label: 'Play', filled: true, onTap: () => backend.playTracks(tracks, 0)),
                    const SizedBox(width: 12),
                    AccentButton(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => backend.playTracks(Recommender(AppController.I.settings).rank(tracks), 0)),
                  ],
                ]),
              ),
              if (tracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Empty. Tap the heart on any song, or use the ⋯ menu to add songs.', style: TextStyle(color: context.secondaryText)),
                ),
              for (var i = 0; i < tracks.length; i++)
                Dismissible(
                  key: ValueKey('${tracks[i].mediaId}$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(color: const Color(0xFF8A2A2A), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: const Icon(Icons.delete_outline_rounded)),
                  onDismissed: (_) => UserPlaylists.removeTrack(id, tracks[i].mediaId),
                  child: TrackRow(track: tracks[i], onTap: () => backend.playTracks(tracks, i)),
                ),
            ]);
          },
        ),
      );
}
