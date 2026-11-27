import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../sources/stream_proxy_stub.dart'
    if (dart.library.io) '../sources/stream_proxy_io.dart'
    show saveStream, fileExists, deleteSavedFile, keepDirPath, saveArtwork;
import 'models.dart';
import 'offline.dart';
import 'settings.dart';

enum DownloadState { queued, active, failed }

class DownloadJob {
  DownloadJob(this.track);
  final Track track;
  DownloadState state = DownloadState.queued;
  double progress = 0;
  String? error;
  int tries = 0;
}

/// Saves songs on the device and keeps the index in [Settings] (so it survives style switches and updates).
/// Saved songs play first from the file; the app falls back to streaming when the file is gone.
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._settings, this._backend) {
    OfflineIndex.pathOf = pathOf;
    unawaited(_init());
    // Start waiting downloads when Wi-Fi returns or the mobile-data switch is turned on.
    try {
      _net = Connectivity().onConnectivityChanged.listen(
        (_) => unawaited(_pump()),
        onError: (_) {},
      );
    } catch (_) {}
    _settings.addListener(_onSettings);
  }

  StreamSubscription<dynamic>? _net;
  bool _lastMobileOk = true;

  void _onSettings() {
    final ok = !_settings.downloadWifiOnly;
    if (ok && !_lastMobileOk) unawaited(_pump());
    _lastMobileOk = ok;
  }

  @override
  void dispose() {
    _net?.cancel();
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  /// True when the setting forbids mobile data and the phone has no Wi-Fi or cable connection.
  Future<bool> _blockedByData() async {
    if (!_settings.downloadWifiOnly) return false;
    try {
      final r = await Connectivity().checkConnectivity();
      final free = r.any(
        (c) =>
            c == ConnectivityResult.wifi ||
            c == ConnectivityResult.ethernet ||
            c == ConnectivityResult.vpn &&
                !r.contains(ConnectivityResult.mobile),
      );
      return !free && r.contains(ConnectivityResult.mobile);
    } catch (_) {
      return false;
    }
  }

  /// The downloads folder. Entries store only the file name, because an iPhone app's container path
  /// changes after an update or re-sign and an absolute path would stop working.
  String _root = '';

  Future<void> _init() async {
    try {
      _root = await keepDirPath();
    } catch (_) {}
    await _verify();
    notifyListeners();
  }

  String? _abs(Map? m) {
    if (m == null) return null;
    final f = m['file'];
    if (f is String && f.isNotEmpty && _root.isNotEmpty) return '$_root/$f';
    final p = m['path'];
    return p is String && p.isNotEmpty ? p : null;
  }

  final Settings _settings;
  final Backend _backend;
  final Map<String, DownloadJob> jobs = {};
  bool _running = false;

  bool get supported => !kIsWeb;

  String? pathOf(String mediaId) {
    return _abs(_settings.downloads[mediaId]);
  }

  bool isDownloaded(String mediaId) => pathOf(mediaId) != null;

  DownloadJob? jobFor(String mediaId) => jobs[mediaId];

  int get totalBytes => _settings.downloads.values.fold<int>(
    0,
    (a, m) => a + ((m['bytes'] as num?)?.toInt() ?? 0),
  );

  /// Saved songs, newest first.
  List<Track> get tracks {
    final entries = _settings.downloads.entries.toList()
      ..sort(
        (a, b) => ((b.value['ts'] as num?) ?? 0).compareTo(
          (a.value['ts'] as num?) ?? 0,
        ),
      );
    final out = <Track>[];
    for (final e in entries) {
      final t = e.value['track'];
      if (t is Map) {
        try {
          out.add(
            _offlineTrack(Track.fromMap(Map<String, dynamic>.from(t)), e.value),
          );
        } catch (_) {}
      }
    }
    return out;
  }

  Track _offlineTrack(Track t, Map m) {
    final art = m['art'];
    if (art is String && art.isNotEmpty && _root.isNotEmpty) {
      return t.copyWithArtwork('$_root/$art');
    }
    return t;
  }

  /// The same track pointing at its saved file (for engines that take a uri), or [t] itself.
  Track withLocalUri(Track t) {
    final p = pathOf(t.mediaId);
    if (p == null) return t;
    return Track(
      mediaId: t.mediaId,
      title: t.title,
      artist: t.artist,
      album: t.album,
      albumArtist: t.albumArtist,
      albumId: t.albumId,
      durationMs: t.durationMs,
      trackNumber: t.trackNumber,
      discNumber: t.discNumber,
      year: t.year,
      uri: p.startsWith('/') ? 'file://$p' : p,
      artworkUri: _offlineTrack(
        t,
        _settings.downloads[t.mediaId] ?? const {},
      ).artworkUri,
      artworkBytes: t.artworkBytes,
      mimeType: t.mimeType,
      dateAddedSec: t.dateAddedSec,
    );
  }

  void enqueue(Track t) {
    if (!supported ||
        !t.isRemote ||
        isDownloaded(t.mediaId) ||
        jobs.containsKey(t.mediaId))
      return;
    jobs[t.mediaId] = DownloadJob(t);
    notifyListeners();
    unawaited(_pump());
  }

  void enqueueAll(Iterable<Track> list) {
    for (final t in list) {
      enqueue(t);
    }
  }

  void cancelOrRetry(String mediaId) {
    final j = jobs[mediaId];
    if (j == null) return;
    if (j.state == DownloadState.failed) {
      j.state = DownloadState.queued;
      j.error = null;
      j.progress = 0;
      unawaited(_pump());
    } else if (j.state == DownloadState.queued) {
      jobs.remove(mediaId);
    }
    notifyListeners();
  }

  Future<void> remove(String mediaId) async {
    final all = _settings.downloads;
    final path = all.remove(mediaId)?['path'];
    jobs.remove(mediaId);
    _settings.downloads = all;
    if (path is String) await deleteSavedFile(path);
    notifyListeners();
  }

  Future<void> removeAll() async {
    for (final id in _settings.downloads.keys.toList()) {
      await remove(id);
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = jobs.values
            .where((j) => j.state == DownloadState.queued)
            .firstOrNull;
        if (next == null) break;
        if (await _blockedByData()) {
          for (final j in jobs.values.where(
            (j) => j.state == DownloadState.queued,
          )) {
            j.error = 'Waiting for Wi-Fi';
          }
          notifyListeners();
          break;
        }
        next.error = null;
        await _run(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadJob j) async {
    final t = j.track;
    j.state = DownloadState.active;
    notifyListeners();
    try {
      // Best quality unless the listener chose another in Audio settings; retries ask for a fresh link.
      final dq = _settings.downloadQuality;
      final p = await _backend
          .resolveStream(
            t,
            quality: dq < 0 ? null : dq.clamp(0, 3),
            fresh: true,
          )
          .timeout(const Duration(seconds: 150));
      if (p == null || p.url == null)
        throw StateError('No downloadable stream found');
      var last = 0.0;
      final saved = await saveStream(
        p,
        t.mediaId,
        progress: (v) {
          if (v - last >= 0.02) {
            last = v;
            j.progress = v;
            notifyListeners();
          }
        },
      );
      if (saved == null) throw StateError('The download did not finish');
      String? art;
      final au = t.artworkUri;
      if (au != null && au.startsWith('http'))
        art = await saveArtwork(au, t.mediaId);
      final all = _settings.downloads;
      all[t.mediaId] = {
        'file': saved.path.split(RegExp(r'[\\/]')).last,
        if (art != null) 'art': art,
        'path': saved.path,
        'bytes': saved.bytes,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'track': t.toMap(),
      };
      _settings.downloads = all;
      jobs.remove(t.mediaId);
    } catch (e) {
      j.tries++;
      if (j.tries < 3) {
        // Links expire and networks hiccup: ask for a fresh link and try again.
        j.state = DownloadState.queued;
        j.progress = 0;
        notifyListeners();
        await Future<void>.delayed(Duration(seconds: 2 * j.tries));
        return;
      }
      j.state = DownloadState.failed;
      j.error = '$e'.replaceFirst('Bad state: ', '');
    }
    notifyListeners();
  }

  Future<void> _verify() async {
    final all = _settings.downloads;
    var changed = false;
    for (final e in all.entries.toList()) {
      final p = _abs(e.value);
      if (p == null || !await fileExists(p)) {
        all.remove(e.key);
        changed = true;
      }
    }
    if (changed) {
      _settings.downloads = all;
      notifyListeners();
    }
  }
}
