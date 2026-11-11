import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'home.dart';

const _moods = <(String, Color, String)>[
  ('Chill', Color(0xFF7FA6F0), 'chill'),
  ('Commute', Color(0xFFE0A800), 'commute'),
  ('Energize', Color(0xFFE2D074), 'energize workout hits'),
  ('Feel good', Color(0xFF7EDB8A), 'feel good'),
  ('Focus', Color(0xFFB5B5B5), 'focus lofi'),
  ('Party', Color(0xFFA066E0), 'party'),
  ('Romance', Color(0xFFC00000), 'romantic'),
  ('Sad', Color(0xFF8A8A8A), 'sad songs'),
  ('Sleep', Color(0xFF7038C8), 'sleep calm'),
  ('Workout', Color(0xFFE88040), 'workout'),
  ('Bhojpuri', Color(0xFF9A0A98), 'bhojpuri'),
  ('Bengali', Color(0xFFE0D070), 'bengali'),
  ('Devotional', Color(0xFF6A6A6A), 'devotional bhajan'),
  ('Diwali', Color(0xFFD08030), 'diwali'),
  ('Classical', Color(0xFFB0B0B0), 'classical'),
  ('Dance & electronic', Color(0xFF0088B8), 'dance electronic'),
  ('Desi hip-hop', Color(0xFF555555), 'desi hip hop'),
  ('Folk & acoustic', Color(0xFF20902A), 'folk acoustic'),
  ('Gaming', Color(0xFF7A7A8A), 'gaming'),
  ('Family', Color(0xFF1F7090), 'family'),
  ('Punjabi', Color(0xFFF76B15), 'punjabi'),
  ('Retro', Color(0xFF3F8CE0), 'retro 90s'),
  ('Rock', Color(0xFF3E63DD), 'rock'),
  ('Indie', Color(0xFF30A46C), 'indie'),
];

/// Mood and genre tiles; each opens a page of playlists, albums and songs for that mood.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.only(bottom: kListBottomPad, top: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 300).floor().clamp(2, 6);
              final w = (c.maxWidth - (cols - 1) * 16) / cols;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final (name, color, q) in _moods)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => MoodScreen(title: name, query: q, color: color))),
                    child: _MoodTile(name: name, color: color, width: w),
                  ),
              ]);
            }),
          ),
        ],
      );
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({required this.name, required this.color, required this.width});
  final String name;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        height: 130,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: dark)),
          Positioned(left: 0, top: 0, bottom: 0, width: width * 0.28, child: ColoredBox(color: color)),
          Positioned(
            left: 18,
            top: 16,
            right: 12,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key, required this.title, required this.query, required this.color});
  final String title;
  final String query;
  final Color color;

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  late final Future<SearchBundle> _f = AppController.I.catalog.search(widget.query);
  late final Future<List<Track>> _songs = AppController.I.backend.searchRemote('${widget.query} songs');

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: FutureBuilder<List<Object?>>(
          future: Future.wait<Object?>([_f, _songs]),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CupertinoActivityIndicator());
            }
            final b = snap.data?[0] as SearchBundle?;
            final songs = (snap.data?[1] as List<Track>?) ?? const <Track>[];
            return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
              LargeTitle(widget.title),
              if (b != null && b.playlists.isNotEmpty) SectionShelf(section: HomeSection('Playlists', b.playlists, style: SectionStyle.square)),
              if (b != null && b.albums.isNotEmpty) SectionShelf(section: HomeSection('Albums & singles', b.albums, style: SectionStyle.square)),
              if (b != null && b.artists.isNotEmpty) SectionShelf(section: HomeSection('Artists', b.artists, style: SectionStyle.circle)),
              if (songs.isNotEmpty) TrackShelf(title: 'Songs', tracks: songs),
              if ((b == null || (b.playlists.isEmpty && b.albums.isEmpty)) && songs.isEmpty)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Nothing found for this mood.'))),
            ]);
          },
        ),
      );
}
