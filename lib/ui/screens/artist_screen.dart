import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'home.dart';

/// Artist page: full-bleed portrait fading into the artwork colour, name, Info / Play / Favourite
/// buttons, then Top Songs, Albums, Singles and Similar Artists.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.item});
  final CatalogItem item;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late final Stream<ArtistPage?> _page = AppController.I.catalog.artistStream(widget.item.id, name: widget.item.title);
  Color _tint = const Color(0xFF3A3A44);
  bool _allSongs = false;

  @override
  void initState() {
    super.initState();
    ArtworkColors.of(widget.item.artTrack).then((c) {
      if (!mounted || c.isEmpty) return;
      setState(() => _tint = Color.lerp(c.first, Colors.black, 0.6)!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    final settings = AppController.I.settings;
    // The artist page is always dark, over a tint taken from the portrait.
    return Theme(
      data: buildTheme(Theme.of(context).brightness),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<ArtistPage?>(
          stream: _page,
          builder: (context, snap) {
            final page = snap.data;
            final loading = !snap.hasData && snap.connectionState == ConnectionState.waiting;
            final name = page?.name ?? widget.item.title;
            final image = Track(mediaId: 'artist:${widget.item.id}', title: name, artist: '', artworkUri: page?.imageUrl ?? widget.item.imageUrl);
            final songs = page?.topSongs ?? const <Track>[];
            final shown = _allSongs ? songs : songs.take(5).toList();
            final width = MediaQuery.sizeOf(context).width;
            final headerH = width.clamp(0.0, 560.0);

            return Stack(children: [
              ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
                SizedBox(
                  height: 400,
                  child: Stack(fit: StackFit.expand, children: [
                    Artwork(image, radius: 0, px: 1200),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.5, 1.0],
                          colors: [context.bg.withValues(alpha: 0.4), context.bg.withValues(alpha: 0), context.bg],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 18,
                      child: Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: -1, color: context.accent)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Row(children: [
                    GestureDetector(
                      onTap: songs.isEmpty ? null : () => backend.playTracks(songs, 0),
                      child: Container(
                        height: 62,
                        padding: const EdgeInsets.symmetric(horizontal: 34),
                        decoration: BoxDecoration(color: context.accent, borderRadius: BorderRadius.circular(31)),
                        child: loading
                            ? SizedBox(width: 24, height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: context.onAccent)))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.play_arrow_rounded, size: 28, color: context.onAccent),
                                const SizedBox(width: 8),
                                Text('Play', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.onAccent)),
                              ]),
                      ),
                    ),
                    const SizedBox(width: 14),
                    _RoundButton(icon: Icons.shuffle_rounded, size: 62, onTap: songs.isEmpty ? () {} : () => backend.playTracks(songs, 0, shuffle: true)),
                    const SizedBox(width: 14),
                    ListenableBuilder(
                      listenable: settings,
                      builder: (_, __) {
                        final fav = settings.favoriteArtists.contains(widget.item.id);
                        return _RoundButton(
                          icon: fav ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 62,
                          onTap: () => settings.toggleFavoriteArtist(widget.item.id),
                        );
                      },
                    ),
                  ]),
                ),
                if (!loading && page == null)
                  const EmptyState(icon: Icons.person_off_outlined, title: 'Artist Unavailable', message: 'This artist page could not be loaded.')
                else ...[
                  if (page != null && (page.followers.isNotEmpty || page.facts.isNotEmpty || page.genres.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final label in [
                          if (page.followers.isNotEmpty) page.followers,
                          if (page.facts.isNotEmpty) page.facts,
                          ...page.genres,
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: context.chipFill, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.separator, width: 0.6)),
                            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                      ]),
                    ),
                  if ((page?.bio ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('About artist', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Text(page!.bio, maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, height: 1.45, color: context.secondaryText)),
                      ]),
                    ),
                  if (songs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
                      child: Row(children: [
                        const Expanded(child: Text('Top songs', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                        TextButton(onPressed: () => setState(() => _allSongs = !_allSongs), child: Text(_allSongs ? 'Show less' : 'Show all')),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: LayoutBuilder(builder: (context, c) {
                        final cols = (c.maxWidth / 420).floor().clamp(1, 3);
                        final w = c.maxWidth / cols;
                        return Wrap(children: [
                          for (var i = 0; i < shown.length; i++)
                            SizedBox(width: w, child: _SongRow(track: shown[i], onTap: () => backend.playTracks(songs, i))),
                        ]);
                      }),
                    ),
                  ],
                  if (page != null && page.albums.isNotEmpty) _Carousel(title: 'Albums', items: page.albums, size: 170),
                  if (page != null && page.singles.isNotEmpty) _Carousel(title: 'Singles & EPs', items: page.singles, size: 150),
                  if (page != null && page.playlists.isNotEmpty) _Carousel(title: 'Playlists', items: page.playlists, size: 150),
                  if (page != null && page.similar.isNotEmpty) _Carousel(title: 'Similar Artists', items: page.similar, size: 124),
                ],
              ]),
              // Floating glass buttons, as in the system back/share controls.
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(children: [
                    _RoundButton(icon: Icons.arrow_back_ios_new_rounded, size: 44, onTap: () => Navigator.of(context).maybePop()),
                    const Spacer(),
                    _RoundButton(
                      icon: Icons.more_horiz_rounded,
                      size: 44,
                      onTap: () => _showBio(context, page),
                    ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  void _showBio(BuildContext context, ArtistPage? page) {
    final bio = page?.bio ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, c) => ListView(controller: c, padding: const EdgeInsets.all(24), children: [
          Text(page?.name ?? widget.item.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if ((page?.followers ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${page!.followers} followers', style: TextStyle(color: context.secondaryText)),
            ),
          const SizedBox(height: 16),
          Text(bio.isEmpty ? 'No biography available.' : bio, style: TextStyle(fontSize: 15, height: 1.4, color: context.secondaryText)),
        ]),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.size, required this.onTap});
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: size,
              height: size,
              color: context.chipFill,
              child: Icon(icon, color: context.accent, size: size * 0.46),
            ),
          ),
        ),
      );
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
          child: Row(children: [
            Artwork(track, size: 54, radius: 6, px: 160),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: context.secondaryText),
                ),
              ]),
            ),
            TrackMenu(track: track),
          ]),
        ),
      );
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.title, required this.items, required this.size});
  final String title;
  final List<CatalogItem> items;
  final double size;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: size + 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => ItemCard(item: items[i], width: size),
          ),
        ),
      ]);
}
