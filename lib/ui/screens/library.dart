import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/settings.dart';
import '../theme/theme.dart';
import '../widgets/playlists.dart';
import 'home.dart';
import 'import_screen.dart';
import 'playlist_screen.dart';

/// Library: "Your listening experience" stat cards, History / Local Music shortcuts and playlists.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.onHistory, required this.onLocal});
  final VoidCallback onHistory;
  final VoidCallback onLocal;

  @override
  Widget build(BuildContext context) {
    final s = AppController.I.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final stats = _Stats.from(s);
        return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad, top: 10), children: [
          SizedBox(
            height: 240,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
              _StatCard(big: '${stats.minutes}', label: 'MINUTES LISTENED', foot: '${stats.plays} plays · All time', since: stats.since),
              _StatCard(big: stats.topArtist, label: 'TOP ARTIST', foot: '${stats.topArtistPlays} plays', since: stats.since),
              _StatCard(big: stats.topSong, label: 'TOP SONG', foot: '${stats.topSongArtist} · ${stats.topSongPlays} plays', since: stats.since),
              _StatCard(big: stats.topAlbum, label: 'TOP ALBUM', foot: '${stats.topAlbumPlays} plays', since: stats.since),
            ]),
          ),
          const SizedBox(height: 8),
          _row(context, Icons.history_rounded, 'History', onHistory),
          _row(context, Icons.folder_rounded, 'Local Music', onLocal),
          _row(context, Icons.playlist_add_rounded, 'Import playlist', () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const ImportScreen()))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
            child: Text('Playlists', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: 250,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
              GestureDetector(
                onTap: () async {
                  final id = await newPlaylistDialog(context);
                  if (id != null && context.mounted) {
                    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => PlaylistScreen(id: id)));
                  }
                },
                child: _tile(context, child: const Icon(Icons.add_rounded, size: 44), title: 'New playlist', sub: 'Saved on this device'),
              ),
              for (final p in UserPlaylists.all())
                GestureDetector(
                  onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => PlaylistScreen(id: p['id'] as String))),
                  child: _tile(context, child: Icon(p['id'] == UserPlaylists.likedId ? Icons.favorite_rounded : Icons.queue_music_rounded, size: 44, color: null), title: p['name'] as String, sub: '${(p['tracks'] as List).length} songs'),
                ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.separator, width: 0.5))),
          child: Row(children: [
            Icon(icon, size: 26),
            const SizedBox(width: 22),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right_rounded, color: context.secondaryText),
          ]),
        ),
      );

  Widget _tile(BuildContext context, {required Widget child, required String title, required String sub}) => SizedBox(
        width: 190,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 174,
              height: 174,
              decoration: BoxDecoration(color: const Color(0xFF262626), borderRadius: BorderRadius.circular(16)),
              child: Center(child: child),
            ),
            const SizedBox(height: 10),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(sub, maxLines: 1, style: TextStyle(fontSize: 14, color: context.secondaryText)),
          ]),
        ),
      );
}

class _Stats {
  _Stats({
    required this.minutes,
    required this.plays,
    required this.topArtist,
    required this.topArtistPlays,
    required this.topSong,
    required this.topSongArtist,
    required this.topSongPlays,
    required this.topAlbum,
    required this.topAlbumPlays,
    required this.since,
  });
  final int minutes, plays, topArtistPlays, topSongPlays, topAlbumPlays;
  final String topArtist, topSong, topSongArtist, topAlbum, since;

  static (String, int) _top(Map<String, int> m) {
    if (m.isEmpty) return ('—', 0);
    final e = m.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (e.key, e.value);
  }

  factory _Stats.from(Settings s) {
    final plays = [for (final p in s.plays) if (p['skip'] != true) p];
    final artists = <String, int>{}, songs = <String, int>{}, albums = <String, int>{};
    final songArtist = <String, String>{};
    for (final p in plays) {
      final a = (p['artist'] as String? ?? '').split(RegExp(r',|&')).first.trim();
      if (a.isNotEmpty) artists[a] = (artists[a] ?? 0) + 1;
      final t = p['title'] as String? ?? '';
      if (t.isNotEmpty) {
        songs[t] = (songs[t] ?? 0) + 1;
        songArtist[t] = p['artist'] as String? ?? '';
      }
      final al = p['album'] as String? ?? '';
      if (al.isNotEmpty) albums[al] = (albums[al] ?? 0) + 1;
    }
    final ta = _top(artists), ts = _top(songs), tl = _top(albums);
    final d = DateTime.fromMillisecondsSinceEpoch(s.firstRunMs);
    return _Stats(
      minutes: (s.listenedMs / 60000).round(),
      plays: plays.length,
      topArtist: ta.$1,
      topArtistPlays: ta.$2,
      topSong: ts.$1,
      topSongArtist: songArtist[ts.$1] ?? '',
      topSongPlays: ts.$2,
      topAlbum: tl.$1 == '—' ? 'Unknown Album' : tl.$1,
      topAlbumPlays: tl.$2,
      since: '${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}',
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.big, required this.label, required this.foot, required this.since});
  final String big, label, foot, since;

  @override
  Widget build(BuildContext context) => Container(
        width: 372,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B4A5E), Color(0xFF1E2630)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('YOUR LISTENING EXPERIENCE', style: TextStyle(fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: Color(0xB3FFFFFF)))),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/icon/icon.png', width: 26, height: 26)),
          ]),
          const Spacer(),
          Text(big, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: Color(0xB3FFFFFF))),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('MUSIC LISTENER', style: TextStyle(fontSize: 13, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                Text(foot, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xB3FFFFFF))),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('MEMBER SINCE', style: TextStyle(fontSize: 9, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))),
              Text(since, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
          ]),
        ]),
      );
}
