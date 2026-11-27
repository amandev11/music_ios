import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
import '../core/models.dart';
import '../sources/lyrics.dart';
import '../ui/widgets/artwork.dart';
import 'audio_spectrum_engine.dart';
import 'lyrics_cache.dart';

/// Time-synced lyrics as kinetic typography: the previous line fades back, the active line is big and
/// pulses with the bass, the next two lines recede with depth blur. Tap a line to seek to it.
/// With no synced lyrics (instrumentals, or nothing found) it crossfades to a large album cover with a
/// bass-reactive glow instead.
class KineticLyricsView extends StatefulWidget {
  const KineticLyricsView({
    super.key,
    required this.track,
    required this.spectrum,
    this.offset = Duration.zero,
    this.glow = const Color(0xFFFFFFFF),
  });

  final Track? track;
  final ValueListenable<AudioSpectrumData> spectrum;

  /// Shifts the lyrics against the audio; positive shows lines earlier.
  final Duration offset;

  /// Colour of the glow behind the fallback album cover.
  final Color glow;

  @override
  State<KineticLyricsView> createState() => _KineticLyricsViewState();
}

enum _Load { loading, synced, none }

class _KineticLyricsViewState extends State<KineticLyricsView> {
  Lyrics? _lyrics;
  _Load _state = _Load.loading;
  int _active = -1;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    AppController.I.clock.addListener(_tick);
  }

  @override
  void didUpdateWidget(KineticLyricsView old) {
    super.didUpdateWidget(old);
    if (old.track?.mediaId != widget.track?.mediaId) _load();
  }

  @override
  void dispose() {
    AppController.I.clock.removeListener(_tick);
    super.dispose();
  }

  Future<void> _load() async {
    final t = widget.track;
    final id = ++_loadId;
    setState(() {
      _state = _Load.loading;
      _lyrics = null;
      _active = -1;
    });
    if (t == null) {
      setState(() => _state = _Load.none);
      return;
    }
    Lyrics? l;
    final (hit, cached) = await LyricsDiskCache.read(t);
    if (hit) {
      l = cached;
    } else {
      // Hard 5 s ceiling on the lookup; whatever the repository does inside, the UI never waits longer.
      try {
        l = await AppController.I
            .lyricsFor(t)
            .timeout(const Duration(seconds: 5));
        await LyricsDiskCache.write(t, l);
      } catch (_) {
        l = null;
      }
    }
    if (!mounted || id != _loadId) return;
    final ok = l != null && l.synced && l.lines.length > 1;
    setState(() {
      _lyrics = ok ? l : null;
      _state = ok ? _Load.synced : _Load.none;
    });
    _tick();
  }

  void _tick() {
    final l = _lyrics;
    if (l == null || _state != _Load.synced) return;
    final pos = AppController.I.clock.positionMs + widget.offset.inMilliseconds;
    final i = l.activeIndex(pos); // binary search, O(log n)
    if (i != _active) setState(() => _active = i);
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 600),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    child: switch (_state) {
      _Load.synced => _Stack(
        key: const ValueKey('lyrics'),
        lines: _lyrics!.lines,
        active: _active,
        spectrum: widget.spectrum,
      ),
      _Load.loading => const SizedBox.expand(key: ValueKey('loading')),
      _Load.none => _CoverFallback(
        key: ValueKey('cover-${widget.track?.mediaId}'),
        track: widget.track,
        spectrum: widget.spectrum,
        glow: widget.glow,
      ),
    },
  );
}

class _Stack extends StatelessWidget {
  const _Stack({
    super.key,
    required this.lines,
    required this.active,
    required this.spectrum,
  });
  final List<LyricLine> lines;
  final int active;
  final ValueListenable<AudioSpectrumData> spectrum;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final size = (w * 0.085).clamp(26.0, 56.0);
    // Slots relative to the active line: -1 previous, 0 active, 1 and 2 upcoming.
    final slots = <int>[-1, 0, 1, 2];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          // Restarts on every line change: the whole stack slides up into place.
          child: TweenAnimationBuilder<double>(
            key: ValueKey(active),
            tween: Tween(begin: 1, end: 0),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, slide, child) => Transform.translate(
              offset: Offset(0, slide * size * 1.6),
              child: child,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in slots)
                  if (active + s >= 0 && active + s < lines.length)
                    _LineTile(
                      key: ValueKey('${active + s}'),
                      text: lines[active + s].text,
                      slot: s,
                      size: size,
                      spectrum: spectrum,
                      onTap: () => AppController.I.backend.seek(
                        lines[active + s].timeMs,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    super.key,
    required this.text,
    required this.slot,
    required this.size,
    required this.spectrum,
    required this.onTap,
  });
  final String text;
  final int slot;
  final double size;
  final ValueListenable<AudioSpectrumData> spectrum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = slot == 0;
    final opacity = switch (slot) {
      -1 => 0.35,
      0 => 1.0,
      1 => 0.45,
      _ => 0.20,
    };
    final scale = slot == -1 ? 0.92 : 1.0;
    final sigma = switch (slot) {
      -1 => 1.5,
      0 => 0.0,
      1 => 1.2,
      _ => 2.6,
    };
    final style = GoogleFonts.plusJakartaSans(
      fontSize: isActive ? size : size * 0.72,
      fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
      height: 1.18,
      letterSpacing: -0.4,
      color: Colors.white,
      shadows: isActive
          ? const [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 14,
                offset: Offset(0, 2),
              ),
              Shadow(
                color: Color(0x66000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    );
    Widget label = Text(
      text.isEmpty ? '♪' : text,
      textAlign: TextAlign.center,
      style: style,
    );
    if (isActive) {
      // Spring scale from 1.0 to 1.05 that breathes with the bass.
      label = ValueListenableBuilder<AudioSpectrumData>(
        valueListenable: spectrum,
        builder: (context, d, child) =>
            Transform.scale(scale: 1.0 + 0.05 * d.bass, child: child),
        child: label,
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 520),
          curve: Curves.elasticOut,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: sigma),
            duration: const Duration(milliseconds: 420),
            builder: (context, s, child) => s < 0.05
                ? child!
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: s,
                      sigmaY: s,
                      tileMode: TileMode.decal,
                    ),
                    child: child,
                  ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: isActive ? 14 : 8),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({
    super.key,
    required this.track,
    required this.spectrum,
    required this.glow,
  });
  final Track? track;
  final ValueListenable<AudioSpectrumData> spectrum;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    final box = MediaQuery.sizeOf(context);
    final side = (box.shortestSide * 0.62).clamp(180.0, 520.0);
    return Center(
      child: ValueListenableBuilder<AudioSpectrumData>(
        valueListenable: spectrum,
        builder: (context, d, child) => Stack(
          alignment: Alignment.center,
          children: [
            // Bass-reactive radial glow behind the cover.
            IgnorePointer(
              child: Container(
                width: side * (1.55 + 0.35 * d.bass),
                height: side * (1.55 + 0.35 * d.bass),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glow.withValues(alpha: 0.28 + 0.38 * d.bass),
                      glow.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Transform.scale(scale: 1.0 + 0.025 * d.bass, child: child),
          ],
        ),
        child: Hero(
          tag: 'cover-${track?.mediaId}',
          child: Artwork(
            track,
            size: side,
            radius: side * 0.07,
            px: 1024,
            shadow: true,
          ),
        ),
      ),
    );
  }
}
