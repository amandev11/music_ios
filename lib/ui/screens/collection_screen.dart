import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import 'home.dart';

/// An online album or playlist page.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    final catalog = AppController.I.catalog;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, foregroundColor: context.accent),
      body: FutureBuilder<CollectionPage?>(
        future: item.kind == ItemKind.playlist ? catalog.playlist(item.id) : catalog.album(item.id),
        builder: (context, snap) {
          final page = snap.data;
          final loading = snap.connectionState != ConnectionState.done;
          final tracks = page?.tracks ?? const <Track>[];
          final art = Track(mediaId: 'c:${item.id}', title: item.title, artist: '', artworkUri: page?.imageUrl ?? item.imageUrl);
          final artist = page?.subtitle.isNotEmpty == true ? page!.subtitle : item.subtitle;
          final year = page?.year ?? item.year;
          return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Artwork(art, radius: 12, px: 700, shadow: true)),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(page?.title.isNotEmpty == true ? page!.title : item.title,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            if (artist.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(artist, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, color: context.secondaryText)),
              ),
            Text(
              [item.kind == ItemKind.playlist ? 'Playlist' : 'Album', if (year > 0) '$year'].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.secondaryText),
            ),
            const SizedBox(height: 16),
            if (tracks.isNotEmpty)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AccentButton(icon: Icons.play_arrow_rounded, label: 'Play', filled: true, onTap: () => backend.playTracks(tracks, 0)),
                const SizedBox(width: 12),
                AccentButton(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => backend.playTracks(tracks, 0, shuffle: true)),
              ]),
            const SizedBox(height: 12),
            if (loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (tracks.isEmpty)
              const EmptyState(icon: Icons.music_off_rounded, title: 'No Songs', message: 'This page could not be loaded.')
            else
              for (var i = 0; i < tracks.length; i++)
                TrackRow(
                  track: tracks[i],
                  index: i + 1,
                  showArtwork: item.kind == ItemKind.playlist,
                  onTap: () => backend.playTracks(tracks, i),
                ),
            if (page != null && page.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text(page.description, style: TextStyle(color: context.secondaryText, fontSize: 13)),
              ),
          ]);
        },
      ),
    );
  }
}
