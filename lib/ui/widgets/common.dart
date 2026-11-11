import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../../sources/registry.dart' show TrackMatch;
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/collection_screen.dart';
import 'artwork.dart';
import 'glass.dart';
import 'custom_mix.dart';
import 'like_button.dart';
import 'playlists.dart';

class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
          if (trailing != null) trailing!,
        ]),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8)});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
      );
}

String sourceLabel(Track t) => switch (t.kind) {
      SourceKind.youtube => 'YouTube',
      SourceKind.saavn => 'JioSaavn',
      SourceKind.local => '',
      SourceKind.meta => '',
    };

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.index,
    this.showArtwork = true,
  });

  final Track track;
  final VoidCallback onTap;
  final int? index;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<Snapshot>(
      valueListenable: backend.snapshot,
      builder: (context, snap, _) {
        final current = snap.current?.mediaId == track.mediaId;
        final badge = sourceLabel(track);
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              if (index != null)
                SizedBox(
                  width: 28,
                  child: Text('$index', style: TextStyle(color: context.secondaryText, fontSize: 15)),
                ),
              if (showArtwork) ...[Artwork(track, size: 48, radius: 6, px: 160), const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500, color: current ? context.secondaryText : null)),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (badge.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: context.tertiaryText, width: 0.7),
                        ),
                        child: Text(badge, style: TextStyle(fontSize: 9.5, color: context.secondaryText)),
                      ),
                    Expanded(
                      child: Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: context.secondaryText)),
                    ),
                  ]),
                ]),
              ),
              if (track.durationMs > 0)
                Text(formatTime(track.durationMs), style: TextStyle(color: context.secondaryText, fontSize: 13)),
              LikeButton(track: track, size: 21),
              TrackMenu(track: track),
            ]),
          ),
        );
      },
    );
  }
}

class TrackMenu extends StatelessWidget {
  const TrackMenu({super.key, required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'More',
        icon: Icon(Icons.more_horiz_rounded, color: context.secondaryText),
        onPressed: () => _open(context),
      );

  void _open(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final anchor = Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height);
    final root = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    final backend = AppController.I.backend;
    final liked = UserPlaylists.isLiked(track.mediaId);
    final hasMix = AppController.I.settings.mixOverrides.containsKey(track.mediaId);
    final artist = _primaryArtist(track.artist);

    final entries = <_MenuEntry>[
      _MenuEntry(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Remove from Liked Songs' : 'Like', () => UserPlaylists.toggleLike(track)),
      _MenuEntry(Icons.playlist_play_rounded, 'Play Next', () => backend.playNext(track)),
      _MenuEntry(Icons.queue_music_rounded, 'Add to Queue', () => backend.addToQueue(track)),
      _MenuEntry(Icons.playlist_add_rounded, 'Add to Playlist', () => addToPlaylistDialog(context, track)),
      if (track.album.trim().isNotEmpty) _MenuEntry(Icons.album_rounded, 'View Album', () => _viewAlbum(context, nav)),
      if (artist.isNotEmpty) _MenuEntry(Icons.person_rounded, 'View Artist', () => _viewArtist(nav, artist)),
      _MenuEntry(Icons.tune_rounded, hasMix ? 'Custom transition (set)' : 'Custom transition', () => showCustomMixDialog(context, track)),
    ];

    root.push(PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, anim, _) => _GlassMenuPage(anchor: anchor, entries: entries, anim: anim),
    ));
  }

  static String _primaryArtist(String raw) {
    final first = raw.split(RegExp(r'\s*(?:,|&|;| feat\.? | ft\.? | x )\s*', caseSensitive: false)).first.trim();
    return first;
  }

  void _viewArtist(NavigatorState nav, String name) {
    nav.push(CupertinoPageRoute<void>(
      builder: (_) => ArtistScreen(item: CatalogItem(kind: ItemKind.artist, id: 'name:$name', title: name)),
    ));
  }

  Future<void> _viewAlbum(BuildContext context, NavigatorState nav) async {
    if (!TrackKeys.isRemote(track.mediaId) && track.albumId > 0) {
      nav.push(CupertinoPageRoute<void>(
        builder: (_) => AlbumScreen(album: Album(id: track.albumId, title: track.album, artist: track.albumArtist ?? track.artist, artworkUri: track.artworkUri)),
      ));
      return;
    }
    try {
      final hits = await AppController.I.catalog.deezer.searchAlbums('${track.album} ${_primaryArtist(track.artist)}', limit: 5);
      final key = TrackMatch.normalize(track.album);
      final match = hits.where((h) => TrackMatch.normalize(h.title) == key).firstOrNull ?? hits.firstOrNull;
      if (match != null) {
        nav.push(CupertinoPageRoute<void>(builder: (_) => CollectionScreen(item: match)));
        return;
      }
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Album not found')));
  }
}

class _MenuEntry {
  const _MenuEntry(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _GlassMenuPage extends StatelessWidget {
  const _GlassMenuPage({required this.anchor, required this.entries, required this.anim});
  final Rect anchor;
  final List<_MenuEntry> entries;
  final Animation<double> anim;

  static const double _w = 248;
  static const double _rowH = 48;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final dark = context.isDark;
    final h = entries.length * _rowH + 12;
    var left = anchor.right - _w;
    left = left.clamp(12.0, size.width - _w - 12);
    var top = anchor.bottom + 4;
    final below = top + h <= size.height - pad.bottom - 12;
    if (!below) top = (anchor.top - h - 4).clamp(pad.top + 8, size.height);
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    return Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: _w,
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            alignment: below ? Alignment.topRight : Alignment.bottomRight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.5 : 0.18), blurRadius: 36, offset: const Offset(0, 14))],
              ),
              child: Glass(
                radius: BorderRadius.circular(22),
                blur: 28,
                border: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final e in entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          splashColor: Colors.white.withValues(alpha: 0.12),
                          highlightColor: Colors.white.withValues(alpha: 0.08),
                          onTap: () {
                            Navigator.of(context).pop();
                            e.onTap();
                          },
                          child: SizedBox(
                            height: _rowH,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: dark ? 0.10 : 0.45),
                                  ),
                                  child: Icon(e.icon, size: 17, color: context.accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, required this.onTap, this.width = 160});
  final Album album;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Artwork(album.asArtTrack, size: width, radius: 10, px: 400),
            const SizedBox(height: 8),
            Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: context.secondaryText)),
          ]),
        ),
      );
}

class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Material(
        color: filled ? context.accent : context.chipFill,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: filled ? context.onAccent : context.accent, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: filled ? context.onAccent : context.accent)),
            ]),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: context.tertiaryText),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.secondaryText)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}
