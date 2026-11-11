import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import 'home.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: context.accent,
      ),
      body: FutureBuilder<List<Track>>(
        future: backend.albumTracks(album),
        builder: (context, snap) {
          final tracks = snap.data ?? const <Track>[];
          return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Artwork(album.asArtTrack, radius: 12, px: 700, shadow: true),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(album.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(album.artist, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: context.secondaryText)),
            if (album.year > 0)
              Text('${album.year}', textAlign: TextAlign.center, style: TextStyle(color: context.secondaryText)),
            const SizedBox(height: 16),
            if (tracks.isNotEmpty)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AccentButton(icon: Icons.play_arrow_rounded, label: 'Play', filled: true, onTap: () => backend.playTracks(tracks, 0)),
                const SizedBox(width: 12),
                AccentButton(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => backend.playTracks(tracks, 0, shuffle: true)),
              ]),
            const SizedBox(height: 12),
            for (var i = 0; i < tracks.length; i++)
              TrackRow(
                track: tracks[i],
                index: tracks[i].trackNumber > 0 ? tracks[i].trackNumber : i + 1,
                showArtwork: false,
                onTap: () => backend.playTracks(tracks, i),
              ),
          ]);
        },
      ),
    );
  }
}
