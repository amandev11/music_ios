import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/settings.dart';
import 'source.dart';
import '../engine/google_clients.dart';
import 'stream_proxy_stub.dart' if (dart.library.io) 'stream_proxy_io.dart';
import 'yt_fallback.dart';
import 'yt_innertube.dart';
import 'ytmusic.dart';

/// Step-by-step report of every YouTube route, so a failure can be pinpointed from one screenshot.
Stream<String> runYouTubeDiagnostics(Settings settings, {String videoId = 'dQw4w9WgXcQ'}) async* {
  yield 'Test video: $videoId';

  final songs = await YtMusicSearch().songs('Drake', limit: 3);
  yield 'YT Music search: ${songs.isEmpty ? 'FAILED (no results)' : 'ok, ${songs.length} songs, first: ${songs.first.title}'}';

  final tube = YtInnerTube();
  for (final c in InnerTubeClient.all) {
    final r = await tube.player(videoId, c);
    yield '${c.name}: ${r.status}${r.reason.isEmpty ? '' : ' (${r.reason})'}, ${r.formats.length} audio formats';
    if (r.formats.isNotEmpty) {
      final f = r.formats.first;
      final code = await tube.probeStatus(f.url, {'User-Agent': c.userAgent});
      yield '  stream probe: HTTP $code ${code == 200 || code == 206 ? '(playable)' : '(blocked)'}';
      yield '  download test: ${await proxySelfTest(Playable.url(f.url, headers: {'User-Agent': c.userAgent}))}';
    }
  }

  yield 'IFrame fallback (Windows): used automatically when no stream can be downloaded';
  final yt = YoutubeExplode();
  for (final (name, client) in [
    ('explode androidVr', YoutubeApiClient.androidVr),
    ('explode ios', YoutubeApiClient.ios),
    ('explode tv', YoutubeApiClient.tv),
    ('explode safari', YoutubeApiClient.safari),
  ]) {
    try {
      final m = await yt.videos.streamsClient.getManifest(videoId, ytClients: [client]);
      final a = m.audioOnly.toList();
      if (a.isEmpty) {
        yield '$name: manifest has no audio';
        continue;
      }
      final url = a.first.url.toString();
      final code = await tube.probeStatus(url, googleVideoHeaders(url));
      yield '$name: ${a.length} audio streams, probe HTTP $code';
    } catch (e) {
      yield '$name: ERROR ${'$e'.split('\n').first}';
    }
  }
  yt.close();

  final fb = await YtFallback(settings).stream(videoId);
  yield 'Piped/Invidious fallback: ${fb == null ? 'FAILED' : 'ok'}';
  yield 'Done.';
}
