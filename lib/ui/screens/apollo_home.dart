import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'home.dart' show kListBottomPad;
import 'local_screen.dart';
import 'profile_hub.dart';
import 'profile_screen.dart' show ProfileAvatar;

/// Home of the Apollo style: a big chart hero, Quick picks, ranked chart cards, featured pairs and shelves.
/// Only this style uses it; every other style keeps its own home. Sections come from the same catalogue
/// (YouTube Music charts, playlists and new releases, plus JioSaavn and Deezer) and can be switched on or off
/// in Appearance > Backgrounds > Home layout.
class ApolloHome extends StatefulWidget {
  const ApolloHome({super.key, required this.onSearch});
  final VoidCallback onSearch;

  @override
  State<ApolloHome> createState() => _ApolloHomeState();
}

class _ApolloHomeState extends State<ApolloHome> {
  late Future<List<HomeSection>> _home = AppController.I.catalog.home();

  Future<void> _refresh() async {
    setState(() => _home = AppController.I.catalog.home(refresh: true));
    await _home;
  }

  static bool _songs(HomeSection s) =>
      s.items.length >= 3 && s.items.every((i) => i.track != null);

  static bool _kind(HomeSection s, ItemKind k) =>
      s.items.isNotEmpty &&
      s.items.where((i) => i.kind == k).length * 2 > s.items.length;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return RefreshIndicator(
      color: context.accent,
      onRefresh: _refresh,
      child: ListenableBuilder(
        listenable: AppController.I.settings,
        builder: (context, _) {
          final st = AppController.I.settings;
          return ListView(
            padding: const EdgeInsets.only(bottom: kListBottomPad),
            children: [
              const _Header(),
              FutureBuilder<List<HomeSection>>(
                future: _home,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 100),
                      child: Center(child: CupertinoActivityIndicator()),
                    );
                  }
                  final sections = [...?snap.data];
                  final recents = AppController.I.recentTracks;
                  final children = <Widget>[];

                  // Hero: the first all-songs section (the YouTube chart when it loaded).
                  final heroIx = sections.indexWhere(_songs);
                  HomeSection? hero;
                  if (heroIx >= 0) hero = sections.removeAt(heroIx);
                  if (hero != null && st.homeShows('hero')) {
                    children.add(_HeroRow(section: hero));
                  }

                  // Quick picks: what you played lately, else the next songs section.
                  List<Track> quick = recents.take(5).toList();
                  if (quick.length < 5) {
                    final alt = sections.indexWhere(_songs);
                    if (alt >= 0 && quick.isEmpty) {
                      quick = [
                        for (final i in sections[alt].items.take(5)) i.track!,
                      ];
                    }
                  }
                  if (quick.isNotEmpty && st.homeShows('quick')) {
                    children.add(_QuickPicks(tracks: quick));
                  }

                  var featuredShown = 0;
                  var playlistShelves = 0;
                  for (final s in sections) {
                    if (s.items.isEmpty) continue;
                    if (_songs(s)) {
                      if (st.homeShows('charts')) {
                        children.add(
                          _Shelf(
                            section: s,
                            child: _ChartSongs(section: s),
                          ),
                        );
                      }
                    } else if (_kind(s, ItemKind.artist)) {
                      if (st.homeShows('artists')) {
                        children.add(
                          _Shelf(
                            section: s,
                            child: _Circles(items: s.items),
                          ),
                        );
                      }
                    } else if (_kind(s, ItemKind.album)) {
                      if (st.homeShows('releases')) {
                        children.add(
                          _Shelf(
                            section: s,
                            child: _FeaturedPairs(items: s.items),
                          ),
                        );
                      }
                    } else {
                      if (!st.homeShows('playlists')) continue;
                      playlistShelves++;
                      final chart = s.style == SectionStyle.chart;
                      final featured =
                          !chart &&
                          playlistShelves % 3 == 0 &&
                          featuredShown < 2;
                      if (featured) featuredShown++;
                      children.add(
                        _Shelf(
                          section: s,
                          child: chart
                              ? _ChartCards(items: s.items)
                              : featured
                              ? _FeaturedPairs(items: s.items)
                              : _Squares(items: s.items),
                        ),
                      );
                    }
                  }
                  if (recents.length > 5 && st.homeShows('recent')) {
                    children.add(
                      TrackShelf(
                        title: 'Recently played',
                        tracks: recents.take(20).toList(),
                      ),
                    );
                  }
                  if (sections.isEmpty && hero == null) {
                    children.add(
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Can\'t Load Music',
                          message: 'Check your connection. Saved songs in Downloads still play offline.',
                          action: AccentButton(
                            icon: Icons.refresh_rounded,
                            label: 'Try Again',
                            filled: true,
                            onTap: _refresh,
                          ),
                        ),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  );
                },
              ),
              ValueListenableBuilder<LibraryData>(
                valueListenable: backend.library,
                builder: (context, lib, _) {
                  if (lib.tracks.isEmpty && backend.canAddMusic) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: AccentButton(
                        icon: Icons.add_rounded,
                        label: 'Add Music From This Device',
                        onTap: () => addMusicFlow(context),
                      ),
                    );
                  }
                  if (lib.tracks.isEmpty) return const SizedBox.shrink();
                  return TrackShelf(
                    title: 'On this device',
                    tracks: lib.tracks.take(20).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Home',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => openProfileHub(context),
          child: const ProfileAvatar(size: 42),
        ),
      ],
    ),
  );
}

/// Section title with a chevron; tapping opens the whole shelf.
class _Shelf extends StatelessWidget {
  const _Shelf({required this.section, required this.child});
  final HomeSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => _ShelfPage(section: section)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 26),
            ],
          ),
        ),
      ),
      child,
    ],
  );
}

class _ShelfPage extends StatelessWidget {
  const _ShelfPage({required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final songs = section.items
        .where((i) => i.track != null)
        .map((i) => i.track!)
        .toList();
    final allSongs = songs.length == section.items.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: kListBottomPad),
          children: [
            LargeTitle(section.title),
            if (allSongs) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    AccentButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Play',
                      filled: true,
                      onTap: () => AppController.I.playAround(songs, 0),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < songs.length; i++)
                TrackRow(
                  track: songs[i],
                  onTap: () => AppController.I.playAround(songs, i),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final cols = (c.maxWidth / 170).floor().clamp(2, 8);
                    final w = (c.maxWidth - (cols - 1) * 14) / cols;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 18,
                      children: [
                        for (final it in section.items)
                          ItemCard(item: it, width: w),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Hero: ranked chart songs as big cards ------------------------------------------------------

class _HeroRow extends StatelessWidget {
  const _HeroRow({required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cw = (w * 0.86).clamp(280.0, 460.0);
    final songs = [for (final i in section.items) i.track!];
    return SizedBox(
      height: cw * 0.56 + 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        itemCount: songs.length.clamp(0, 12),
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final t = songs[i];
          final art = artworkProvider(t, px: 900);
          return SizedBox(
            width: cw,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: context.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: context.secondaryText),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => AppController.I.playAround(songs, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (art != null)
                            Image(
                              image: art,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) =>
                                  ColoredBox(color: context.separator),
                            )
                          else
                            ColoredBox(color: context.separator),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0x99000000)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x66000000),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0x44FFFFFF),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Play',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---- Quick picks ----------------------------------------------------------------------------------

class _QuickPicks extends StatelessWidget {
  const _QuickPicks({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Quick picks',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => AppController.I.playAround(tracks, 0),
              child: Text(
                'Play all',
                style: TextStyle(fontSize: 14, color: context.secondaryText),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFF1C1C1E)
                : const Color(0xFFE9E9EE),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.separator.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < tracks.length; i++)
                InkWell(
                  onTap: () => AppController.I.playAround(tracks, i),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: context.tertiaryText,
                            ),
                          ),
                        ),
                        Artwork(tracks[i], size: 54, radius: 8, px: 150),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tracks[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                tracks[i].artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: context.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TrackMenu(track: tracks[i]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

// ---- Shelf bodies ---------------------------------------------------------------------------------

BoxDecoration _cardBox(BuildContext context) => BoxDecoration(
  color: context.isDark ? const Color(0xFF1A1A1C) : const Color(0xFFE9E9EE),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: context.separator.withValues(alpha: 0.45)),
);

/// "CHART  #01" card: rank, title, artist and big cover (songs).
class _ChartSongs extends StatelessWidget {
  const _ChartSongs({required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final songs = [for (final i in section.items) i.track!];
    final cw = (MediaQuery.sizeOf(context).width * 0.62).clamp(220.0, 300.0);
    return SizedBox(
      height: cw + 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: songs.length.clamp(0, 20),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _RankCard(
          width: cw,
          rank: i + 1,
          title: songs[i].title,
          subtitle: songs[i].artist,
          art: songs[i],
          onTap: () => AppController.I.playAround(songs, i),
        ),
      ),
    );
  }
}

/// The same card for playlists and albums of a chart section.
class _ChartCards extends StatelessWidget {
  const _ChartCards({required this.items});
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final cw = (MediaQuery.sizeOf(context).width * 0.62).clamp(220.0, 300.0);
    return SizedBox(
      height: cw + 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length.clamp(0, 20),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _RankCard(
          width: cw,
          rank: i + 1,
          title: items[i].title,
          subtitle: items[i].subtitle,
          art: items[i].artTrack,
          onTap: () => openItem(context, items[i]),
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.width,
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.art,
    required this.onTap,
  });
  final double width;
  final int rank;
  final String title;
  final String subtitle;
  final Track art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: _cardBox(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                size: 18,
                color: context.tertiaryText,
              ),
              const SizedBox(width: 6),
              Text(
                'CHART',
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: context.secondaryText,
                ),
              ),
              const Spacer(),
              Text(
                '#${rank.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: context.secondaryText),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity,
                child: Artwork(art, radius: 0, px: 600),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Squares extends StatelessWidget {
  const _Squares({required this.items});
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    const w = 156.0;
    return SizedBox(
      height: w + 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length.clamp(0, 24),
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => ItemCard(item: items[i], width: w),
      ),
    );
  }
}

class _Circles extends StatelessWidget {
  const _Circles({required this.items});
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 190,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: items.length.clamp(0, 24),
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (_, i) => ItemCard(item: items[i], width: 130),
    ),
  );
}

/// One big card plus two stacked small ones, repeated sideways ("Dancing on your own", "New releases").
class _FeaturedPairs extends StatelessWidget {
  const _FeaturedPairs({required this.items});
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final groupW = (w * 0.92).clamp(300.0, 520.0);
    const h = 236.0;
    final groups = <List<CatalogItem>>[
      for (var i = 0; i < items.length && i < 18; i += 3)
        items.sublist(i, (i + 3).clamp(0, items.length)),
    ];
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, g) {
          final it = groups[g];
          return Container(
            width: groupW,
            padding: const EdgeInsets.all(10),
            decoration: _cardBox(context),
            child: Row(
              children: [
                Expanded(flex: 11, child: _Big(item: it.first)),
                if (it.length > 1) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 9,
                    child: Column(
                      children: [
                        Expanded(child: _Small(item: it[1])),
                        if (it.length > 2) ...[
                          const SizedBox(height: 10),
                          Expanded(child: _Small(item: it[2])),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => openItem(context, item),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(item.artTrack, radius: 0, px: 700),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xAA000000)],
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Small extends StatelessWidget {
  const _Small({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => openItem(context, item),
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF262628)
            : const Color(0xFFDCDCE2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Artwork(item.artTrack, size: 52, radius: 10, px: 200),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.subtitle.isEmpty
                      ? (item.kind == ItemKind.album ? 'Album' : 'Playlist')
                      : item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
