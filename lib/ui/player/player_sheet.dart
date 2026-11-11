import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/glass.dart';
import 'full_player.dart';
import 'sheet_controller.dart';

/// Overlays [child] with the player. The same rounded surface morphs between the floating mini-player
/// pill and the full-screen player: rect, corner radius and cross-fade are all functions of one
/// spring-driven value, and the full player is laid out at final size the whole time so nothing
/// re-flows mid-gesture. The pill is always present ("Not Playing" when the queue is empty).
class PlayerHost extends StatefulWidget {
  const PlayerHost({
    super.key,
    required this.child,
    required this.miniRect,
    this.repaint,
    this.barStyle = false,
  });

  final Widget child;

  /// Where the mini-player pill sits for a given host size; re-evaluated whenever [repaint] fires.
  final Rect Function(Size size) miniRect;
  final Listenable? repaint;

  /// Desktop top-bar pill (square-ish, centred title, progress hairline) instead of the floating phone pill.
  final bool barStyle;

  @override
  State<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends State<PlayerHost> with SingleTickerProviderStateMixin {
  late final PlayerSheetController sheet = PlayerSheetController(this);
  bool _wasOpening = false;

  /// Closes the on-screen keyboard (search field etc.) as soon as the player starts opening.
  void _closeKeyboardWhenOpening() {
    final opening = sheet.animation.value > 0.02;
    if (opening && !_wasOpening) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide').catchError((_) {});
    }
    _wasOpening = opening;
  }

  @override
  void initState() {
    super.initState();
    sheet.animation.addListener(_closeKeyboardWhenOpening);
  }

  @override
  void dispose() {
    sheet.animation.removeListener(_closeKeyboardWhenOpening);
    sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppController.I.backend;
    return ValueListenableBuilder<Snapshot>(
      valueListenable: backend.snapshot,
      builder: (context, snap, _) {
        final hasTrack = snap.current != null;
        return LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final full = Offset.zero & size;
          return AnimatedBuilder(
            animation: Listenable.merge([sheet.animation, if (widget.repaint != null) widget.repaint!]),
            builder: (context, _) {
              final mini = widget.miniRect(size);
              sheet.travel = mini.top.clamp(200.0, 4000.0);
              final t = sheet.animation.value;
              final tc = t.clamp(0.0, 1.0);
              final rect = Rect.lerp(mini, full, t)!;
              final radius = (widget.barStyle ? 6.0 : mini.height / 2) * (1 - tc);
              final miniOpacity = (1 - tc * 4).clamp(0.0, 1.0);
              final fullOpacity = ((tc - 0.12) / 0.55).clamp(0.0, 1.0);
              return PopScope(
                canPop: !(hasTrack && sheet.isExpanded),
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) sheet.collapse();
                },
                child: Stack(children: [
                  Positioned.fill(child: widget.child),
                  Positioned.fromRect(
                    rect: rect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(fit: StackFit.expand, children: [
                        if (miniOpacity > 0)
                          Opacity(
                            opacity: miniOpacity,
                            child: IgnorePointer(
                              ignoring: tc > 0.05,
                              child: widget.barStyle ? _BarPill(snap: snap, sheet: sheet) : _MiniPlayer(snap: snap, sheet: sheet),
                            ),
                          ),
                        if (hasTrack && tc > 0.001)
                          Opacity(
                            opacity: fullOpacity,
                            child: IgnorePointer(
                              ignoring: tc < 0.6,
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minWidth: size.width,
                                maxWidth: size.width,
                                minHeight: size.height,
                                maxHeight: size.height,
                                child: Theme(data: buildTheme(Brightness.dark), child: FullPlayer(sheet: sheet)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ]),
              );
            },
          );
        });
      },
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.snap, required this.sheet});
  final Snapshot snap;
  final PlayerSheetController sheet;

  @override
  Widget build(BuildContext context) {
    final track = snap.current;
    final backend = AppController.I.backend;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: track == null ? null : sheet.expand,
      onVerticalDragUpdate: track == null ? null : (d) => sheet.dragBy(d.delta.dy),
      onVerticalDragEnd: track == null ? null : (d) => sheet.release(d.primaryVelocity ?? 0),
      child: Stack(fit: StackFit.expand, children: [
        Glass(
          blur: 30,
          border: true,
          radius: BorderRadius.circular(40),
          child: const SizedBox.expand(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
          child: Row(children: [
            track == null
                ? Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: context.separator, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.music_note_rounded, color: context.secondaryText, size: 22),
                  )
                : Artwork(track, size: 40, radius: 8, px: 120),
            const SizedBox(width: 12),
            Expanded(
              child: Text(track?.title ?? 'Not Playing',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              onPressed: track == null ? null : backend.toggle,
              icon: snap.isBuffering && !snap.isPlaying && track != null
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(snap.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
            ),
            if (track != null)
              IconButton(
                onPressed: snap.hasNext ? backend.next : null,
                icon: const Icon(Icons.fast_forward_rounded, size: 28),
              ),
          ]),
        ),
      ]),
    );
  }
}


/// BitChord-style now-playing pill for the desktop top bar.
class _BarPill extends StatelessWidget {
  const _BarPill({required this.snap, required this.sheet});
  final Snapshot snap;
  final PlayerSheetController sheet;

  @override
  Widget build(BuildContext context) {
    final track = snap.current;
    final clock = AppController.I.clock;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: track == null ? null : sheet.expand,
      child: Glass(
        radius: BorderRadius.circular(6),
        border: true,
        child: Stack(children: [
          Row(children: [
            track == null
                ? const SizedBox(width: 54, height: 54)
                : Artwork(track, size: 54, radius: 0, px: 160),
            Expanded(
              child: track == null
                  ? Center(child: Icon(Icons.music_note_rounded, color: context.tertiaryText, size: 26))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: context.secondaryText, fontWeight: FontWeight.w600)),
                    ]),
            ),
            const SizedBox(width: 54),
          ]),
          if (track != null)
            Positioned(
              left: 54,
              right: 0,
              bottom: 0,
              height: 2.5,
              child: AnimatedBuilder(
                animation: clock,
                builder: (_, __) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: clock.fraction.clamp(0.0, 1.0), child: Container(color: context.secondaryText)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
