import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import '../widgets/like_button.dart';
import 'lyrics_view.dart';
import 'mesh_background.dart';
import 'queue_view.dart';
import 'side_panels.dart';
import '../widgets/audio_controls.dart';
import '../widgets/particle_grid.dart';
import 'scrubber.dart';
import 'sheet_controller.dart';
import 'visualizer.dart';

enum _Pane { artwork, lyrics, queue }

class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key, required this.sheet});
  final PlayerSheetController sheet;

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  _Pane _pane = _Pane.artwork;
  Timer? _tempoTimer;
  double _bpm = 0;
  bool _spatialAvailable = false;

  @override
  void initState() {
    super.initState();
    final b = AppController.I.backend;
    b.setFrameActive(true);
    b.spatialAvailable().then((v) {
      if (mounted) setState(() => _spatialAvailable = v);
    });
    if (b.hasBeatEngine) {
      _tempoTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        final t = await b.tempo();
        if (mounted) setState(() => _bpm = t?.bpm ?? 0);
      });
    }
  }

  @override
  void dispose() {
    _tempoTimer?.cancel();
    AppController.I.backend.setFrameActive(false);
    super.dispose();
  }

  void _toggle(_Pane p) => setState(() => _pane = _pane == p ? _Pane.artwork : p);

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<Snapshot>(
      valueListenable: backend.snapshot,
      builder: (context, snap, _) {
        final track = snap.current;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        return Stack(fit: StackFit.expand, children: [
          MeshBackground(track: track, frame: backend.frame),
          const Positioned.fill(child: ParticleGrid()),
          SafeArea(
            child: wide ? _wide(context, snap, track) : _compact(context, snap, track),
          ),
        ]);
      },
    );
  }

  // ---- Layouts ------------------------------------------------------------------------------------

  Widget _compact(BuildContext context, Snapshot snap, Track? track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        _grabber(),
        Expanded(
          child: switch (_pane) {
            _Pane.artwork => _dragZone(_nowPlaying(snap, track)),
            _Pane.lyrics => Column(children: [
                _miniHeader(track),
                Expanded(child: LyricsView(track: track)),
              ]),
            _Pane.queue => Column(children: [
                _miniHeader(track),
                const Expanded(child: QueueView()),
              ]),
          },
        ),
        if (_pane == _Pane.artwork) _info(track),
        // One-line synced lyric under the title (same as the desktop layout), hidden while the lyrics pane is open.
        if (_pane == _Pane.artwork) ...[
          const SizedBox(height: 8),
          LyricPreview(track: track),
        ],
        const SizedBox(height: 8),
        const Scrubber(),
        const SizedBox(height: 6),
        _controls(snap),
        const SizedBox(height: 10),
        _toolbar(),
        const SizedBox(height: 10),
      ]),
    );
  }

  Widget _wide(BuildContext context, Snapshot snap, Track? track) {
    final backend = AppController.I.backend;
    final size = MediaQuery.sizeOf(context);
    final art = (size.height - 330).clamp(260.0, 610.0);
    final rightW = (size.width - art - 160).clamp(300.0, 612.0);
    final src = track == null ? '' : (track.album.isNotEmpty ? track.album : track.title);
    final Widget right = switch (_pane) {
      _Pane.lyrics => Column(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: i == 0 ? 0.9 : 0.3)),
                ),
            ]),
          ),
          Expanded(child: LyricsView(track: track, fontSize: 34, blur: true, topPad: 10)),
          const SizedBox(height: 6),
          const Text('Lyrics by LRCLIB', style: TextStyle(fontSize: 15, color: Color(0xB3FFFFFF), decoration: TextDecoration.underline)),
        ]),
      _Pane.queue => const QueuePanel(),
      _Pane.artwork => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(src.isEmpty ? '' : 'Playing from $src', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(track?.title ?? 'Not Playing', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(track?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, color: Color(0x99FFFFFF), fontWeight: FontWeight.w500)),
              ]),
            ),
            if (track != null) LikeButton(track: track, size: 28, color: Colors.white70),
            if (track != null)
              Theme(
                data: ThemeData.dark(),
                child: Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33FFFFFF)),
                  child: TrackMenu(track: track),
                ),
              ),
          ]),
          const SizedBox(height: 22),
          LyricPreview(track: track),
          const SizedBox(height: 10),
          const SizedBox(width: double.infinity, child: Scrubber()),
          const SizedBox(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _bigButton(Icons.fast_rewind_rounded, 64, snap.hasPrevious || snap.currentIndex >= 0, backend.previous),
            GestureDetector(
              onTap: backend.toggle,
              child: SizedBox(
                width: 84,
                height: 84,
                child: Center(
                  child: snap.isBuffering && !snap.isPlaying
                      ? const SizedBox(width: 38, height: 38, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : Icon(snap.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 80, color: Colors.white),
                ),
              ),
            ),
            _bigButton(Icons.fast_forward_rounded, 64, snap.hasNext, backend.next),
          ]),
          const SizedBox(height: 26),
          Row(children: [
            const Icon(Icons.volume_mute_rounded, size: 18, color: Color(0xB3FFFFFF)),
            const Expanded(child: VolumeSlider()),
            const Icon(Icons.volume_up_rounded, size: 18, color: Color(0xB3FFFFFF)),
          ]),
        ]),
    };
    return Column(children: [
      _grabber(),
      Expanded(
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: art,
              height: art,
              child: Column(children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: backend.frame,
                    builder: (_, child) => Transform.scale(scale: 1 + 0.012 * backend.frame.envelope, child: child),
                    child: Artwork(track, radius: 12, px: 900, shadow: true),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 76),
            SizedBox(width: rightW, height: art, child: right),
          ]),
        ),
      ),
      SizedBox(
        width: art,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _roundTool(Icons.format_quote_rounded, _pane == _Pane.lyrics, () => _toggle(_Pane.lyrics)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => showOutputDialog(context),
              child: Container(
                width: 96,
                height: 54,
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(27)),
                child: const Icon(Icons.headphones_rounded, size: 24),
              ),
            ),
            const SizedBox(height: 8),
            Text(AppController.I.settings.outputDevice == 'auto' ? 'System default' : 'Custom output',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xB3FFFFFF))),
          ]),
          _roundTool(Icons.format_list_bulleted_rounded, _pane == _Pane.queue, () => _toggle(_Pane.queue)),
        ]),
      ),
      const SizedBox(height: 26),
    ]);
  }

  Widget _bigButton(IconData icon, double size, bool enabled, VoidCallback onTap) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(width: 90, height: 84, child: Icon(icon, size: size, color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.3))),
      );

  Widget _roundTool(IconData icon, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0x55FFFFFF) : Colors.transparent),
          child: Icon(icon, size: 26),
        ),
      );

  // ---- Pieces -------------------------------------------------------------------------------------

  Widget _grabber() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => widget.sheet.dragBy(d.delta.dy),
        onVerticalDragEnd: (d) => widget.sheet.release(d.primaryVelocity ?? 0),
        onTap: widget.sheet.collapse,
        child: SizedBox(
          height: 36,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: const Color(0x66FFFFFF), borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
      );

  Widget _dragZone(Widget child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => widget.sheet.dragBy(d.delta.dy),
        onVerticalDragEnd: (d) => widget.sheet.release(d.primaryVelocity ?? 0),
        child: child,
      );

  Widget _nowPlaying(Snapshot snap, Track? track) {
    final backend = AppController.I.backend;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 460),
          child: AnimatedScale(
            scale: snap.isPlaying ? 1.0 : 0.86,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            child: AnimatedBuilder(
              animation: backend.frame,
              builder: (_, child) => Transform.scale(scale: 1 + 0.018 * backend.frame.envelope, child: child),
              child: Artwork(track, radius: 14, px: 900, shadow: true),
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      BeatVisualizer(frame: backend.frame, height: 40),
    ]);
  }

  Widget _miniHeader(Track? track) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Artwork(track, size: 52, radius: 8, px: 200),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(track?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Color(0x99FFFFFF))),
            ]),
          ),
        ]),
      );

  Widget _info(Track? track) {
    final backend = AppController.I.backend;
    final badge = track == null ? '' : sourceLabel(track);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(track?.title ?? 'Not Playing',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Row(children: [
            Flexible(
              child: Text(track?.artist ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, color: Color(0xB3FFFFFF))),
            ),
            if (badge.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(badge, style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
            ],
          ]),
          if (backend.hasBeatEngine && _bpm > 0) ...[
            const SizedBox(height: 6),
            Row(children: [
              Text('${_bpm.round()} BPM', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xB3FFFFFF))),
              const SizedBox(width: 10),
              BeatDots(frame: backend.frame),
            ]),
          ],
        ]),
      ),
      if (track != null) LikeButton(track: track, size: 26, color: Colors.white70),
      if (track != null) Theme(data: ThemeData.dark(), child: TrackMenu(track: track)),
    ]);
  }

  Widget _controls(Snapshot snap) {
    final backend = AppController.I.backend;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _iconButton(Icons.skip_previous_rounded, 48, snap.hasPrevious || snap.currentIndex >= 0, backend.previous),
      GestureDetector(
        onTap: backend.toggle,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Center(
            child: snap.isBuffering && !snap.isPlaying
                ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(snap.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(snap.isPlaying), size: 72, color: Colors.white),
                  ),
          ),
        ),
      ),
      _iconButton(Icons.skip_next_rounded, 48, snap.hasNext, backend.next),
    ]);
  }

  Widget _iconButton(IconData icon, double size, bool enabled, VoidCallback onTap) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(icon, size: size, color: Colors.white.withValues(alpha: enabled ? 1 : 0.35)),
        ),
      );

  Widget _toolbar() {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<bool>(
      valueListenable: backend.spatial,
      builder: (context, spatialOn, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _toolButton(Icons.lyrics_outlined, 'Lyrics', _pane == _Pane.lyrics, () => _toggle(_Pane.lyrics)),
        _toolButton(
          Icons.surround_sound_outlined,
          'Spatial',
          spatialOn && _spatialAvailable,
          () {
            if (!_spatialAvailable) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                content: Text('Spatial audio is not available on this device or platform.'),
              ));
              return;
            }
            backend.toggleSpatial();
          },
        ),
        _toolButton(Icons.queue_music_rounded, 'Up Next', _pane == _Pane.queue, () => _toggle(_Pane.queue)),
      ]),
    );
  }

  Widget _toolButton(IconData icon, String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Tooltip(
            message: label,
            child: Icon(icon, size: 24, color: on ? Colors.black : const Color(0xB3FFFFFF)),
          ),
        ),
      );
}
