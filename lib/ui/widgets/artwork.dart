import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../app.dart';
import '../../backend/native_backend.dart';
import '../../core/models.dart';
import '../theme/theme.dart';

/// content:// and file artwork on Android is decoded by the native side and handed over as JPEG.
class NativeArtworkProvider extends ImageProvider<NativeArtworkProvider> {
  const NativeArtworkProvider(this.uri, this.px);
  final String uri;
  final int px;

  @override
  Future<NativeArtworkProvider> obtainKey(ImageConfiguration configuration) =>
      Future.value(this);

  @override
  ImageStreamCompleter loadImage(NativeArtworkProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await NativeBackend.artwork(uri, px);
    if (bytes == null) throw StateError('no artwork for $uri');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is NativeArtworkProvider && other.uri == uri && other.px == px;

  @override
  int get hashCode => Object.hash(uri, px);
}

ImageProvider? artworkProvider(Track? t, {int px = 512}) {
  if (t == null) return null;
  final bytes = t.artworkBytes;
  if (bytes != null) return MemoryImage(bytes);
  final uri = t.artworkUri;
  if (uri == null || uri.isEmpty) return null;
  if (uri.startsWith('http')) {
    return NetworkImage(uri, webHtmlElementStrategy: WebHtmlElementStrategy.fallback);
  }
  if (isNativeAndroid) return NativeArtworkProvider(uri, px);
  return null;
}

class Artwork extends StatelessWidget {
  const Artwork(this.track, {super.key, this.size, this.radius = 8, this.px = 512, this.shadow = false});

  final Track? track;
  final double? size;
  final double radius;
  final int px;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final provider = artworkProvider(track, px: px);
    final placeholder = _Placeholder(radius: radius);
    Widget img = provider == null
        ? placeholder
        : Image(
            image: provider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => placeholder,
            frameBuilder: (_, child, frame, sync) => sync || frame != null
                ? child
                : placeholder,
          );
    img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    if (shadow) {
      img = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 20))],
        ),
        child: img,
      );
    }
    return size == null ? AspectRatio(aspectRatio: 1, child: img) : SizedBox(width: size, height: size, child: img);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.radius});
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDark ? const [Color(0xFF3A3A3C), Color(0xFF1C1C1E)] : const [Color(0xFFE5E5EA), Color(0xFFD1D1D6)],
          ),
        ),
        child: Center(child: Icon(Icons.music_note_rounded, color: context.tertiaryText, size: 28)),
      );
}

/// Dominant colours of the artwork, cached. Sampled in-app (no palette package): the image is decoded
/// at 64 px, pixels are bucketed by hue weighted by saturation x brightness, and the strongest hues
/// become the palette. Falls back to a neutral palette only when the image really cannot be read.
class ArtworkColors {
  static const fallback = [Color(0xFF5B2A86), Color(0xFF3A5AA8), Color(0xFF1F1B3A), Color(0xFF0B0B14)];
  static final Map<String, List<Color>> _cache = {};

  static List<Color>? peek(Track? t) => t == null ? null : _cache[t.artKey];

  static Future<List<Color>> of(Track? t) async {
    if (t == null) return fallback;
    final key = t.artKey;
    final hit = _cache[key];
    if (hit != null) return hit;
    final provider = artworkProvider(t, px: 128);
    if (provider == null) return fallback;
    try {
      final colors = await _sample(ResizeImage(provider, width: 64, height: 64));
      return _cache[key] = colors;
    } catch (e) {
      debugPrint('Artwork colour sampling failed: $e');
      return fallback;
    }
  }

  static Future<List<Color>> _sample(ImageProvider provider) async {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, st) {
        if (!done.isCompleted) done.completeError(e, st);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await done.future.timeout(const Duration(seconds: 12));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('no pixel data');
    const buckets = 24;
    final weight = List<double>.filled(buckets, 0);
    final sr = List<double>.filled(buckets, 0), sg = List<double>.filled(buckets, 0), sb = List<double>.filled(buckets, 0);
    double ar = 0, ag = 0, ab = 0, an = 0, dr = 0, dg = 0, db = 0, dn = 0;
    final n = data.lengthInBytes ~/ 4;
    for (var i = 0; i < n; i++) {
      final r = data.getUint8(i * 4), g = data.getUint8(i * 4 + 1), b = data.getUint8(i * 4 + 2), a = data.getUint8(i * 4 + 3);
      if (a < 128) continue;
      ar += r;
      ag += g;
      ab += b;
      an++;
      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      if (hsv.value < 0.35) {
        dr += r;
        dg += g;
        db += b;
        dn++;
      }
      if (hsv.saturation > 0.22 && hsv.value > 0.18) {
        final k = (hsv.hue / 360 * buckets).floor() % buckets;
        final w = hsv.saturation * hsv.value;
        weight[k] += w;
        sr[k] += r * w;
        sg[k] += g * w;
        sb[k] += b * w;
      }
    }
    if (an == 0) throw StateError('empty image');
    final avg = Color.fromARGB(255, (ar / an).round(), (ag / an).round(), (ab / an).round());
    Color bucketColor(int k) => Color.fromARGB(255, (sr[k] / weight[k]).round(), (sg[k] / weight[k]).round(), (sb[k] / weight[k]).round());

    var best = -1;
    for (var k = 0; k < buckets; k++) {
      if (weight[k] > 0 && (best < 0 || weight[k] > weight[best])) best = k;
    }
    if (best < 0 || weight[best] < n * 0.01) {
      // Near-greyscale artwork: shades of its own average.
      final dark = Color.lerp(avg, Colors.black, 0.55)!;
      return [avg, Color.lerp(avg, Colors.white, 0.18)!, dark, Color.lerp(avg, Colors.black, 0.3)!];
    }
    var second = -1;
    for (var k = 0; k < buckets; k++) {
      final d = (k - best).abs();
      final dist = d < buckets - d ? d : buckets - d;
      if (dist >= 3 && weight[k] > 0 && (second < 0 || weight[k] > weight[second])) second = k;
    }
    final c0 = bucketColor(best);
    final c1 = second >= 0 ? bucketColor(second) : (HSVColor.fromColor(c0).withHue((HSVColor.fromColor(c0).hue + 30) % 360)).toColor();
    final dark = dn > n * 0.04 ? Color.fromARGB(255, (dr / dn).round(), (dg / dn).round(), (db / dn).round()) : Color.lerp(c0, Colors.black, 0.65)!;
    return [c0, c1, dark, Color.lerp(avg, c0, 0.5)!];
  }
}
