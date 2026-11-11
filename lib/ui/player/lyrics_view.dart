import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models.dart';
import '../../sources/lyrics.dart';
import '../theme/theme.dart';

/// Time-synced lyrics: the active line is large and bright, others recede; the list follows the
/// song and tapping a line seeks to it.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track, this.fontSize = 30, this.blur = false, this.topPad = 40});
  final Track? track;
  final double fontSize;

  /// Blur lines in proportion to their distance from the active one (BitChord-style).
  final bool blur;
  final double topPad;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  Lyrics? _lyrics;
  bool _loading = true;
  int _active = -2;
  final _scroll = ScrollController();
  List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _fetch();
    AppController.I.clock.addListener(_onTick);
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track?.mediaId != widget.track?.mediaId) _fetch();
  }

  Future<void> _fetch() async {
    final t = widget.track;
    setState(() {
      _loading = true;
      _lyrics = null;
      _active = -2;
    });
    if (t == null) return;
    final l = await AppController.I.lyricsFor(t);
    if (!mounted || widget.track?.mediaId != t.mediaId) return;
    setState(() {
      _lyrics = l;
      _loading = false;
      _keys = List.generate(l?.lines.length ?? 0, (_) => GlobalKey());
    });
  }

  void _onTick() {
    final l = _lyrics;
    if (l == null || !l.synced) return;
    final i = l.activeIndex(AppController.I.clock.positionMs);
    if (i != _active) {
      setState(() => _active = i);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (i < 0 || i >= _keys.length) return;
        final ctx = _keys[i].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.32, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
        }
      });
    }
  }

  @override
  void dispose() {
    AppController.I.clock.removeListener(_onTick);
    _scroll.dispose();
    super.dispose();
  }

  Widget _maybeBlur(Widget w, int distance) {
    return w; // blur was the main source of lyric lag; opacity falloff replaces it
    // ignore: dead_code
    if (!widget.blur || distance <= 0) return w;
    final sigma = (distance * 1.1).clamp(0.0, 4.5);
    return ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal), child: w);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    final l = _lyrics;
    if (l == null) {
      return Center(child: Text('No lyrics found', style: TextStyle(color: context.secondaryText, fontSize: 18)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(24, widget.topPad, 24, MediaQuery.sizeOf(context).height * 0.45),
      itemCount: l.lines.length,
      itemBuilder: (context, i) {
        final line = l.lines[i];
        final active = !l.synced || i == _active;
        final past = l.synced && i < _active;
        if (line.text.isEmpty) return const SizedBox(height: 24);
        final bright = context.accent;
        final style = lyricStyle(widget.fontSize);
        final end = i + 1 < l.lines.length ? l.lines[i + 1].timeMs : line.timeMs + 4500;
        final words = AppController.I.settings.wordLyrics;
        final Widget text = (l.synced && i == _active && words)
            ? _KaraokeLine(text: line.text, startMs: line.timeMs, endMs: end, style: style, bright: bright, dim: bright.withValues(alpha: 0.32))
            : AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: style.copyWith(color: bright.withValues(alpha: l.synced ? (i == _active ? 1.0 : (past ? 0.35 : 0.5)) : 1.0)),
                child: _maybeBlur(Text(line.text), l.synced ? (i - _active).abs() : 0),
              );
        return GestureDetector(
          key: _keys[i],
          behavior: HitTestBehavior.opaque,
          onTap: l.synced ? () => AppController.I.backend.seek(line.timeMs) : null,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: text,
          ),
        );
      },
    );
  }
}

/// Lyric typeface: a geometric display sans with real weight contrast (falls back to the system font
/// until the first download finishes).
TextStyle lyricStyle(double size) =>
    GoogleFonts.plusJakartaSans(fontSize: size, height: 1.22, fontWeight: FontWeight.w800, letterSpacing: -0.6);

/// Active line, filled word by word. LRCLIB only times whole lines, so each word gets a share of the
/// line's duration in proportion to its length. Drawn by one CustomPainter that repaints off the clock
/// (no widget rebuilds, no per-word shader layers): a dim paragraph, then the same paragraph in the bright
/// colour clipped to the filled part of each word.
class _KaraokeLine extends StatelessWidget {
  const _KaraokeLine({required this.text, required this.startMs, required this.endMs, required this.style, required this.bright, required this.dim});
  final String text;
  final int startMs;
  final int endMs;
  final TextStyle style;
  final Color bright;
  final Color dim;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: c.maxWidth);
        return SizedBox(
          width: c.maxWidth,
          height: tp.height,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _KaraokePainter(
                text: text,
                style: style,
                startMs: startMs,
                // Finish the last word a touch early so the line reads as complete before the next begins.
                spanMs: ((endMs - startMs) * 0.9).clamp(600, 12000).toDouble(),
                bright: bright,
                dim: dim,
                clock: AppController.I.clock,
              ),
            ),
          ),
        );
      });
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter({required this.text, required this.style, required this.startMs, required this.spanMs, required this.bright, required this.dim, required this.clock})
      : super(repaint: clock) {
    for (final m in RegExp(r'\S+').allMatches(text)) {
      _ranges.add((m.start, m.end));
      _weights.add((m.end - m.start) + 1.0);
    }
    _total = _weights.fold<double>(0, (a, b) => a + b);
  }

  final String text;
  final TextStyle style;
  final int startMs;
  final double spanMs;
  final Color bright;
  final Color dim;
  final PositionClock clock;
  final _ranges = <(int, int)>[];
  final _weights = <double>[];
  double _total = 1;

  TextPainter? _dimP, _brightP;
  double _laidOutWidth = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (_dimP == null || _laidOutWidth != size.width) {
      _dimP = TextPainter(text: TextSpan(text: text, style: style.copyWith(color: dim)), textDirection: TextDirection.ltr)..layout(maxWidth: size.width);
      _brightP = TextPainter(text: TextSpan(text: text, style: style.copyWith(color: bright)), textDirection: TextDirection.ltr)..layout(maxWidth: size.width);
      _laidOutWidth = size.width;
    }
    _dimP!.paint(canvas, Offset.zero);

    final p = ((clock.positionMs - startMs) / spanMs).clamp(0.0, 1.0);
    final clip = Path();
    var acc = 0.0;
    for (var k = 0; k < _ranges.length; k++) {
      final a = acc / _total;
      acc += _weights[k];
      final b = acc / _total;
      final f = ((p - a) / (b - a)).clamp(0.0, 1.0);
      if (f <= 0) break;
      for (final box in _brightP!.getBoxesForSelection(TextSelection(baseOffset: _ranges[k].$1, extentOffset: _ranges[k].$2))) {
        clip.addRect(Rect.fromLTRB(box.left, box.top, box.left + (box.right - box.left) * f, box.bottom));
      }
    }
    canvas.save();
    canvas.clipPath(clip);
    _brightP!.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KaraokePainter old) => old.text != text || old.startMs != startMs || old.bright != bright || old.dim != dim;
}

/// One-line preview of the active lyric ("Finding the words" while it loads), for the full player.
class LyricPreview extends StatefulWidget {
  const LyricPreview({super.key, required this.track});
  final Track? track;

  @override
  State<LyricPreview> createState() => _LyricPreviewState();
}

class _LyricPreviewState extends State<LyricPreview> {
  Lyrics? _l;
  bool _loading = true;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _fetch();
    AppController.I.clock.addListener(_tick);
  }

  @override
  void didUpdateWidget(LyricPreview old) {
    super.didUpdateWidget(old);
    if (old.track?.mediaId != widget.track?.mediaId) _fetch();
  }

  Future<void> _fetch() async {
    final t = widget.track;
    setState(() {
      _loading = true;
      _l = null;
      _active = -1;
    });
    if (t == null) return;
    final l = await AppController.I.lyricsFor(t);
    if (mounted && widget.track?.mediaId == t.mediaId) setState(() {
      _l = l;
      _loading = false;
    });
  }

  void _tick() {
    final l = _l;
    if (l == null || !l.synced) return;
    final i = l.activeIndex(AppController.I.clock.positionMs);
    if (i != _active) setState(() => _active = i);
  }

  @override
  void dispose() {
    AppController.I.clock.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final text = _loading
        ? 'Finding the words'
        : (l == null ? '' : (l.synced ? (_active >= 0 && _active < l.lines.length ? l.lines[_active].text : '') : ''));
    return SizedBox(
      height: 26,
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0x80FFFFFF))),
    );
  }
}
