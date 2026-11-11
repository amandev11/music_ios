import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/artwork.dart';
import '../widgets/glass.dart';
import 'explore.dart';

const double kListBottomPad = 190;

/// Online home, laid out like the real Home tab: Top Picks hero row, Recently Played, then shelves
/// from the catalogue (new releases, charts, playlists, trending songs, artists).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onSearch});
  final VoidCallback onSearch;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<HomeSection>> _home = AppController.I.catalog.home();

  Future<void> _refresh() async {
    setState(() => _home = AppController.I.catalog.home(refresh: true));
    await _home;
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return RefreshIndicator(
      color: context.accent,
      onRefresh: _refresh,
      child: ListenableBuilder(
        listenable: AppController.I.settings,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
          const _Greeting(),
          FutureBuilder<List<HomeSection>>(
            future: _home,
            builder: (context, snap) {
              final sections = snap.data ?? const <HomeSection>[];
              final recents = AppController.I.recentTracks;
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: CupertinoActivityIndicator()));
              }
              final children = <Widget>[];
              final quick = recents.isNotEmpty
                  ? recents.take(8).toList()
                  : [
                      for (final sec in sections.where((x) => x.style == SectionStyle.songs).take(1))
                        for (final it in sec.items.take(8))
                          if (it.track != null) it.track!
                    ];
              if (quick.isNotEmpty) children.add(_QuickPicks(tracks: quick));
              children.add(const _ForYou());
              final hero = sections.where((s) => s.style == SectionStyle.wide).toList();
              final rest = sections.where((s) => s.style != SectionStyle.wide).toList();
              for (final s in hero) {
                children.add(SectionShelf(section: s));
              }
              if (recents.length > 8) {
                children.add(TrackShelf(title: 'Recently played', tracks: recents.take(20).toList()));
              }
              for (final s in rest) {
                children.add(SectionShelf(section: s));
              }
              if (sections.isEmpty) {
                children.add(Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Can\'t Load Music',
                    message: 'Check your connection. On the web build, set a proxy in Settings so the browser can reach the catalogue.',
                    action: AccentButton(icon: Icons.refresh_rounded, label: 'Try Again', filled: true, onTap: _refresh),
                  ),
                ));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
            },
          ),
          ValueListenableBuilder<LibraryData>(
            valueListenable: backend.library,
            builder: (context, lib, _) {
              if (lib.state == LibraryState.needsPermission) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: AccentButton(icon: Icons.folder_open_rounded, label: 'Allow Access to Music on This Device', onTap: backend.requestPermission),
                );
              }
              if (lib.tracks.isEmpty) {
                return backend.canAddMusic
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: AccentButton(icon: Icons.add_rounded, label: 'Add Music From This Device', onTap: backend.addMusic),
                      )
                    : const SizedBox();
              }
              return TrackShelf(title: 'From Your Library', tracks: lib.tracks.take(20).toList());
            },
          ),
        ]),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  static const _chips = <(String, Color, String)>[
    ('Bollywood', Color(0xFFE5484D), 'bollywood'),
    ('Punjabi', Color(0xFFF76B15), 'punjabi'),
    ('Hip-Hop', Color(0xFF8E4EC6), 'hip hop'),
    ('Pop', Color(0xFFE93D82), 'pop'),
    ('Romance', Color(0xFFD6409F), 'romantic'),
    ('Chill', Color(0xFF3E8FD6), 'chill'),
    ('Party', Color(0xFF12A594), 'party'),
    ('Workout', Color(0xFFE54D2E), 'workout'),
    ('Devotional', Color(0xFFAB6400), 'devotional bhajan'),
  ];

  static String hello(int h) => h < 5
      ? 'Good night'
      : h < 12
          ? 'Good morning'
          : h < 17
              ? 'Good afternoon'
              : h < 21
                  ? 'Good evening'
                  : 'Good night';

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          child: ListenableBuilder(
            listenable: AppController.I.settings,
            builder: (_, __) => StreamBuilder<int>(
              // Re-check every minute so the greeting changes while the app stays open.
              stream: Stream.periodic(const Duration(minutes: 1), (i) => i),
              builder: (_, __) => Text(hello(AppController.I.settings.now.hour),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final (name, color, q) = _chips[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => MoodScreen(title: name, query: q, color: color))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
                  ),
                  child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ]);
}

/// Compact tiles for what you played lately (or today's top songs on a fresh install).
class _QuickPicks extends StatelessWidget {
  const _QuickPicks({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1000 ? 4 : c.maxWidth >= 640 ? 3 : 2;
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          final backend = AppController.I.backend;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (var i = 0; i < tracks.length; i++)
              GestureDetector(
                onTap: () => backend.playTracks(tracks, i),
                child: SizedBox(
                  width: w,
                  height: 64,
                  child: Glass(
                    radius: BorderRadius.circular(14),
                    border: true,
                    child: Row(children: [
                      Artwork(tracks[i], size: 64, radius: 0, px: 160),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tracks[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 10),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
      );
}


/// "Made for you": songs ranked from the listener's own plays, skips and likes.
class _ForYou extends StatelessWidget {
  const _ForYou();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Track>>(
        future: AppController.I.catalog.forYou(),
        builder: (context, snap) {
          final t = snap.data ?? const <Track>[];
          if (t.isEmpty) return const SizedBox.shrink();
          return TrackShelf(title: 'Made for you', tracks: t.take(20).toList());
        },
      );
}
