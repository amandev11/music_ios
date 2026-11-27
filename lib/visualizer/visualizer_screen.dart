import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
import '../core/models.dart';
import '../ui/widgets/artwork.dart';
import 'audio_spectrum_engine.dart';
import 'kinetic_lyrics_view.dart';
import 'viz_scenes.dart';
import 'viz_sheet.dart';

/// Full-screen "Ambient Visualizer & Kinetic Lyrics" mode: a GPU fragment shader driven by the music,
/// synced kinetic lyrics on top, an ambient edge glow, and a floating glass control pill that hides itself.
class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});

  /// Opens the visualizer over whatever is on screen.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, __, ___) => const VisualizerScreen(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
        ),
      );

  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _app = AppController.I;
  late final AudioSpectrumEngine _engine = AudioSpectrumEngine(
    backend: _app.backend,
    positionMs: () => _app.clock.positionMs,
  );
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _colorAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: 1,
  );
  late final Animation<double> _colorT = CurvedAnimation(
    parent: _colorAnim,
    curve: Curves.easeInOutCubic,
  );
  late final AnimationController _hud = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  final Map<String, ui.FragmentShader> _shaders = {};
  final Set<String> _failed = {};
  int _frame = 0;

  List<Color> _from = _defaults;
  List<Color> _to = _defaults;
  static const _defaults = [
    Color(0xFF5B2A86),
    Color(0xFF3A5AA8),
    Color(0xFFB07CFF),
  ];
  String? _trackId;

  double _time = 0;
  Duration _lastTick = Duration.zero;
  bool _appActive = true;
  Timer? _hideTimer;
  final _timeNotifier = ValueNotifier<int>(0);

  bool get _playing => _app.backend.snapshot.value.isPlaying;
  bool get _shouldRun => _appActive && _playing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _app.backend.setFrameActive(true);
    _app.backend.snapshot.addListener(_onSnapshot);
    _app.settings.addListener(_onSettings);
    _loadShader();
    _onSnapshot();
    _syncTicker();
    _kickHud();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.backend.snapshot.removeListener(_onSnapshot);
    _app.backend.setFrameActive(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideTimer?.cancel();
    _ticker.dispose();
    _colorAnim.dispose();
    _hud.dispose();
    _engine.dispose();
    _timeNotifier.dispose();
    _app.settings.removeListener(_onSettings);
    for (final sh in _shaders.values) {
      sh.dispose();
    }
    super.dispose();
  }

  void _onSettings() {
    _loadShader();
    if (mounted) setState(() {});
  }

  Future<void> _loadShader() async {
    final scene = vizSceneById(_app.settings.vizScene);
    if (_shaders.containsKey(scene.id) || _failed.contains(scene.id)) return;
    try {
      final p = await ui.FragmentProgram.fromAsset(scene.asset);
      if (!mounted) return;
      setState(() => _shaders[scene.id] = p.fragmentShader());
    } catch (e) {
      // Old GPUs or web builds without shader support: the gradient backdrop takes over.
      debugPrint('Visualizer scene ${scene.id} unavailable: $e');
      if (mounted) setState(() => _failed.add(scene.id));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _onSnapshot() {
    final s = _app.backend.snapshot.value;
    final t = s.current;
    _engine.setTrack(t);
    if (t?.mediaId != _trackId) {
      _trackId = t?.mediaId;
      unawaited(_loadColors(t));
    }
    _syncTicker();
    if (mounted) setState(() {});
  }

  /// Starts the frame loop only while a song plays in the foreground; otherwise the GPU is idle.
  void _syncTicker() {
    if (_shouldRun) {
      if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _time += dt.clamp(0.0, 0.1);
    // Energy Saver draws every other frame.
    if (_app.settings.vizPreset == 'saver' && (_frame++ & 1) == 1) return;
    _engine.tick(elapsed, playing: true);
    _timeNotifier.value++;
  }

  Future<void> _loadColors(Track? t) async {
    final cols = await ArtworkColors.of(t);
    if (!mounted || t?.mediaId != _trackId) return;
    final primary = cols.isNotEmpty ? cols[0] : _defaults[0];
    final secondary = cols.length > 1 ? cols[1] : _defaults[1];
    final hsl = HSLColor.fromColor(primary);
    final accent = hsl
        .withHue((hsl.hue + 28) % 360)
        .withSaturation(math.max(hsl.saturation, 0.7))
        .withLightness(0.62)
        .toColor();
    // Start the morph from wherever the previous morph currently is.
    _from = _currentColors();
    _to = [primary, secondary, accent];
    _colorAnim.forward(from: 0);
  }

  List<Color> _currentColors() {
    final t = _colorT.value;
    return [for (var i = 0; i < 3; i++) Color.lerp(_from[i], _to[i], t)!];
  }

  // ---- HUD ----------------------------------------------------------------

  void _kickHud() {
    _hideTimer?.cancel();
    if (_hud.value < 1) _hud.forward();
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) _hud.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _app.backend.snapshot.value;
    final track = snap.current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _kickHud(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _kickHud(),
          onPointerMove: (_) => _kickHud(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(child: _backdrop()),
              // Dark scrim keeps white lyrics readable on bright artwork colours.
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x55000000),
                        Color(0x00000000),
                        Color(0x88000000),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 56, 0, 150),
                  child: KineticLyricsView(
                    track: track,
                    spectrum: _engine.data,
                    glow: _to[2],
                  ),
                ),
              ),
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _EdgeGlowPainter(
                      spectrum: _engine.data,
                      colorT: _colorT,
                      colors: _currentColors,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
              _hudLayer(track, snap),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backdrop() {
    final scene = vizSceneById(_app.settings.vizScene);
    final shader = _shaders[scene.id];
    if (shader == null) {
      // Fallback while the shader loads or when it cannot run: a soft animated-colour gradient.
      return AnimatedBuilder(
        animation: Listenable.merge([_colorT, _engine.data]),
        builder: (context, _) {
          final c = _currentColors();
          final bass = _engine.data.value.bass;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.1 + 0.15 * bass,
                colors: [c[0], c[1].withValues(alpha: 0.9), Colors.black],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          );
        },
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _ShaderPainter(
        shader: shader,
        extended: scene.extended,
        intensity: _app.settings.vizIntensity,
        speed: _app.settings.vizSpeed,
        spectrum: _engine.data,
        colors: _currentColors,
        time: () => _time,
        repaint: Listenable.merge([_timeNotifier, _colorT]),
      ),
    );
  }

  Widget _hudLayer(Track? track, Snapshot snap) => FadeTransition(
    opacity: _hud,
    child: AnimatedBuilder(
      animation: _hud,
      builder: (context, child) =>
          IgnorePointer(ignoring: _hud.value < 0.05, child: child),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 8,
              left: 12,
              child: _GlassButton(
                icon: Icons.tune_rounded,
                tooltip: 'Scenes and presets',
                onTap: () {
                  _kickHud();
                  showVizSheet(context);
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 12,
              child: _GlassButton(
                icon: Icons.close_rounded,
                tooltip: 'Exit',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _ControlPill(
                    track: track,
                    playing: snap.isPlaying,
                    onActivity: _kickHud,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---- Painters -----------------------------------------------------------------------------------------

class _ShaderPainter extends CustomPainter {
  _ShaderPainter({
    required this.shader,
    required this.extended,
    required this.intensity,
    required this.speed,
    required this.spectrum,
    required this.colors,
    required this.time,
    required Listenable repaint,
  }) : super(repaint: Listenable.merge([repaint, spectrum]));

  final ui.FragmentShader shader;
  final bool extended;
  final double intensity;
  final double speed;
  final ValueNotifier<AudioSpectrumData> spectrum;
  final List<Color> Function() colors;
  final double Function() time;

  @override
  void paint(Canvas canvas, Size size) {
    final d = spectrum.value;
    final c = colors();
    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, time())
      ..setFloat(i++, d.bass)
      ..setFloat(i++, d.mid)
      ..setFloat(i++, d.treble);
    for (final col in c) {
      shader
        ..setFloat(i++, col.r)
        ..setFloat(i++, col.g)
        ..setFloat(i++, col.b);
    }
    if (extended) {
      shader
        ..setFloat(i++, intensity)
        ..setFloat(i++, speed)
        ..setFloat(i++, d.beatImpulse);
      final b = d.bands;
      for (var k = 0; k < 16; k++) {
        shader.setFloat(i++, b == null ? 0 : b[k].toDouble());
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) =>
      old.shader != shader || old.intensity != intensity || old.speed != speed;
}

class _EdgeGlowPainter extends CustomPainter {
  _EdgeGlowPainter({
    required this.spectrum,
    required this.colorT,
    required this.colors,
  }) : super(repaint: Listenable.merge([spectrum, colorT]));

  final ValueNotifier<AudioSpectrumData> spectrum;
  final Animation<double> colorT;
  final List<Color> Function() colors;

  @override
  void paint(Canvas canvas, Size size) {
    final bass = spectrum.value.bass;
    final accent = colors()[2];
    final spread = 18 + 34 * bass;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spread
      ..color = accent.withValues(alpha: 0.10 + 0.30 * bass)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, spread * 0.8);
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) => false;
}

// ---- HUD widgets ----------------------------------------------------------------------------------------

class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.radius, this.padding});
  final Widget child;
  final double radius;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: child,
      ),
    ),
  );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 44,
    this.iconSize = 24,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: _Glass(
          radius: size / 2,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    ),
  );
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.track,
    required this.playing,
    required this.onActivity,
  });
  final Track? track;
  final bool playing;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    final b = AppController.I.backend;
    return _Glass(
      radius: 32,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Artwork(track, size: 46, radius: 10, px: 128),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      track?.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _GlassButton(
                icon: Icons.skip_previous_rounded,
                tooltip: 'Previous',
                size: 42,
                onTap: () {
                  onActivity();
                  b.previous();
                },
              ),
              const SizedBox(width: 8),
              _GlassButton(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: playing ? 'Pause' : 'Play',
                size: 52,
                iconSize: 30,
                onTap: () {
                  onActivity();
                  b.toggle();
                },
              ),
              const SizedBox(width: 8),
              _GlassButton(
                icon: Icons.skip_next_rounded,
                tooltip: 'Next',
                size: 42,
                onTap: () {
                  onActivity();
                  b.next();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Scrub(onActivity: onActivity),
        ],
      ),
    );
  }
}

class _Scrub extends StatefulWidget {
  const _Scrub({required this.onActivity});
  final VoidCallback onActivity;

  @override
  State<_Scrub> createState() => _ScrubState();
}

class _ScrubState extends State<_Scrub> {
  double? _drag;

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final clock = AppController.I.clock;
    return ListenableBuilder(
      listenable: clock,
      builder: (context, _) {
        final dur = clock.durationMs;
        final frac = _drag ?? clock.fraction.clamp(0.0, 1.0);
        final pos = (_drag != null ? _drag! * dur : clock.positionMs.toDouble())
            .round();
        return Row(
          children: [
            Text(
              _fmt(pos),
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: const Color(0x44FFFFFF),
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  value: frac.toDouble(),
                  onChangeStart: (_) => widget.onActivity(),
                  onChanged: dur > 0 ? (v) => setState(() => _drag = v) : null,
                  onChangeEnd: (v) {
                    setState(() => _drag = null);
                    widget.onActivity();
                    AppController.I.backend.seek((v * dur).round());
                  },
                ),
              ),
            ),
            Text(
              _fmt(dur),
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}
