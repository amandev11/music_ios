import 'dart:typed_data';

enum SourceKind { local, youtube, saavn, meta }

/// Track ids double as routing keys: `yt:`, `saavn:` or `local:`.
class TrackKeys {
  static String youtube(String id) => 'yt:$id';
  static String saavn(String id) => 'saavn:$id';
  static String local(String id) => 'local:$id';

  /// Catalogue entries (Deezer) with no stream of their own: resolved by matching on the playback sources.
  static String meta(String id) => 'dz:$id';

  static SourceKind kindOf(String mediaId) {
    if (mediaId.startsWith('yt:')) return SourceKind.youtube;
    if (mediaId.startsWith('saavn:')) return SourceKind.saavn;
    if (mediaId.startsWith('dz:') || mediaId.startsWith('mb:')) return SourceKind.meta;
    return SourceKind.local;
  }

  static String rawId(String mediaId) {
    final i = mediaId.indexOf(':');
    return i < 0 ? mediaId : mediaId.substring(i + 1);
  }

  static bool isRemote(String mediaId) => kindOf(mediaId) != SourceKind.local;
}

class Track {
  const Track({
    required this.mediaId,
    required this.title,
    required this.artist,
    this.album = '',
    this.albumArtist,
    this.albumId = 0,
    this.durationMs = 0,
    this.trackNumber = 0,
    this.discNumber = 0,
    this.year = 0,
    this.uri = '',
    this.artworkUri,
    this.artworkBytes,
    this.mimeType,
    this.dateAddedSec = 0,
  });

  final String mediaId;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int albumId;
  final int durationMs;
  final int trackNumber;
  final int discNumber;
  final int year;

  /// File path, blob URL, content URI or the engine's own stream URI.
  final String uri;
  final String? artworkUri;
  final Uint8List? artworkBytes;
  final String? mimeType;
  final int dateAddedSec;

  SourceKind get kind => TrackKeys.kindOf(mediaId);
  bool get isRemote => kind != SourceKind.local;
  bool get hasArtwork => artworkBytes != null || (artworkUri != null && artworkUri!.isNotEmpty);

  /// Same artwork identity, for cache keys.
  String get artKey => artworkUri ?? (artworkBytes != null ? 'bytes:$mediaId' : 'none');

  factory Track.fromMap(Map<dynamic, dynamic> m) => Track(
        mediaId: m['mediaId'] as String,
        title: (m['title'] as String?) ?? '',
        artist: (m['artist'] as String?) ?? '',
        album: (m['album'] as String?) ?? '',
        albumArtist: m['albumArtist'] as String?,
        albumId: (m['albumId'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        trackNumber: (m['trackNumber'] as num?)?.toInt() ?? 0,
        discNumber: (m['discNumber'] as num?)?.toInt() ?? 0,
        year: (m['year'] as num?)?.toInt() ?? 0,
        uri: _uriOf(m),
        artworkUri: m['artworkUri'] as String?,
        mimeType: m['mimeType'] as String?,
        dateAddedSec: (m['dateAddedSec'] as num?)?.toInt() ?? 0,
      );

  /// Queue snapshots from the Android engine carry no uri; remote tracks are addressed by their key anyway.
  static String _uriOf(Map<dynamic, dynamic> m) {
    final given = (m['uri'] as String?) ?? '';
    if (given.isNotEmpty) return given;
    final id = m['mediaId'] as String;
    return TrackKeys.isRemote(id) ? Uri(scheme: 'aurora', host: 'stream', queryParameters: {'k': id}).toString() : '';
  }

  Map<String, Object?> toMap() => {
        'mediaId': mediaId,
        'title': title,
        'artist': artist,
        'albumArtist': albumArtist,
        'album': album,
        'albumId': albumId,
        'durationMs': durationMs,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'year': year,
        'uri': uri,
        'artworkUri': artworkUri,
        'mimeType': mimeType,
        'dateAddedSec': dateAddedSec,
        'remote': isRemote,
      };

  @override
  bool operator ==(Object other) => other is Track && other.mediaId == mediaId;

  @override
  int get hashCode => mediaId.hashCode;
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUri,
    this.artworkBytes,
    this.year = 0,
    this.trackCount = 0,
  });

  final int id;
  final String title;
  final String artist;
  final String? artworkUri;
  final Uint8List? artworkBytes;
  final int year;
  final int trackCount;

  factory Album.fromMap(Map<dynamic, dynamic> m) => Album(
        id: (m['id'] as num).toInt(),
        title: (m['title'] as String?) ?? '',
        artist: (m['artist'] as String?) ?? '',
        artworkUri: m['artworkUri'] as String?,
        year: (m['year'] as num?)?.toInt() ?? 0,
        trackCount: (m['trackCount'] as num?)?.toInt() ?? 0,
      );

  /// A track-shaped handle so artwork widgets can take either.
  Track get asArtTrack => Track(
        mediaId: 'album:$id',
        title: title,
        artist: artist,
        artworkUri: artworkUri,
        artworkBytes: artworkBytes,
      );
}

enum LibraryState { needsPermission, scanning, ready }

class LibraryData {
  const LibraryData({
    this.state = LibraryState.scanning,
    this.tracks = const [],
    this.albums = const [],
  });
  final LibraryState state;
  final List<Track> tracks;
  final List<Album> albums;
}

enum RepeatMode { off, all, one }

class Snapshot {
  const Snapshot({
    this.isPlaying = false,
    this.isBuffering = false,
    this.queue = const [],
    this.currentIndex = -1,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.speed = 1.0,
    this.hasNext = false,
    this.hasPrevious = false,
    this.automix = false,
  });

  final bool isPlaying;
  final bool isBuffering;
  final List<Track> queue;
  final int currentIndex;
  final bool shuffle;
  final RepeatMode repeat;
  final double speed;
  final bool hasNext;
  final bool hasPrevious;
  final bool automix;

  Track? get current => currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  factory Snapshot.fromMap(Map<dynamic, dynamic> m) => Snapshot(
        isPlaying: m['isPlaying'] == true,
        isBuffering: m['isBuffering'] == true,
        currentIndex: (m['currentIndex'] as num?)?.toInt() ?? -1,
        shuffle: m['shuffle'] == true,
        repeat: RepeatMode.values[((m['repeat'] as num?)?.toInt() ?? 0).clamp(0, 2)],
        speed: (m['speed'] as num?)?.toDouble() ?? 1.0,
        hasNext: m['hasNext'] == true,
        hasPrevious: m['hasPrevious'] == true,
        automix: m['automix'] == true,
        queue: [for (final q in (m['queue'] as List? ?? const [])) Track.fromMap(q as Map)],
      );
}

class Progress {
  const Progress([this.positionMs = 0, this.durationMs = 0, this.bufferedMs = 0]);
  final int positionMs;
  final int durationMs;
  final int bufferedMs;

  double get fraction => durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
}

class TrackAnalysis {
  const TrackAnalysis({required this.bpm, required this.confidence, required this.waveform});
  final double bpm;
  final double confidence;
  final List<double> waveform;
}

String formatTime(int ms) {
  final s = (ms / 1000).floor().clamp(0, 359999);
  final m = s ~/ 60;
  final r = s % 60;
  if (m >= 60) {
    final h = m ~/ 60;
    return '$h:${(m % 60).toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
  return '$m:${r.toString().padLeft(2, '0')}';
}

class PlaybackError {
  PlaybackError(this.message) : at = DateTime.now();
  final String message;
  final DateTime at;
}

enum ItemKind { song, album, playlist, artist }

/// A card in the online catalog: something you can open (album, playlist, artist) or play (song).
class CatalogItem {
  const CatalogItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    this.track,
    this.year = 0,
    this.description = '',
  });

  final ItemKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final Track? track;
  final int year;
  final String description;

  Track get artTrack => Track(mediaId: 'item:$id', title: title, artist: subtitle, artworkUri: imageUrl);
}

enum SectionStyle { wide, square, circle, songs, chart }

class HomeSection {
  const HomeSection(this.title, this.items, {this.style = SectionStyle.square, this.caption = ''});
  final String title;
  final List<CatalogItem> items;
  final SectionStyle style;
  final String caption;
}

class ArtistPage {
  const ArtistPage({
    required this.id,
    required this.name,
    this.imageUrl,
    this.bio = '',
    this.followers = '',
    this.topSongs = const [],
    this.albums = const [],
    this.singles = const [],
    this.similar = const [],
    this.playlists = const [],
    this.genres = const [],
    this.facts = '',
  });
  final String id;
  final String name;
  final String? imageUrl;
  final String bio;
  final String followers;
  final List<Track> topSongs;
  final List<CatalogItem> albums;
  final List<CatalogItem> singles;
  final List<CatalogItem> similar;
  final List<CatalogItem> playlists;
  final List<String> genres;
  final String facts;
}

class CollectionPage {
  const CollectionPage({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    this.description = '',
    this.year = 0,
    this.tracks = const [],
  });
  final String id;
  final ItemKind kind;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String description;
  final int year;
  final List<Track> tracks;
}

class SearchBundle {
  const SearchBundle({
    this.topArtist,
    this.artists = const [],
    this.songs = const [],
    this.albums = const [],
    this.playlists = const [],
  });
  final CatalogItem? topArtist;
  final List<CatalogItem> artists;
  final List<Track> songs;
  final List<CatalogItem> albums;
  final List<CatalogItem> playlists;
  bool get isEmpty => topArtist == null && artists.isEmpty && songs.isEmpty && albums.isEmpty && playlists.isEmpty;
}
