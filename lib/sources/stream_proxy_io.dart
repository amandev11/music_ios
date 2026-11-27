import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/network_quality.dart';
import 'yt_trace.dart';
import 'source.dart';

/// googlevideo links from the app clients only work with the client's own User-Agent and bounded
/// range requests, and the audio engine cannot open them directly. So the song is downloaded here, with
/// the right headers, into a temporary file (a few MB, about a second) and the engine plays that file:
/// a plain local file always opens, seeks instantly and decodes fine for Automix analysis.
const _piece = 1024 * 1024;
const _parallel = 4;
const _keepFiles = 15;
final _client = http.Client();
final _inflight = <String, Future<File?>>{};

/// Makes [p] playable by the engine: googlevideo streams are served through a loopback proxy that adds the
/// right headers and bounded ranges, so playback starts as soon as the first bytes arrive instead of after
/// a full download. Null when the link is refused (so the caller can try the next candidate). Other URLs
/// pass through untouched.
/// True when the native iPhone engine plays everything: it downloads the song itself (parallel ranges, straight
/// from YouTube) so the loopback proxy is skipped, and only AAC/mp4 streams are accepted.
bool nativeOnlyYoutube = false;

Future<Playable?> fetchPlayable(Playable p) async {
  final url = p.url;
  if (url == null || !url.contains('googlevideo.com')) return p;
  final uri = Uri.parse(url);
  final length = int.tryParse(uri.queryParameters['clen'] ?? '');
  final tag =
      '${uri.queryParameters['c'] ?? '?'}/${uri.queryParameters['itag'] ?? '?'}';
  if (length == null || length <= 0) {
    YtTrace.log('$tag:no-length');
    return null;
  }
  if (nativeOnlyYoutube &&
      (uri.queryParameters['mime'] ?? 'audio/mp4').contains('webm')) {
    YtTrace.log('$tag:webm');
    return null;
  }
  if (!await _probeFirstBytes(p, uri)) {
    YtTrace.log('$tag:probe-refused');
    return null;
  }
  if (nativeOnlyYoutube) {
    // The native engine plays a local file: Dart downloads it (see _download), which is the path known to work.
    // A link that cannot be downloaded is never handed on: the next candidate is tried instead.
    final f = await _download(p);
    if (f == null) YtTrace.log('$tag:download-failed');
    return f == null ? null : Playable.url(f.path, kbps: p.kbps);
  }
  try {
    await _ensureServer();
  } catch (e) {
    debugPrint('Local stream proxy failed to start: $e');
    final f = await _download(p);
    return f == null ? null : Playable.url(f.path, kbps: p.kbps);
  }
  final mime = uri.queryParameters['mime'] ?? 'audio/mp4';
  final ext = mime.contains('webm') ? 'webm' : 'm4a';
  final token =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_routes.length}';
  _routes[token] = _Route(
    uri,
    Map<String, String>.of(p.headers),
    length,
    mime.split(';').first,
    p,
  );
  while (_routes.length > 200) {
    _routes.remove(_routes.keys.first);
  }
  return Playable.url(
    'http://127.0.0.1:${_server!.port}/$token.$ext',
    kbps: p.kbps,
  );
}

/// Reads the first bytes with the real headers: a link that answers a 2-byte probe but refuses the real
/// transfer (HTTP 403 without a PO token) is rejected here, in under a second, instead of mid-song.
/// googlevideo takes the range as a URL parameter (like YouTube's own apps) more reliably than as a header.
Uri _rangeUri(Uri u, int from, int to) =>
    u.replace(queryParameters: {...u.queryParameters, 'range': '$from-$to'});

Future<bool> _probeFirstBytes(Playable p, Uri uri) async {
  final length = int.tryParse(uri.queryParameters['clen'] ?? '') ?? 0;
  if (!await _probeRange(p, uri, 0, 262143, record: true)) return false;
  // Some links serve the first megabyte and then answer 403 (they want a PO token): test deep into the file too,
  // so such a link is rejected now and the next client is tried instead of failing mid-download.
  if (length > 4 * 1024 * 1024) {
    final from = (length * 0.6).floor();
    return _probeRange(p, uri, from, from + 65535, minBytes: 16 * 1024);
  }
  return true;
}

Future<bool> _probeRange(
  Playable p,
  Uri uri,
  int from,
  int to, {
  bool record = false,
  int minBytes = 32 * 1024,
}) async {
  return await _probe(
        p,
        _rangeUri(uri, from, to),
        null,
        to - from + 1,
        minBytes,
        record,
      ) ||
      await _probe(p, uri, 'bytes=$from-$to', to - from + 1, minBytes, record);
}

Future<bool> _probe(
  Playable p,
  Uri uri,
  String? range,
  int want,
  int minBytes,
  bool record,
) async {
  try {
    final r = http.Request('GET', uri)
      ..headers.addAll({...p.headers, if (range != null) 'Range': range});
    final res = await _client.send(r).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 206) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      return false;
    }
    var got = 0;
    final sw = Stopwatch()..start();
    await for (final d in res.stream.timeout(const Duration(seconds: 8))) {
      got += d.length;
      if (got >= want) break;
    }
    // The 256 KB probe doubles as a speed test for Auto quality.
    if (record && got >= 200 * 1024) NetworkQuality.record(got, sw.elapsed);
    return got >= minBytes;
  } catch (_) {
    return false;
  }
}

/// When the player cannot open a proxied URL, fall back to downloading the song to a file (slower, but
/// a local file always opens). Null when [proxied] is not one of ours or the download fails.
Future<Playable?> localCopyFor(Playable proxied) async {
  final url = proxied.url ?? '';
  if (!url.startsWith('http://127.0.0.1:')) {
    // Direct YouTube link (native iPhone engine): download it here with the same client the probe used.
    if (!url.contains('googlevideo.com')) return null;
    final f = await _download(proxied);
    return f == null ? null : Playable.url(f.path, kbps: proxied.kbps);
  }
  final token = Uri.parse(url).pathSegments.last.split('.').first;
  final original = _routes[token]?.original;
  if (original == null) return null;
  final f = await _download(original);
  return f == null ? null : Playable.url(f.path, kbps: original.kbps);
}

class _Route {
  _Route(this.uri, this.headers, this.length, this.mime, this.original);
  final Playable original;
  final Uri uri;
  final Map<String, String> headers;
  final int length;
  final String mime;
}

const _proxyChunk = 2 * 1024 * 1024;
final _routes = <String, _Route>{};
HttpServer? _server;

Future<void> _ensureServer() async {
  if (_server != null) return;
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _server = s;
  s.listen((req) => unawaited(_serve(req)), onError: (_) {});
}

/// Serves one range request from the player by pulling bounded ranges from googlevideo and piping them on.
Future<void> _serve(HttpRequest req) async {
  final res = req.response;
  var closed = false;
  res.done.then((_) => closed = true, onError: (_) => closed = true);
  try {
    final name = req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.first;
    final route = _routes[name.split('.').first];
    if (route == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    var start = 0;
    var end = route.length - 1;
    var partial = false;
    final m = RegExp(r'bytes=(\d*)-(\d*)')
        .firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (m != null) {
      final a = m.group(1) ?? '', b = m.group(2) ?? '';
      if (a.isEmpty && b.isNotEmpty) {
        start = math.max(0, route.length - int.parse(b));
      } else if (a.isNotEmpty) {
        start = int.parse(a);
        if (b.isNotEmpty) end = math.min(end, int.parse(b));
      }
      partial = true;
    }
    if (start > end || start >= route.length) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${route.length}',
      );
      await res.close();
      return;
    }
    Future<http.StreamedResponse> openChunk(int from) async {
      final to = math.min(end, from + _proxyChunk - 1);
      final up = http.Request('GET', route.uri)
        ..headers.addAll({...route.headers, 'Range': 'bytes=$from-$to'});
      final got = await _client.send(up).timeout(const Duration(seconds: 20));
      if (got.statusCode != 200 && got.statusCode != 206) {
        unawaited(got.stream.drain<void>().catchError((_) {}));
        throw HttpException('upstream HTTP ${got.statusCode}');
      }
      return got;
    }

    // Open the first chunk before answering: if YouTube refuses, the player gets a clean 502, not a broken 200.
    var pending = req.method == 'HEAD' ? null : await openChunk(start);
    res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, route.mime)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentLengthHeader, '${end - start + 1}');
    if (partial)
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${route.length}',
      );
    if (pending == null) {
      await res.close();
      return;
    }
    var pos = start;
    while (pos <= end && !closed) {
      final got = pending ?? await openChunk(pos);
      pending = null;
      final to = math.min(end, pos + _proxyChunk - 1);
      final before = pos;
      await for (final data in got.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (closed) break;
        res.add(data);
        pos += data.length;
        await res.flush();
        if (pos > to) break;
      }
      if (pos == before && !closed)
        throw const HttpException('upstream returned no data');
    }
    await res.close();
  } catch (e) {
    debugPrint('Stream proxy: $e');
    try {
      res.statusCode =
          HttpStatus.badGateway; // only takes effect if nothing was sent yet
    } catch (_) {}
    try {
      await res.close();
    } catch (_) {}
  }
}

Future<Playable> proxyPlayable(Playable p) async {
  final f = await _download(p);
  return f == null ? p : Playable.url(f.path, kbps: p.kbps);
}

/// For the diagnostics screen: downloads the stream and reports what happened.
Future<String> proxySelfTest(Playable p) async {
  final sw = Stopwatch()..start();
  try {
    final f = await _download(p, force: true);
    if (f == null) return 'FAILED (see console)';
    return 'downloaded ${(await f.length()) ~/ 1024} KB in ${sw.elapsedMilliseconds} ms -> ${f.path}';
  } catch (e) {
    return 'ERROR $e';
  }
}

Future<File?> _download(
  Playable p, {
  bool force = false,
  void Function(double)? progress,
}) {
  final url = p.url;
  if (url == null || !url.contains('googlevideo.com'))
    return Future.value(null);
  final uri = Uri.parse(url);
  final length = int.tryParse(uri.queryParameters['clen'] ?? '');
  if (length == null || length <= 0 || length > 250 * 1024 * 1024)
    return Future.value(null);
  final id = (uri.queryParameters['id'] ?? '${url.hashCode}').replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
  final mime = uri.queryParameters['mime'] ?? 'audio/mp4';
  final ext = mime.contains('webm') ? 'webm' : 'm4a';
  return _inflight.putIfAbsent('$id.$ext', () async {
    try {
      final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}music_audio_cache',
      );
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}$id.$ext');
      if (!force && await file.exists() && await file.length() == length)
        return file;
      final part = File('${file.path}.part');
      if (await part.exists()) await part.delete();
      final raf = await part.open(mode: FileMode.write);
      try {
        await raf.truncate(length);
        // Several 1 MB pieces at once, all through Dart's own HTTP client: the same network path that asked YouTube
        // for the link, so the link's address binding matches (a different stack can be refused with HTTP 403).
        final pieces = <int>[
          for (var pos = 0; pos < length; pos += _piece) pos,
        ];
        var next = 0;
        var failed = false;
        var doneBytes = 0;
        final total = Stopwatch()..start();
        Future<void> worker() async {
          try {
            while (!failed) {
              final i = next++;
              if (i >= pieces.length) return;
              final from = pieces[i];
              final to = math.min(length - 1, from + _piece - 1);
              final data = await _fetchPiece(p, uri, from, to);
              if (failed) return;
              await _writeAt(raf, from, data);
              doneBytes += data.length;
              progress?.call((doneBytes / length).clamp(0.0, 1.0));
            }
          } catch (_) {
            failed = true; // stop the other workers; the caller sees the error
            rethrow;
          }
        }

        await Future.wait([for (var w = 0; w < _parallel; w++) worker()]);
        NetworkQuality.record(length, total.elapsed);
      } finally {
        await raf.close();
      }
      if (await part.length() != length)
        throw HttpException('short download ${await part.length()} of $length');
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      unawaited(_evict(dir));
      return file;
    } catch (e) {
      debugPrint('YouTube download failed: $e');
      YtTrace.log(
        'dl:${'$e'.split('\n').first.replaceAll('HttpException: ', '')}',
      );
      return null;
    } finally {
      _inflight.remove('$id.$ext');
    }
  });
}

Future<void> _evict(Directory dir) async {
  try {
    final files = [
      for (final e in await dir.list().toList())
        if (e is File && !e.path.endsWith('.part')) e,
    ];
    if (files.length <= _keepFiles) return;
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    for (final f in files.take(files.length - _keepFiles)) {
      await f.delete();
    }
  } catch (_) {}
}

Future<void> _writeAt(RandomAccessFile raf, int at, List<int> data) async {
  // One writer at a time: RandomAccessFile has a single position.
  final prev = _writeLock;
  final done = Completer<void>();
  _writeLock = done.future;
  await prev;
  try {
    await raf.setPosition(at);
    await raf.writeFrom(data);
  } finally {
    done.complete();
  }
}

Future<void> _writeLock = Future.value();

/// One byte range, asked for as a URL parameter first and as a Range header second, retried a few times.
Future<List<int>> _fetchPiece(Playable p, Uri uri, int from, int to) async {
  Object? last;
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      final viaUrl = attempt.isEven;
      final r = http.Request('GET', viaUrl ? _rangeUri(uri, from, to) : uri)
        ..headers.addAll({
          ...p.headers,
          if (!viaUrl) 'Range': 'bytes=$from-$to',
        });
      final res = await _client.send(r).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 && res.statusCode != 206) {
        unawaited(res.stream.drain<void>().catchError((_) {}));
        throw HttpException('upstream HTTP ${res.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final d in res.stream.timeout(const Duration(seconds: 30))) {
        bytes.add(d);
      }
      if (bytes.length != to - from + 1)
        throw HttpException('short piece ${bytes.length} of ${to - from + 1}');
      return bytes.takeBytes();
    } catch (e) {
      last = e;
      await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
    }
  }
  throw last ?? const HttpException('download failed');
}

// ---- Keeping songs for offline play ---------------------------------------------------------------

Future<Directory> _keepDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}downloads');
  await d.create(recursive: true);
  return d;
}

/// Folder holding saved songs (the app-support folder, which the OS never clears).
Future<String> keepDirPath() async => (await _keepDir()).path;

/// Saves the cover art next to the song so lists look right offline. Returns the file name or null.
Future<String?> saveArtwork(String url, String name) async {
  if (!url.startsWith('http')) return null;
  try {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dir = await _keepDir();
    final dest = File('${dir.path}${Platform.pathSeparator}$safe.jpg');
    final res = await _client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      return null;
    }
    final bytes = await res.stream.toBytes();
    if (bytes.length < 500) return null;
    await dest.writeAsBytes(bytes, flush: true);
    return '$safe.jpg';
  } catch (_) {
    return null;
  }
}

/// Saves a resolved stream as a permanent file named [name] (no extension) and returns its path and size.
/// googlevideo links use the same parallel, link-bound download as playback; other direct links are streamed.
Future<({String path, int bytes})?> saveStream(
  Playable p,
  String name, {
  void Function(double)? progress,
}) async {
  final url = p.url;
  if (url == null || url.isEmpty) return null;
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  try {
    final dir = await _keepDir();
    if (url.contains('googlevideo.com')) {
      final cached = await _download(p, progress: progress);
      if (cached != null) {
        final ext = cached.path.endsWith('.webm') ? 'webm' : 'm4a';
        final dest = File('${dir.path}${Platform.pathSeparator}$safe.$ext');
        if (await dest.exists()) await dest.delete();
        await cached.copy(dest.path);
        return (path: dest.path, bytes: await dest.length());
      }
    }
    // iPhone resolves YouTube to a file the native downloader already holds: keep a copy of it.
    if (!url.startsWith('http')) {
      final src = File(
        url.startsWith('file://') ? Uri.parse(url).toFilePath() : url,
      );
      if (!await src.exists()) return null;
      final dot = src.path.lastIndexOf('.');
      final ext = dot > src.path.lastIndexOf(Platform.pathSeparator)
          ? src.path.substring(dot + 1)
          : 'm4a';
      final dest = File('${dir.path}${Platform.pathSeparator}$safe.$ext');
      if (await dest.exists()) await dest.delete();
      await src.copy(dest.path);
      final n = await dest.length();
      if (n < 20 * 1024) {
        await dest.delete();
        return null;
      }
      progress?.call(1);
      return (path: dest.path, bytes: n);
    }
    final res = await _client
        .send(http.Request('GET', Uri.parse(url))..headers.addAll(p.headers))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200 && res.statusCode != 206) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      return null;
    }
    final path = Uri.parse(url).path.toLowerCase();
    final ext = path.endsWith('.mp3')
        ? 'mp3'
        : path.endsWith('.webm')
        ? 'webm'
        : path.endsWith('.ogg')
        ? 'ogg'
        : 'm4a';
    final dest = File('${dir.path}${Platform.pathSeparator}$safe.$ext');
    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    var got = 0;
    final total = res.contentLength ?? 0;
    try {
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress?.call((got / total).clamp(0.0, 1.0));
      }
    } finally {
      await sink.close();
    }
    // A cut-off transfer must not be kept as a song: the job retries instead.
    if (got < 20 * 1024 || (total > 0 && got < total)) {
      await part.delete();
      return null;
    }
    if (await dest.exists()) await dest.delete();
    await part.rename(dest.path);
    return (path: dest.path, bytes: got);
  } catch (e) {
    debugPrint('Saving song failed: $e');
    return null;
  }
}

Future<bool> fileExists(String path) async => File(path).exists();

Future<void> deleteSavedFile(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
