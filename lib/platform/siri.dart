import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../backend/backend.dart';
import '../app.dart';
import '../core/models.dart';
import '../ui/widgets/playlists.dart';

/// Siri and Shortcuts: "play <song> on Music", pause, resume, next, previous, like, liked songs, playlists,
/// "what's playing". The native App Intents hand over one JSON command; this runs it.
class SiriBridge with WidgetsBindingObserver {
  SiriBridge(this._backend) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'siri' && call.arguments is String) {
        unawaited(_run(call.arguments as String));
        return true;
      }
      return null;
    });
    WidgetsBinding.instance.addObserver(this);
    _backend.snapshot.addListener(_publishNow);
    AppController.I.settings.addListener(_catalogSoon);
    Timer(const Duration(seconds: 6), () => unawaited(_syncCatalog()));
    unawaited(_take());
    // A cold start through Siri can finish launching a moment after the intent ran.
    Timer(const Duration(seconds: 2), () => unawaited(_take()));
  }

  static const _ch = MethodChannel('aurora/pcm');
  final Backend _backend;
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _nowShown;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_take());
    if (state == AppLifecycleState.paused) unawaited(_syncCatalog());
  }

  Timer? _catalogTimer;
  void _catalogSoon() {
    _catalogTimer?.cancel();
    _catalogTimer = Timer(
      const Duration(seconds: 45),
      () => unawaited(_syncCatalog()),
    );
  }

  /// Tells Siri which songs, artists and playlists exist, so a spoken name can be recognised: liked songs,
  /// recent plays, downloads, playlists and the device library, newest first.
  Future<void> _syncCatalog() async {
    try {
      final c = AppController.I;
      final seen = <String>{};
      final songs = <List<String>>[];
      void add(Track t) {
        if (t.title.trim().isEmpty ||
            !seen.add(t.mediaId) ||
            songs.length >= 300)
          return;
        songs.add([t.mediaId, t.title, t.artist]);
      }

      final lists = UserPlaylists.all();
      for (final p in lists.take(1)) {
        for (final m in (p['tracks'] as List? ?? const [])) {
          add(Track.fromMap(Map<String, dynamic>.from(m as Map)));
        }
      }
      c.recentTracks.forEach(add);
      c.downloads.tracks.forEach(add);
      for (final p in lists.skip(1)) {
        for (final m in (p['tracks'] as List? ?? const [])) {
          add(Track.fromMap(Map<String, dynamic>.from(m as Map)));
        }
      }
      _backend.library.value.tracks.forEach(add);
      final artists = <String>{
        for (final r in songs)
          if (r[2].trim().isNotEmpty && !r[2].contains(',')) r[2].trim(),
      }.take(100).toList();
      final names = [
        for (final p in lists)
          if ('${p['name']}'.trim().isNotEmpty) '${p['name']}',
      ].take(50).toList();
      final json = jsonEncode({
        'songs': songs,
        'artists': artists,
        'playlists': names,
      });
      if (json == _catalogSent) return;
      _catalogSent = json;
      await _ch.invokeMethod<void>('siriCatalog', json);
    } catch (e) {
      debugPrint('Siri catalog failed: $e');
    }
  }

  String? _catalogSent;

  /// Keeps "what's playing" readable by Siri even when the app is in the background.
  void _publishNow() {
    final t = _backend.snapshot.value.current;
    final text = t == null
        ? ''
        : '${t.title}${t.artist.isEmpty ? '' : ' by ${t.artist}'}';
    if (text == _nowShown) return;
    _nowShown = text;
    unawaited(_ch.invokeMethod<void>('siriNow', text).catchError((_) {}));
  }

  Future<void> _take() async {
    try {
      final q = await _ch.invokeMethod<String>('takeSiri');
      if (q != null && q.trim().isNotEmpty) await _run(q);
    } catch (_) {}
  }

  Future<void> _run(String raw) async {
    // The same command can arrive by notification and by the stored copy: run it once.
    if (raw == _last &&
        DateTime.now().difference(_lastAt) < const Duration(seconds: 4))
      return;
    _last = raw;
    _lastAt = DateTime.now();
    String cmd = 'play', q = raw, title = '';
    try {
      final m = jsonDecode(raw) as Map;
      cmd = '${m['cmd']}';
      q = '${m['q'] ?? ''}'.trim();
      title = '${m['t'] ?? ''}'.trim();
    } catch (_) {}
    try {
      final playing = _backend.snapshot.value.isPlaying;
      switch (cmd) {
        case 'pause':
          if (playing) await _backend.toggle();
        case 'resume':
          if (_backend.snapshot.value.current == null) {
            // Nothing queued (the app was closed): start with the recent songs, else the liked ones.
            final recent = AppController.I.recentTracks;
            if (recent.isNotEmpty) {
              await _backend.playTracks(recent, 0);
            } else {
              await _playPlaylist(UserPlaylists.likedId, shuffle: true);
            }
          } else if (!playing) {
            await _backend.toggle();
          }
        case 'track':
          final known = <Track>[
            ...AppController.I.recentTracks,
            ...AppController.I.downloads.tracks,
            ..._backend.library.value.tracks,
            for (final p in UserPlaylists.all())
              for (final m in (p['tracks'] as List? ?? const []))
                Track.fromMap(Map<String, dynamic>.from(m as Map)),
          ];
          final hit = known.where((t) => t.mediaId == q);
          if (hit.isNotEmpty) {
            await _backend.playTracks([hit.first], 0);
          } else {
            await _playQuery(title);
          }
        case 'next':
          await _backend.next();
        case 'previous':
          await _backend.previous();
        case 'like':
          final t = _backend.snapshot.value.current;
          if (t != null && !UserPlaylists.isLiked(t.mediaId))
            UserPlaylists.toggleLike(t);
        case 'liked':
          await _playPlaylist(UserPlaylists.likedId, shuffle: false);
        case 'shuffle':
          await _playPlaylist(UserPlaylists.likedId, shuffle: true);
        case 'playlist':
          final want = q.toLowerCase();
          final all = UserPlaylists.all();
          final hit = all
              .where((p) => '${p['name']}'.toLowerCase() == want)
              .followedBy(
                all.where((p) => '${p['name']}'.toLowerCase().contains(want)),
              );
          if (hit.isNotEmpty) {
            await _playPlaylist('${hit.first['id']}', shuffle: false);
          } else {
            await _playQuery(q);
          }
        default:
          await _playQuery(q);
      }
    } catch (e) {
      debugPrint('Siri command failed: $e');
    }
  }

  Future<void> _playPlaylist(String id, {required bool shuffle}) async {
    final p = UserPlaylists.all().firstWhere(
      (p) => p['id'] == id,
      orElse: () => const {},
    );
    final tracks = <Track>[
      for (final m in (p['tracks'] as List? ?? const []))
        Track.fromMap(Map<String, dynamic>.from(m as Map)),
    ];
    if (tracks.isEmpty) return;
    await _backend.playTracks(tracks, 0, shuffle: shuffle);
  }

  Future<void> _playQuery(String q) async {
    if (q.isEmpty) return;
    var found = await _backend.searchLocal(q);
    // A title match in the library wins; otherwise search the catalogue.
    if (found.isEmpty) found = await _backend.searchRemote(q);
    if (found.isEmpty) return;
    await _backend.playTracks(found, 0);
  }
}
