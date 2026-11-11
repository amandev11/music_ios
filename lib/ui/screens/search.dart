import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'home.dart';

const _categories = <(String, Color)>[
  ('Bollywood', Color(0xFFE5484D)),
  ('Hip-Hop', Color(0xFF8E4EC6)),
  ('Pop', Color(0xFFE93D82)),
  ('Punjabi', Color(0xFFF76B15)),
  ('Rock', Color(0xFF3E63DD)),
  ('Dance', Color(0xFF12A594)),
  ('Romance', Color(0xFFD6409F)),
  ('Indie', Color(0xFF30A46C)),
  ('Lo-fi', Color(0xFF5B5BD6)),
  ('Workout', Color(0xFFE54D2E)),
  ('Devotional', Color(0xFFAB6400)),
  ('Retro', Color(0xFF0090FF)),
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  /// The sidebar search box posts here; the screen picks it up whether or not it is on screen.
  static final request = ValueNotifier<String>('');

  /// Bumped when the Search tab is double-tapped: clears the box and results and opens the keyboard.
  static final reset = ValueNotifier<int>(0);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _gen = 0;
  int _scope = 0; // 0 online, 1 library
  String _query = '';
  List<Track> _local = const [];
  List<Track>? _songs;
  SearchBundle? _bundle;

  void _onChanged(String q) {
    _debounce?.cancel();
    setState(() => _query = q.trim());
    if (_query.isEmpty) {
      setState(() {
        _local = const [];
        _songs = null;
        _bundle = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(_query));
  }

  Future<void> _run(String q) async {
    final gen = ++_gen;
    final backend = AppController.I.backend;
    setState(() {
      _songs = null;
      _bundle = null;
    });
    backend.searchLocal(q).then((l) {
      if (mounted && gen == _gen) setState(() => _local = l);
    });
    final results = await Future.wait<Object?>([
      backend.searchRemote(q),
      AppController.I.catalog.search(q),
    ]);
    if (!mounted || gen != _gen) return;
    setState(() {
      _songs = results[0] as List<Track>;
      _bundle = results[1] as SearchBundle;
    });
  }

  void _reset() {
    _debounce?.cancel();
    _gen++;
    _controller.clear();
    setState(() {
      _query = '';
      _local = const [];
      _songs = null;
      _bundle = null;
    });
    _focus.requestFocus();
  }

  void _external() {
    final q = SearchScreen.request.value;
    if (q.trim().isNotEmpty) _pick(q.trim());
  }

  @override
  void initState() {
    super.initState();
    SearchScreen.request.addListener(_external);
    SearchScreen.reset.addListener(_reset);
    _external();
  }

  void _pick(String q) {
    _controller.text = q;
    _onChanged(q);
  }

  @override
  void dispose() {
    SearchScreen.request.removeListener(_external);
    SearchScreen.reset.removeListener(_reset);
    _focus.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ListView(
      padding: const EdgeInsets.only(bottom: kListBottomPad),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const LargeTitle('Search'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            Expanded(
              child: CupertinoSearchTextField(
                controller: _controller,
                focusNode: _focus,
                placeholder: 'Artists, Songs, Albums',
                onChanged: _onChanged,
                onSubmitted: (q) {
                  _debounce?.cancel();
                  if (q.trim().isNotEmpty) _run(q.trim());
                },
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                borderRadius: BorderRadius.circular(24),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ]),
        ),
        if (_query.isEmpty) ...[
          const SectionHeader('Browse Categories'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 190).floor().clamp(2, 6);
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final (name, color) in _categories)
                  GestureDetector(
                    onTap: () => _pick(name),
                    child: Container(
                      width: w,
                      height: 84,
                      padding: const EdgeInsets.all(12),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]);
            }),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _scope,
                children: const {
                  0: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Online')),
                  1: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Library')),
                },
                onValueChanged: (v) => setState(() => _scope = v ?? 0),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_scope == 1)
            _local.isEmpty
                ? Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No matches in your library.', style: TextStyle(color: context.secondaryText))))
                : Column(children: [for (var i = 0; i < _local.length; i++) TrackRow(track: _local[i], onTap: () => backend.playTracks(_local, i))])
          else if (_songs == null || _bundle == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CupertinoActivityIndicator()))
          else
            ..._online(context, _songs!, _bundle!),
        ],
      ],
    );
  }

  List<Widget> _online(BuildContext context, List<Track> songs, SearchBundle b) {
    final backend = AppController.I.backend;
    if (songs.isEmpty && b.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No results for "$_query".', style: TextStyle(color: context.secondaryText))))];
    }
    final rows = <Widget>[];
    if (b.topArtist != null) rows.add(_ResultRow(item: b.topArtist!, label: 'Artist'));
    for (var i = 0; i < songs.length; i++) {
      rows.add(_SongResult(track: songs[i], onTap: () => AppController.I.playFromSearch(songs, i)));
    }
    for (final a in b.albums.take(4)) {
      rows.add(_ResultRow(item: a, label: 'Album'));
    }
    for (final p in b.playlists.take(4)) {
      rows.add(_ResultRow(item: p, label: 'Playlist'));
    }
    for (final a in b.artists.take(4)) {
      rows.add(_ResultRow(item: a, label: 'Artist'));
    }
    return rows;
  }
}

/// Artist / album / playlist result: artwork, title, "Kind · detail" and a chevron.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.item, required this.label});
  final CatalogItem item;
  final String label;

  @override
  Widget build(BuildContext context) {
    final circle = item.kind == ItemKind.artist;
    final detail = [label, if (item.subtitle.isNotEmpty && item.kind != ItemKind.artist) item.subtitle].join(' · ');
    return _Row(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(circle ? 34 : 6),
        child: Artwork(item.artTrack, size: 68, radius: 0, px: 200),
      ),
      title: item.title,
      subtitle: detail,
      trailing: Icon(Icons.chevron_right_rounded, color: context.secondaryText),
      onTap: () => openItem(context, item),
    );
  }
}

class _SongResult extends StatelessWidget {
  const _SongResult({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Row(
        leading: Artwork(track, size: 68, radius: 6, px: 200),
        title: track.title,
        subtitle: 'Song · ${track.artist}',
        badge: sourceLabel(track),
        trailing: TrackMenu(track: track),
        onTap: onTap,
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.title, required this.subtitle, required this.trailing, required this.onTap, this.badge = ''});
  final Widget leading;
  final String title;
  final String subtitle;
  final String badge;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 92),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.separator, width: 0.5))),
                child: Row(children: [
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: context.secondaryText)),
                    ]),
                  ),
                  trailing,
                ]),
              ),
            ),
          ]),
        ),
      );
}
