import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../engine/ios_native_transport.dart';
import 'source.dart';
import 'stream_proxy_stub.dart' if (dart.library.io) 'stream_proxy_io.dart';
import 'yt_trace.dart';
import 'yt_innertube.dart';
import 'ytmusic.dart';

/// YouTube via youtube_explode_dart (iOS, macOS, Windows, Linux). Not usable in browsers.
class YouTubeNativeSource implements MusicSource {
  YouTubeNativeSource([this._settings]) : _yt = YoutubeExplode();
  final _ytm = YtMusicSearch();
  final _tube = YtInnerTube();
  final Settings? _settings;

  final YoutubeExplode _yt;

  @override
  SourceKind get kind => SourceKind.youtube;

  /// Opens the connections and fetches the visitor id now, so the first song starts as fast as the tenth.
  Future<void> warm() async {
    try {
      await _tube.visitor();
    } catch (_) {}
  }

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    // YouTube Music first (clean song results); plain YouTube search only if it returns nothing.
    final music = await _ytm.songs(query, limit: limit);
    if (music.isNotEmpty) return music;
    final results = await _yt.search.search(query);
    final out = <Track>[];
    for (final v in results) {
      final d = v.duration;
      // Skip live streams and mixes; music tracks are short.
      if (d == null || d.inSeconds < 30 || d.inMinutes > 15) continue;
      out.add(
        Track(
          mediaId: TrackKeys.youtube(v.id.value),
          title: decodeEntities(v.title),
          artist: v.author.replaceAll(RegExp(r' - Topic$'), ''),
          durationMs: d.inMilliseconds,
          artworkUri: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
          uri: TrackKeys.youtube(v.id.value),
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  /// One lookup per video at a time (prefetch and play often ask together), and a second full pass when the
  /// first fails quickly: YouTube links fail transiently, so one failure is not final.
  ///
  /// A route only counts once the song has really been downloaded (see [fetchPlayable]): links that answer a
  /// tiny probe but refuse the real transfer are skipped.
  @override
  Future<Playable?> stream(String rawId, {int? quality}) {
    YtTrace.clear();
    return _inflight.putIfAbsent(
      quality == null ? rawId : '$rawId#$quality',
      () async {
        try {
          final sw = Stopwatch()..start();
          for (var attempt = 0; attempt < 2; attempt++) {
            final r = await _resolve(rawId, quality: quality);
            if (r != null) return r;
            if (sw.elapsed > const Duration(seconds: 45))
              break; // already slow: do not make the listener wait twice
            await Future<void>.delayed(const Duration(milliseconds: 700));
          }
          return null;
        } finally {
          _inflight.remove(quality == null ? rawId : '$rawId#$quality');
        }
      },
    );
  }

  final _inflight = <String, Future<Playable?>>{};

  Future<Playable?> _resolve(String rawId, {int? quality}) async {
    final q = quality ?? _settings?.quality ?? 2;
    if (nativeOnlyYoutube) {
      // iPhone: the whole pipeline (player request + download) runs natively, so links and downloader share one stack.
      final r = await IosNativeTransport.ytResolve(
        rawId,
        q,
        (m) => YtTrace.log('native:$m'),
      );
      if (r != null) {
        YtTrace.log('native:${r.client}');
        return Playable.url(r.path);
      }
    }
    try {
      await for (final cand
          in _tube
              .candidates(rawId, quality: q)
              .timeout(const Duration(seconds: 40))) {
        final ok = await fetchPlayable(cand)
            .timeout(const Duration(seconds: 60), onTimeout: () => null);
        if (ok != null) return ok;
      }
    } catch (e) {
      debugPrint('YouTube lookup failed for $rawId: ${'$e'.split('\n').first}');
      YtTrace.log('lookup:${'$e'.split('\n').first}');
    }
    return null;
  }
}
