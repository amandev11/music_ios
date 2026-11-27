import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_quality.dart';

/// User-tunable endpoints. Web builds need a CORS proxy for JioSaavn and a reachable Invidious host
/// list for YouTube search; native builds ignore both.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

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

  List<String> get invidiousHosts =>
      _prefs.getStringList('invidious') ?? defaultInvidious;
  set invidiousHosts(List<String> v) {
    _prefs.setStringList('invidious', v);
    notifyListeners();
  }

  bool get saavnEnabled => _prefs.getBool('saavn') ?? true;
  set saavnEnabled(bool v) {
    _prefs.setBool('saavn', v);
    notifyListeners();
  }

  bool get audiusEnabled => _prefs.getBool('audius') ?? true;
  set audiusEnabled(bool v) {
    _prefs.setBool('audius', v);
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

  /// Waveform progress bar in the player. Off (default) keeps the classic plain line.
  bool get waveformBar => _prefs.getBool('waveformBar') ?? false;
  set waveformBar(bool v) {
    _prefs.setBool('waveformBar', v);
    notifyListeners();
  }

  /// Round-thumb slider (like Instagram / WhatsApp voice notes): thin track, dot that grows under the finger and a
  /// time bubble while dragging. Off keeps the classic thick bar.
  bool get thumbSlider => _prefs.getBool('thumbSlider') ?? true;
  set thumbSlider(bool v) {
    _prefs.setBool('thumbSlider', v);
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

  Set<String> get favoriteArtists =>
      (_prefs.getStringList('favArtists') ?? const []).toSet();
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
  DateTime get now => tzOffsetMin == null
      ? DateTime.now()
      : DateTime.now().toUtc().add(Duration(minutes: tzOffsetMin!));

  bool get mixFilters => _prefs.getBool('mixFilters') ?? false;
  set mixFilters(bool v) {
    _prefs.setBool('mixFilters', v);
    notifyListeners();
  }

  /// Per-song custom transitions, keyed by the outgoing song's id: {mode, sec}.
  Map<String, Map<String, dynamic>> get mixOverrides {
    try {
      final m = jsonDecode(_prefs.getString('mixOv') ?? '{}') as Map;
      return {
        for (final e in m.entries)
          '${e.key}': Map<String, dynamic>.from(e.value as Map),
      };
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

  /// Everything worth keeping if the app is reinstalled: playlists (with Liked Songs), favourite artists and the
  /// per-song Automix choices.
  Map<String, dynamic> exportBackup() => {
    'app': 'aurora',
    'version': 1,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'playlists': playlists,
    'favArtists': favoriteArtists.toList(),
    'mixOverrides': mixOverrides,
    'appearance': {
      'uiStyle': uiStyle,
      'playerStyle': playerStyle,
      'accentIndex': accentIndex,
      'accentCustom': accentCustom,
      'miniButton': miniButton,
      'widgetTheme': widgetTheme,
      'iconId': iconId,
      'profileName': profileName,
      'searchHistory': searchHistory,
    },
  };

  /// Merges a backup into this device: playlists with the same id gain the missing songs, new ones are added.
  /// Returns the number of playlists touched.
  int importBackup(Map<String, dynamic> data) {
    if (data['app'] != 'aurora')
      throw const FormatException('Not an Aurora backup');
    final mine = playlists;
    var touched = 0;
    for (final raw in (data['playlists'] as List? ?? const [])) {
      final p = Map<String, dynamic>.from(raw as Map);
      final i = mine.indexWhere((m) => m['id'] == p['id']);
      if (i < 0) {
        mine.add(p);
      } else {
        final have = <String>{
          for (final t in (mine[i]['tracks'] as List))
            '${(t as Map)['mediaId']}',
        };
        final merged = List<dynamic>.from(mine[i]['tracks'] as List);
        for (final t in (p['tracks'] as List? ?? const [])) {
          if (have.add('${(t as Map)['mediaId']}')) merged.add(t);
        }
        mine[i]['tracks'] = merged;
      }
      touched++;
    }
    playlists = mine;
    final ap = data['appearance'];
    if (ap is Map) {
      if (ap['uiStyle'] is String) uiStyle = ap['uiStyle'] as String;
      if (ap['playerStyle'] is String)
        playerStyle = ap['playerStyle'] as String;
      if (ap['accentIndex'] is int) accentIndex = ap['accentIndex'] as int;
      if (ap['accentCustom'] is int) accentCustom = ap['accentCustom'] as int;
      if (ap['miniButton'] is String) miniButton = ap['miniButton'] as String;
      if (ap['widgetTheme'] is String)
        widgetTheme = ap['widgetTheme'] as String;
      if (ap['searchHistory'] is List && searchHistory.isEmpty) {
        _prefs.setStringList('searchHistory', [
          for (final e in (ap['searchHistory'] as List).take(5)) '$e',
        ]);
      }
      if (ap['profileName'] is String && profileName.isEmpty)
        profileName = ap['profileName'] as String;
    }
    final fav = favoriteArtists;
    for (final a in (data['favArtists'] as List? ?? const [])) {
      if (!fav.contains('$a')) toggleFavoriteArtist('$a');
    }
    return touched;
  }

  // ---- Appearance & profile (all persisted, so switching styles never touches playlists or history) ----

  /// UiStyle name: classic, orbit, sleeve, sky, verdant, editorial.
  String get uiStyle => _prefs.getString('uiStyle') ?? 'apollo';
  set uiStyle(String v) {
    _prefs.setString('uiStyle', v);
    notifyListeners();
  }

  /// PlayerStyle name, or 'auto' to follow the UI style.
  String get playerStyle => _prefs.getString('playerStyle') ?? 'auto';
  set playerStyle(String v) {
    _prefs.setString('playerStyle', v);
    notifyListeners();
  }

  /// Index into the accent palette; 0 uses the style's own colour.
  int get accentIndex => _prefs.getInt('accentIndex') ?? 0;
  set accentIndex(int v) {
    _prefs.setInt('accentIndex', v);
    notifyListeners();
  }

  /// Pure black backgrounds in dark mode (saves power on OLED).
  bool get amoled => _prefs.getBool('amoled') ?? false;
  set amoled(bool v) {
    _prefs.setBool('amoled', v);
    notifyListeners();
  }

  /// Fewer animations and no blur-heavy backdrop, for slower devices.
  bool get lightEffects => _prefs.getBool('lightEffects') ?? false;
  set lightEffects(bool v) {
    _prefs.setBool('lightEffects', v);
    notifyListeners();
  }

  String get iconId => _prefs.getString('iconId') ?? 'keycapkeystone';
  set iconId(String v) {
    _prefs.setString('iconId', v);
    notifyListeners();
  }

  /// Android only: show the chosen icon's own name under the launcher icon.
  bool get iconNamed => _prefs.getBool('iconNamed') ?? false;
  set iconNamed(bool v) {
    _prefs.setBool('iconNamed', v);
    notifyListeners();
  }

  /// Custom accent colour (ARGB int, 0 = none); active when [accentIndex] is 99.
  int get accentCustom => _prefs.getInt('accentCustom') ?? 0;
  set accentCustom(int v) {
    _prefs.setInt('accentCustom', v);
    notifyListeners();
  }

  /// What the mini player's extra button does: like, next, previous, playlist, output.
  String get miniButton => _prefs.getString('miniButton') ?? 'like';
  set miniButton(String v) {
    _prefs.setString('miniButton', v);
    notifyListeners();
  }

  /// Home-screen widget look: minimal, classic, gradient, glass, vinyl, neon.
  String get widgetTheme => _prefs.getString('widgetTheme') ?? 'classic';
  set widgetTheme(String v) {
    _prefs.setString('widgetTheme', v);
    notifyListeners();
  }

  /// Fade between tabs.
  bool get smoothAnimations => _prefs.getBool('smoothAnim') ?? true;
  set smoothAnimations(bool v) {
    _prefs.setBool('smoothAnim', v);
    notifyListeners();
  }

  /// Home sections the listener switched off (Apollo home): hero, quick, charts, playlists, releases, artists, recent.
  List<String> get homeHidden => _prefs.getStringList('homeHidden') ?? const [];
  void setHomeSection(String key, bool shown) {
    final l = {...homeHidden};
    shown ? l.remove(key) : l.add(key);
    _prefs.setStringList('homeHidden', l.toList());
    notifyListeners();
  }

  bool homeShows(String key) => !homeHidden.contains(key);

  /// Last five searches, newest first.
  List<String> get searchHistory =>
      _prefs.getStringList('searchHistory') ?? const [];

  void addSearch(String q) {
    final t = q.trim();
    if (t.length < 2) return;
    final l = [...searchHistory]
      ..removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    l.insert(0, t);
    _prefs.setStringList('searchHistory', l.take(5).toList());
    notifyListeners();
  }

  void removeSearch(String q) {
    _prefs.setStringList('searchHistory', [
      for (final e in searchHistory)
        if (e != q) e,
    ]);
    notifyListeners();
  }

  void clearSearches() {
    _prefs.setStringList('searchHistory', const []);
    notifyListeners();
  }

  String get profileName => _prefs.getString('profileName') ?? '';
  set profileName(String v) {
    _prefs.setString('profileName', v.trim());
    notifyListeners();
  }

  /// Path of a picked profile photo (empty = initials).
  String get profilePhoto => _prefs.getString('profilePhoto') ?? '';
  set profilePhoto(String v) {
    _prefs.setString('profilePhoto', v);
    notifyListeners();
  }

  /// Offline copies: mediaId -> {path, bytes, title, artist, album, art, durationMs, ts, track}.
  Map<String, Map<String, dynamic>> get downloads {
    try {
      final m = jsonDecode(_prefs.getString('downloads') ?? '{}') as Map;
      return {
        for (final e in m.entries)
          '${e.key}': Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  set downloads(Map<String, Map<String, dynamic>> v) {
    _prefs.setString('downloads', jsonEncode(v));
    notifyListeners();
  }

  /// Phones use the desktop player's layout (default) instead of the compact phone layout.
  bool get deskPlayer => _prefs.getBool('deskPlayer') ?? true;
  set deskPlayer(bool v) {
    _prefs.setBool('deskPlayer', v);
    notifyListeners();
  }

  /// iPhone: show the now-playing poster on the Lock Screen and Dynamic Island (a Live Activity).
  bool get lockPoster => _prefs.getBool('lockPoster') ?? true;
  set lockPoster(bool v) {
    _prefs.setBool('lockPoster', v);
    notifyListeners();
  }

  /// Visualizer: scene id, preset, response intensity and motion speed.
  String get vizScene => _prefs.getString('vizScene') ?? 'plasma';
  set vizScene(String v) {
    _prefs.setString('vizScene', v);
    notifyListeners();
  }

  String get vizPreset => _prefs.getString('vizPreset') ?? 'balanced';
  set vizPreset(String v) {
    _prefs.setString('vizPreset', v);
    notifyListeners();
  }

  double get vizIntensity => _prefs.getDouble('vizIntensity') ?? 1.0;
  set vizIntensity(double v) {
    _prefs.setDouble('vizIntensity', v);
    notifyListeners();
  }

  double get vizSpeed => _prefs.getDouble('vizSpeed') ?? 1.0;
  set vizSpeed(double v) {
    _prefs.setDouble('vizSpeed', v);
    notifyListeners();
  }

  /// Quality of saved songs: 0 data saver .. 3 best, -1 to follow the streaming quality. Best by default.
  int get downloadQuality => _prefs.getInt('dlQuality') ?? 3;
  set downloadQuality(int v) {
    _prefs.setInt('dlQuality', v);
    notifyListeners();
  }

  /// Download on Wi-Fi only.
  bool get downloadWifiOnly => _prefs.getBool('dlWifi') ?? false;
  set downloadWifiOnly(bool v) {
    _prefs.setBool('dlWifi', v);
    notifyListeners();
  }

  /// Save every song you like for offline play.
  bool get autoDownloadLiked => _prefs.getBool('dlLiked') ?? false;
  set autoDownloadLiked(bool v) {
    _prefs.setBool('dlLiked', v);
    notifyListeners();
  }

  /// Automix "DJ" options.
  /// 0 Smooth blend, 1 Club (beat-matched, filter and echo transitions), 2 Mashup-style hard cuts on the beat.
  int get djStyle => _prefs.getInt('djStyle') ?? 1;
  set djStyle(int v) {
    _prefs.setInt('djStyle', v);
    notifyListeners();
  }

  /// Last good YouTube Music home/chart shelves (JSON), shown instantly on the next launch.
  String get ytHomeCache => _prefs.getString('ytHomeCache') ?? '';
  set ytHomeCache(String v) => _prefs.setString('ytHomeCache', v);

  /// Sleep timer end (ms since epoch) or 0.
  int get sleepAtMs => _prefs.getInt('sleepAt') ?? 0;
  set sleepAtMs(int v) {
    _prefs.setInt('sleepAt', v);
    notifyListeners();
  }

  /// Wraps [url] for the CORS proxy on web when one is configured.
  Uri proxied(Uri url) {
    if (!kIsWeb || proxyUrl.isEmpty) return url;
    return Uri.parse('$proxyUrl${Uri.encodeComponent(url.toString())}');
  }
}
