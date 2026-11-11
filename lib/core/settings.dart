import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_quality.dart';

/// User-tunable endpoints. Web builds need a CORS proxy for JioSaavn and a reachable Invidious host
/// list for YouTube search; native builds ignore both.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  static const defaultInvidious = [
    'https://yewtu.be',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
  ];

  /// e.g. https://your-worker.example.workers.dev/?url=  (see tools/cors_proxy_worker.js)
  String get proxyUrl => _prefs.getString('proxyUrl') ?? '';
  set proxyUrl(String v) {
    _prefs.setString('proxyUrl', v.trim());
    notifyListeners();
  }

  List<String> get invidiousHosts => _prefs.getStringList('invidious') ?? defaultInvidious;
  set invidiousHosts(List<String> v) {
    _prefs.setStringList('invidious', v);
    notifyListeners();
  }

  bool get saavnEnabled => _prefs.getBool('saavn') ?? true;
  set saavnEnabled(bool v) {
    _prefs.setBool('saavn', v);
    notifyListeners();
  }

  bool get youtubeEnabled => _prefs.getBool('youtube') ?? true;
  set youtubeEnabled(bool v) {
    _prefs.setBool('youtube', v);
    notifyListeners();
  }

  List<String> get musicFolders => _prefs.getStringList('folders') ?? const [];
  set musicFolders(List<String> v) {
    _prefs.setStringList('folders', v);
    notifyListeners();
  }

  List<String> get musicFiles => _prefs.getStringList('files') ?? const [];
  set musicFiles(List<String> v) {
    _prefs.setStringList('files', v);
    notifyListeners();
  }

  /// Speaker protection (sub-bass filter, limiter, headroom): on by default.
  bool get outputProtection => _prefs.getBool('outputProtection') ?? true;
  set outputProtection(bool v) {
    _prefs.setBool('outputProtection', v);
    notifyListeners();
  }

  /// iPhone/iPad: play through mpv instead of the native engine (needs an app restart).
  bool get iosCompatEngine => _prefs.getBool('iosCompatEngine') ?? false;
  set iosCompatEngine(bool v) {
    _prefs.setBool('iosCompatEngine', v);
    notifyListeners();
  }

  /// Spatial widening on the Dart (iOS/desktop) engine; off until the listener turns it on.
  bool get spatialDsp => _prefs.getBool('spatialDsp') ?? false;
  set spatialDsp(bool v) {
    _prefs.setBool('spatialDsp', v);
    notifyListeners();
  }

  bool get spatial => _prefs.getBool('spatial') ?? true;
  set spatial(bool v) {
    _prefs.setBool('spatial', v);
    notifyListeners();
  }

  bool get eqEnabled => _prefs.getBool('eqOn') ?? false;
  set eqEnabled(bool v) {
    _prefs.setBool('eqOn', v);
    notifyListeners();
  }

  List<double> get eqGains {
    final l = _prefs.getStringList('eqGains');
    if (l == null || l.length != 10) return List.filled(10, 0.0);
    return [for (final e in l) double.tryParse(e) ?? 0.0];
  }

  set eqGains(List<double> v) {
    _prefs.setStringList('eqGains', [for (final e in v) e.toString()]);
    notifyListeners();
  }

  String get eqPreset => _prefs.getString('eqPreset') ?? 'Flat';
  set eqPreset(String v) {
    _prefs.setString('eqPreset', v);
    notifyListeners();
  }

  bool get automix => _prefs.getBool('automix') ?? false;
  set automix(bool v) {
    _prefs.setBool('automix', v);
    notifyListeners();
  }

  /// True: plain crossfade only (fixed length, no beat matching, no DJ filters). False: DJ-style Automix.
  bool get crossfadeOnly => _prefs.getBool('crossfadeOnly') ?? false;
  set crossfadeOnly(bool v) {
    _prefs.setBool('crossfadeOnly', v);
    notifyListeners();
  }

  double get crossfadeSeconds => _prefs.getDouble('crossfadeSec') ?? 6.0;
  set crossfadeSeconds(double v) {
    _prefs.setDouble('crossfadeSec', v);
    notifyListeners();
  }

  /// Automix picks the blend length from each song; when off, [automixSeconds] is used.
  bool get automixAuto => _prefs.getBool('automixAuto') ?? true;
  set automixAuto(bool v) {
    _prefs.setBool('automixAuto', v);
    notifyListeners();
  }

  double get automixSeconds => _prefs.getDouble('automixSec') ?? 8.0;
  set automixSeconds(double v) {
    _prefs.setDouble('automixSec', v);
    notifyListeners();
  }

  /// Recently played, newest first (JSON track maps; local artwork bytes are not stored).
  List<Map<String, dynamic>> get recent {
    final l = _prefs.getStringList('recent') ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final e in l) {
      try {
        out.add(jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  set recent(List<Map<String, dynamic>> v) {
    _prefs.setStringList('recent', [for (final e in v.take(40)) jsonEncode(e)]);
    notifyListeners();
  }

  Set<String> get favoriteArtists => (_prefs.getStringList('favArtists') ?? const []).toSet();
  void toggleFavoriteArtist(String id) {
    final s = favoriteArtists;
    s.contains(id) ? s.remove(id) : s.add(id);
    _prefs.setStringList('favArtists', s.toList());
    notifyListeners();
  }

  /// What the listener picked: 0 Low, 1 Medium, 2 High, 3 Lossless (best the source has; neither source is
  /// lossless) or 4 Auto (follows the measured network speed).
  int get qualityMode => _prefs.getInt('quality') ?? 4;

  /// The quality actually used right now, 0..3.
  int get quality {
    final m = qualityMode;
    return m == 4 ? NetworkQuality.recommended : m;
  }

  set quality(int v) {
    _prefs.setInt('quality', v);
    notifyListeners();
  }

  int get qualityKbps => const [96, 160, 320, 320][quality.clamp(0, 3)];

  double get volume => _prefs.getDouble('volume') ?? 1.0;
  set volume(double v) => _prefs.setDouble('volume', v);

  /// 'system', 'light' or 'dark'.
  String get themeMode => _prefs.getString('theme') ?? 'system';
  set themeMode(String v) {
    _prefs.setString('theme', v);
    notifyListeners();
  }

  /// When the queue runs out, keep going with songs the listener is likely to enjoy.
  bool get autoplay => _prefs.getBool('autoplay') ?? true;
  set autoplay(bool v) {
    _prefs.setBool('autoplay', v);
    notifyListeners();
  }

  /// Word-by-word lyric highlighting (experimental); off = clean line-by-line.
  bool get wordLyrics => _prefs.getBool('wordLyrics') ?? false;
  set wordLyrics(bool v) {
    _prefs.setBool('wordLyrics', v);
    notifyListeners();
  }

  /// Bass-swap / filter sweeps during Automix blends (needs an mpv build that accepts the filters).
  /// Fixed UTC offset in minutes chosen by the listener; null follows the device clock.
  int? get tzOffsetMin {
    final v = _prefs.getInt('tzOffsetMin');
    return v == null || v == 99999 ? null : v;
  }

  set tzOffsetMin(int? v) {
    _prefs.setInt('tzOffsetMin', v ?? 99999);
    notifyListeners();
  }

  /// Current time in the chosen zone (device zone when none is chosen).
  DateTime get now => tzOffsetMin == null ? DateTime.now() : DateTime.now().toUtc().add(Duration(minutes: tzOffsetMin!));

  bool get mixFilters => _prefs.getBool('mixFilters') ?? false;
  set mixFilters(bool v) {
    _prefs.setBool('mixFilters', v);
    notifyListeners();
  }

  /// Per-song custom transitions, keyed by the outgoing song's id: {mode, sec}.
  Map<String, Map<String, dynamic>> get mixOverrides {
    try {
      final m = jsonDecode(_prefs.getString('mixOv') ?? '{}') as Map;
      return {for (final e in m.entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)};
    } catch (_) {
      return {};
    }
  }

  void setMixOverride(String id, Map<String, dynamic>? v) {
    final m = mixOverrides;
    v == null ? m.remove(id) : m[id] = v;
    _prefs.setString('mixOv', jsonEncode(m));
    notifyListeners();
  }

  bool get particles => _prefs.getBool('particles') ?? true;
  set particles(bool v) {
    _prefs.setBool('particles', v);
    notifyListeners();
  }

  String get outputDevice => _prefs.getString('output') ?? 'auto';
  set outputDevice(String v) => _prefs.setString('output', v);

  int get firstRunMs {
    final v = _prefs.getInt('firstRun');
    if (v != null) return v;
    final now = DateTime.now().millisecondsSinceEpoch;
    _prefs.setInt('firstRun', now);
    return now;
  }

  int get listenedMs => _prefs.getInt('listenedMs') ?? 0;
  set listenedMs(int v) {
    _prefs.setInt('listenedMs', v);
    notifyListeners();
  }

  /// Every started play, newest last: {id,title,artist,album,ts}. Capped.
  List<Map<String, dynamic>> get plays {
    final l = _prefs.getStringList('plays') ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final e in l) {
      try {
        out.add(jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  void addPlay(Map<String, dynamic> m) {
    final l = _prefs.getStringList('plays') ?? <String>[];
    l.add(jsonEncode(m));
    if (l.length > 1000) l.removeRange(0, l.length - 1000);
    _prefs.setStringList('plays', l);
    notifyListeners();
  }

  /// User playlists: {id,name,tracks:[track maps]}.
  List<Map<String, dynamic>> get playlists {
    final l = _prefs.getStringList('playlists') ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final e in l) {
      try {
        out.add(jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  set playlists(List<Map<String, dynamic>> v) {
    _prefs.setStringList('playlists', [for (final e in v) jsonEncode(e)]);
    notifyListeners();
  }

  /// Wraps [url] for the CORS proxy on web when one is configured.
  Uri proxied(Uri url) {
    if (!kIsWeb || proxyUrl.isEmpty) return url;
    return Uri.parse('$proxyUrl${Uri.encodeComponent(url.toString())}');
  }
}
