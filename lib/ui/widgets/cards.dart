import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../screens/artist_screen.dart';
import '../screens/collection_screen.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'common.dart';

/// Opens an album, playlist or artist page, or plays a song.
void openItem(BuildContext context, CatalogItem item, {List<Track>? context_}) {
  final nav = Navigator.of(context);
  switch (item.kind) {
    case ItemKind.artist:
      nav.push(CupertinoPageRoute(builder: (_) => ArtistScreen(item: item)));
    case ItemKind.album:
    case ItemKind.playlist:
      nav.push(CupertinoPageRoute(builder: (_) => CollectionScreen(item: item)));
    case ItemKind.song:
      final t = item.track;
      if (t == null) return;
      final list = context_ ?? [t];
      final i = list.indexWhere((e) => e.mediaId == t.mediaId);
      AppController.I.backend.playTracks(list, i < 0 ? 0 : i);
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, this.width = 188, this.onTap});
  final CatalogItem item;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final circle = item.kind == ItemKind.artist;
    return GestureDetector(
      onTap: onTap ?? () => openItem(context, item),
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(circle ? width / 2 : 14),
            child: Artwork(item.artTrack, size: width, radius: 0, px: 400),
          ),
          const SizedBox(height: 8),
          Text(item.title,
              maxLines: 1,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (item.subtitle.isNotEmpty || item.year > 0)
            Text(item.year > 0 && item.subtitle.isEmpty ? '${item.year}' : item.subtitle,
                maxLines: 1,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: context.secondaryText)),
        ]),
      ),
    );
  }
}

/// Large "Top Picks" card: small caps label, title and subtitle above big artwork.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.item, required this.width, required this.label});
  final CatalogItem item;
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openItem(context, item),
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.secondaryText)),
          const SizedBox(height: 2),
          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          Text(item.subtitle.isEmpty ? (item.kind == ItemKind.song ? 'Song' : '') : item.subtitle,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: context.secondaryText)),
          const SizedBox(height: 10),
          Artwork(item.artTrack, size: width, radius: 12, px: 700, shadow: false),
        ]),
      ),
    );
  }
}

/// Wide feature tile: full-bleed artwork under a gradient, label and title laid over the bottom edge.
class FeatureCard extends StatelessWidget {
  const FeatureCard({super.key, required this.item, required this.width, required this.label});
  final CatalogItem item;
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openItem(context, item),
        child: SizedBox(
          width: width,
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(fit: StackFit.expand, children: [
              Artwork(item.artTrack, radius: 0, px: 800),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.35, 1.0], colors: [Color(0x00000000), Color(0xCC000000)]),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))),
                  const SizedBox(height: 4),
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xCCFFFFFF))),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Horizontal shelf of columns with four song rows each, like the real Home screen.
class SongShelf extends StatelessWidget {
  const SongShelf({super.key, required this.items});
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    final tracks = [for (final i in items) if (i.track != null) i.track!];
    final w = MediaQuery.sizeOf(context).width;
    final colW = (w * 0.88).clamp(280.0, 420.0);
    final cols = (items.length / 4).ceil();
    return SizedBox(
      height: 4 * 64.0,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: cols,
        itemBuilder: (context, c) => SizedBox(
          width: colW,
          child: Column(children: [
            for (var r = 0; r < 4; r++)
              if (c * 4 + r < items.length)
                SizedBox(
                  height: 64,
                  child: Builder(builder: (context) {
                    final t = items[c * 4 + r].track;
                    if (t == null) return const SizedBox();
                    return InkWell(
                      onTap: () => backend.playTracks(tracks, tracks.indexWhere((e) => e.mediaId == t.mediaId)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Row(children: [
                          Artwork(t, size: 50, radius: 6, px: 160),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: context.secondaryText)),
                            ]),
                          ),
                          TrackMenu(track: t),
                        ]),
                      ),
                    );
                  }),
                ),
          ]),
        ),
      ),
    );
  }
}

/// One home-page shelf, laid out according to its [SectionStyle].
class SectionShelf extends StatelessWidget {
  const SectionShelf({super.key, required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final Widget body;
    switch (section.style) {
      case SectionStyle.wide:
        final cw = (w * 0.8).clamp(280.0, 400.0);
        body = SizedBox(
          height: 224,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: section.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => FeatureCard(
              item: section.items[i],
              width: cw,
              label: _label(section.items[i], section.caption),
            ),
          ),
        );
      case SectionStyle.songs:
        body = SongShelf(items: section.items);
      case SectionStyle.circle:
        body = _row(section.items, 150);
      case SectionStyle.chart:
      case SectionStyle.square:
        body = _row(section.items, 188);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (section.style == SectionStyle.wide)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(children: [
            Text(section.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(children: [
            Text(section.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ]),
        ),
      body,
    ]);
  }

  String _label(CatalogItem i, String fallback) => switch (i.kind) {
        ItemKind.album => 'New Release',
        ItemKind.playlist => 'Playlist',
        ItemKind.artist => 'Artist',
        ItemKind.song => 'Song',
      };

  Widget _row(List<CatalogItem> items, double size) => SizedBox(
        height: size + 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) => ItemCard(item: items[i], width: size),
        ),
      );
}

class TrackShelf extends StatelessWidget {
  const TrackShelf({super.key, required this.title, required this.tracks});
  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title),
      SizedBox(
        height: 252,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: tracks.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final t = tracks[i];
            return GestureDetector(
              onTap: () => backend.playTracks(tracks, i),
              child: SizedBox(
                width: 188,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Artwork(t, size: 188, radius: 14, px: 400),
                  const SizedBox(height: 8),
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: context.secondaryText)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
