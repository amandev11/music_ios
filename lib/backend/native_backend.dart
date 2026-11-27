import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/offline.dart';
import '../sources/source.dart' show Playable;
import '../engine/transport.dart' show AudioOutput;
import '../engine/automix/planner.dart';
import 'backend.dart';

/// Android: the Kotlin Media3 + ONNX engine, MediaStore index, NewPipe/JioSaavn sources and
/// MediaLibraryService all live natively; this class is a thin channel client.
class NativeBackend implements Backend {
  static const _methods = MethodChannel('aurora/native');
  static const _libraryEvents = EventChannel('aurora/library');
  static const _snapshotEvents = EventChannel('aurora/snapshot');
  static const _progressEvents = EventChannel('aurora/progress');
  static const _frameEvents = EventChannel('aurora/frame');
  static const _errorEvents = EventChannel('aurora/errors');

  @override
  final ValueNotifier<LibraryData> library = ValueNotifier<LibraryData>(
    const LibraryData(),
  );
  @override
  final ValueNotifier<Snapshot> snapshot = ValueNotifier<Snapshot>(
    const Snapshot(),
  );
  @override
  final ValueNotifier<Progress> progress = ValueNotifier<Progress>(
    const Progress(),
  );
  @override
  final frame = AudioFrame();
  @override
  final ValueNotifier<bool> spatial = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<PlaybackError?> errors = ValueNotifier<PlaybackError?>(
    null,
  );

  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<dynamic>? _frameSub;

  @override
  bool get hasBeatEngine => true;
  @override
  bool get canAddMusic => false;
  @override
  bool get needsPermission =>
      library.value.state == LibraryState.needsPermission;

  @override
  Future<void> init() async {
    void onErr(Object e, StackTrace s) => debugPrint('native stream error: $e');
    _subs.add(
      _libraryEvents.receiveBroadcastStream().listen((e) {
        try {
          final m = e as Map;
          library.value = LibraryData(
            state: switch (m['state']) {
              'NeedsPermission' => LibraryState.needsPermission,
              'Ready' => LibraryState.ready,
              _ => LibraryState.scanning,
            },
            tracks: [
              for (final t in (m['tracks'] as List)) Track.fromMap(t as Map),
            ],
            albums: [
              for (final a in (m['albums'] as List)) Album.fromMap(a as Map),
            ],
          );
        } catch (e, s) {
          onErr(e, s);
        }
      }, onError: onErr),
    );
    _subs.add(
      _snapshotEvents.receiveBroadcastStream().listen((e) {
        try {
          snapshot.value = Snapshot.fromMap(e as Map);
          final mi = (e)['mixInfo'];
          mixInfo.value = mi is String && mi.isNotEmpty ? mi : null;
        } catch (e, s) {
          onErr(e, s);
        }
      }, onError: onErr),
    );
    _subs.add(
      _progressEvents.receiveBroadcastStream().listen((e) {
        try {
          final l = (e as List).cast<num>();
          progress.value = Progress(l[0].toInt(), l[1].toInt(), l[2].toInt());
        } catch (e, s) {
          onErr(e, s);
        }
      }, onError: onErr),
    );
    _subs.add(
      _errorEvents.receiveBroadcastStream().listen(
        (e) => errors.value = PlaybackError('Playback failed: $e'),
        onError: onErr,
      ),
    );
    try {
      spatial.value =
          (await _methods
              .invokeMethod<bool>('spatialEnabled')
              .timeout(const Duration(seconds: 5))) ??
          false;
    } catch (e, s) {
      onErr(e, s); // engine not ready yet: the UI still starts and the streams above fill in later
    }
  }

  Future<List<Track>> _tracks(String method, Map<String, Object?> args) async {
    final r = await _methods.invokeListMethod<Map>(method, args) ?? const [];
    return [for (final m in r) Track.fromMap(m)];
  }

  @override
  Future<void> requestPermission() =>
      _methods.invokeMethod('requestPermission');
  @override
  Future<void> refreshLibrary() => _methods.invokeMethod('refresh');
  @override
  Future<void> addMusic({String source = 'any'}) async {}

  @override
  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    bool shuffle = false,
  }) => _methods.invokeMethod('play', {
    'tracks': [for (final t in tracks) _wire(t)],
    'index': index,
    'shuffle': shuffle,
  });
  @override
  Future<void> toggle() => _methods.invokeMethod('toggle');
  @override
  Future<void> next() => _methods.invokeMethod('next');
  @override
  Future<void> previous() => _methods.invokeMethod('previous');
  @override
  Future<void> seek(int ms) => _methods.invokeMethod('seek', {'ms': ms});
  @override
  Future<void> skipTo(int index) =>
      _methods.invokeMethod('skipTo', {'index': index});
  @override
  Future<void> move(int from, int to) =>
      _methods.invokeMethod('move', {'from': from, 'to': to});
  @override
  Future<void> remove(int index) =>
      _methods.invokeMethod('remove', {'index': index});
  @override
  Future<void> playNext(Track t) => _methods.invokeMethod('playNext', {
    'tracks': [_wire(t)],
  });
  @override
  Future<void> addToQueue(Track t) => _methods.invokeMethod('addToQueue', {
    'tracks': [_wire(t)],
  });

  @override
  final ValueNotifier<String?> mixInfo = ValueNotifier<String?>(null);
  @override
  bool get canMixNow => true;
  @override
  Future<bool> mixNow() async =>
      (await _methods.invokeMethod<bool>('mixNow')) ?? false;

  Future<void> setWidgetTheme(String name) =>
      _methods.invokeMethod('widgetTheme', {'name': name});

  Future<void> setDj(int style) =>
      _methods.invokeMethod('automixDj', {'dj': style});

  Future<bool> openOutputSwitcher() async =>
      (await _methods.invokeMethod<bool>('openOutputSwitcher')) ?? false;

  @override
  Future<void> warmUp() async {
    try {
      await searchRemote('new hindi songs')
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Songs saved for offline play are handed to the engine with their file as the uri.
  Map<String, Object?> _wire(Track t) {
    final p = OfflineIndex.pathOf(t.mediaId);
    final m = t.toMap();
    if (p != null) m['uri'] = p.startsWith('/') ? 'file://$p' : p;
    return m;
  }

  @override
  Future<Playable?> resolveStream(
    Track t, {
    int? quality,
    bool fresh = false,
  }) async {
    final m = await _methods.invokeMapMethod<String, dynamic>('resolveStream', {
      'key': t.mediaId,
      'fresh': fresh,
      'quality': quality,
    });
    final url = m?['url'] as String?;
    if (url == null || url.isEmpty) return null;
    return Playable.url(
      url,
      headers: {
        for (final e in ((m?['headers'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      kbps: (m?['kbps'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> setShuffle(bool on) =>
      _methods.invokeMethod('setShuffle', {'on': on});
  @override
  Future<void> cycleRepeat() => _methods.invokeMethod('cycleRepeat');
  @override
  Future<void> setSpeed(double speed) =>
      _methods.invokeMethod('setSpeed', {'speed': speed});

  @override
  Future<List<Track>> searchLocal(String query) =>
      _tracks('searchLocal', {'q': query});
  @override
  Future<List<Track>> searchRemote(String query) =>
      _tracks('searchRemote', {'q': query});
  @override
  Future<List<Track>> albumTracks(Album album) =>
      _tracks('albumTracks', {'albumId': album.id});

  @override
  bool get eqSupported => true;
  @override
  Future<void> applyEq(bool enabled, List<double> gains) =>
      _methods.invokeMethod('eqSet', {'enabled': enabled, 'gains': gains});
  @override
  final ValueNotifier<double> volume = ValueNotifier<double>(1);
  @override
  Future<void> setOutputProtection(bool on) =>
      _methods.invokeMethod('protectSet', {'on': on});

  @override
  Future<void> setVolume(double v) async {
    volume.value = v.clamp(0.0, 1.0);
    await _methods.invokeMethod('volume', {'value': volume.value});
  }

  @override
  Future<List<AudioOutput>> outputs() async {
    try {
      final l = await _methods.invokeListMethod<Map>('outputs') ?? const [];
      return [
        const AudioOutput('auto', 'System default'),
        for (final m in l) AudioOutput('${m['id']}', '${m['name']}'),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setOutput(String id) =>
      _methods.invokeMethod('setOutput', {'id': id});

  @override
  Future<void> setAutomix(
    bool enabled,
    double seconds, {
    bool beatMix = true,
    bool auto = true,
  }) =>
      // The native engine blends by length only: crossfade mode = fixed seconds, Automix = per-song length.
      _methods.invokeMethod('automixSet', {
        'enabled': enabled,
        'seconds': seconds,
        'auto': beatMix && auto,
        'beatMix': beatMix,
        'dj': MixPlanner.djStyle,
      });

  @override
  Future<bool> spatialAvailable() async =>
      (await _methods.invokeMethod<bool>('spatialAvailable')) ?? false;
  @override
  Future<void> toggleSpatial() async {
    spatial.value =
        (await _methods.invokeMethod<bool>('toggleSpatial')) ?? spatial.value;
  }

  @override
  Future<({double bpm, double confidence})?> tempo() async {
    final m = await _methods.invokeMapMethod<String, num>('tempo');
    if (m == null) return null;
    final bpm = m['bpm']!.toDouble();
    return bpm > 0 ? (bpm: bpm, confidence: m['confidence']!.toDouble()) : null;
  }

  @override
  Future<TrackAnalysis?> analyze(Track t) async {
    final m = await _methods.invokeMapMethod<String, dynamic>('analyze', {
      'mediaId': t.mediaId,
      'uri': t.uri,
    });
    if (m == null) return null;
    return TrackAnalysis(
      bpm: (m['bpm'] as num).toDouble(),
      confidence: (m['confidence'] as num).toDouble(),
      waveform: [
        for (final v in (m['waveform'] as List)) (v as num).toDouble(),
      ],
    );
  }

  @override
  Future<List<double>?> waveform(Track t) async {
    try {
      final a = await analyze(t).timeout(const Duration(seconds: 60));
      return (a == null || a.waveform.isEmpty) ? null : a.waveform;
    } catch (_) {
      return null;
    }
  }

  @override
  void setFrameActive(bool active) {
    if (active) {
      if (_frameSub != null) return;
      _frameSub = _frameEvents.receiveBroadcastStream().listen((e) {
        if (e is! Float64List || e.length < 6 + frame.spectrum.length) return;
        final l = e;
        frame
          ..envelope = l[0]
          ..beatInBar = l[1].toInt()
          ..beatsPerBar = l[2].toInt()
          ..bpm = l[3]
          ..confidence = l[4]
          ..rms = l[5];
        for (var i = 0; i < frame.spectrum.length; i++) {
          frame.spectrum[i] = l[6 + i];
        }
        frame.publish();
      });
    } else {
      _frameSub?.cancel();
      _frameSub = null;
    }
  }

  /// Local artwork lives behind content:// URIs Flutter cannot open; the native side decodes it.
  static Future<Uint8List?> artwork(String uri, int px) =>
      _methods.invokeMethod<Uint8List>('artwork', {'uri': uri, 'px': px});

  @override
  Future<void> dispose() async {
    setFrameActive(false);
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
