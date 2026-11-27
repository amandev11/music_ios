import '../core/settings.dart';
import 'source.dart';
import 'stream_proxy_stub.dart' if (dart.library.io) 'stream_proxy_io.dart';
import 'yt/po_token.dart';
import 'yt_innertube.dart';
import 'yt_trace.dart';
import 'ytmusic.dart';

/// Step-by-step report of the YouTube pipeline, so a failure can be pinpointed from one screenshot.
Stream<String> runYouTubeDiagnostics(
  Settings settings, {
  String videoId = 'dQw4w9WgXcQ',
}) async* {
  yield 'Test video: $videoId';

  final songs = await YtMusicSearch().songs('Drake', limit: 3);
  yield 'YT Music search: ${songs.isEmpty ? 'FAILED (no results)' : 'ok, ${songs.length} songs, first: ${songs.first.title}'}';

  final tube = YtInnerTube();
  final visitor = await tube.visitor();
  yield 'Visitor id: ${visitor == null ? 'FAILED' : 'ok'}';

  String? gvs, player;
  if (PoTokenService.available) {
    final sw = Stopwatch()..start();
    final up = await PoTokenService.I.ensure();
    yield 'BotGuard (PO token engine): ${up ? 'running' : 'FAILED: ${PoTokenService.I.lastError}'} (${sw.elapsedMilliseconds} ms)';
    if (up && visitor != null) {
      gvs = await PoTokenService.I.mint(visitor);
      player = await PoTokenService.I.mint(videoId);
      yield 'PO tokens: stream ${gvs == null ? 'FAILED' : 'ok (${gvs.length} chars)'}, player ${player == null ? 'FAILED' : 'ok'}';
    }
  } else {
    yield 'BotGuard: not available on this platform (tokens skipped)';
  }

  for (final step in YtInnerTube.plan) {
    final c = step.client;
    final label = '${c.name} ${c.version}${step.pot ? ' +PO token' : ''}';
    if (step.pot && (gvs == null || player == null)) {
      yield '$label: skipped (no token)';
      continue;
    }
    final r = await tube.player(
      videoId,
      c,
      visitorData: visitor,
      playerPot: step.pot ? player : null,
    );
    yield '$label: ${r.status}${r.reason.isEmpty ? '' : ' (${r.reason})'}, ${r.formats.length} formats';
    if (r.formats.isEmpty) continue;
    final f = r.formats.first;
    final url = step.pot
        ? '${f.url}&pot=${Uri.encodeQueryComponent(gvs!)}'
        : f.url;
    final code = await tube.probeStatus(url, {'User-Agent': c.userAgent});
    yield '  first bytes: HTTP $code ${code == 200 || code == 206 ? '(ok)' : '(blocked)'}';
    yield '  full download: ${await proxySelfTest(Playable.url(url, headers: {'User-Agent': c.userAgent}))}';
  }

  YtTrace.clear();
  var n = 0;
  await for (final cand in tube.candidates(
    videoId,
    quality: settings.quality,
  )) {
    n++;
    final ok = await fetchPlayable(cand);
    yield 'Pipeline candidate $n: ${ok == null ? 'rejected' : 'READY (${ok.url?.split('/').last})'}';
    if (ok != null) break;
  }
  final trace = YtTrace.take();
  if (trace.isNotEmpty) yield 'Trace: $trace';
  yield 'Done.';
}
