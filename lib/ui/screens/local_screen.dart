import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../widgets/common.dart';
import 'album_screen.dart';
import 'home.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<LibraryData>(
      valueListenable: backend.library,
      builder: (context, lib, _) {
        if (lib.state == LibraryState.needsPermission) {
          return EmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Allow Access to Your Music',
            message: 'Grant audio access to see the music on this device.',
            action: AccentButton(icon: Icons.check_rounded, label: 'Allow Access', filled: true, onTap: backend.requestPermission),
          );
        }
        return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
          LargeTitle('Local Music', trailing: backend.canAddMusic ? IconButton(onPressed: backend.addMusic, icon: const Icon(Icons.add_rounded)) : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _segment,
                children: const {0: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Songs')), 1: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Albums'))},
                onValueChanged: (v) => setState(() => _segment = v ?? 0),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (lib.tracks.isEmpty)
            lib.state == LibraryState.scanning
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CupertinoActivityIndicator()))
                : const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.library_music_outlined, title: 'Library is Empty', message: 'Music on this device shows up here.'),
                  )
          else if (_segment == 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(children: [
                AccentButton(icon: Icons.play_arrow_rounded, label: 'Play', onTap: () => backend.playTracks(lib.tracks, 0)),
                const SizedBox(width: 12),
                AccentButton(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => backend.playTracks(lib.tracks, 0, shuffle: true)),
              ]),
            ),
            for (var i = 0; i < lib.tracks.length; i++)
              TrackRow(track: lib.tracks[i], onTap: () => backend.playTracks(lib.tracks, i)),
          ] else
            Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(builder: (context, c) {
                final cols = (c.maxWidth / 180).floor().clamp(2, 8);
                final w = (c.maxWidth - (cols - 1) * 16) / cols;
                return Wrap(spacing: 16, runSpacing: 20, children: [
                  for (final a in lib.albums)
                    AlbumCard(
                      album: a,
                      width: w,
                      onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => AlbumScreen(album: a))),
                    ),
                ]);
              }),
            ),
        ]);
      },
    );
  }
}
