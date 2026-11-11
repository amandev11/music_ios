import 'package:file_picker/file_picker.dart';

import '../core/models.dart';
import '../engine/yt_iframe.dart';

/// Browsers cannot scan folders: files are picked, read into memory and played from blob URLs.
class LocalScanner {
  bool get supportsFolders => false;

  Future<String?> pickFolder() async => null;

  Future<List<Track>> scanFolder(String path) async => const [];

  /// Returns the new tracks plus the paths worth persisting (none on web: blob URLs die with the tab).
  Future<(List<Track>, List<String>)> pickFiles() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true, withData: true);
    if (res == null) return (const <Track>[], const <String>[]);
    final tracks = <Track>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      final ext = (f.extension ?? 'mp3').toLowerCase();
      final stem = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
      var artist = 'Unknown Artist';
      var title = stem;
      final dash = stem.indexOf(' - ');
      if (dash > 0) {
        artist = stem.substring(0, dash).trim();
        title = stem.substring(dash + 3).trim();
      }
      tracks.add(Track(
        mediaId: TrackKeys.local('web:${f.name}:${bytes.length}'),
        title: title,
        artist: artist,
        album: 'Unknown Album',
        albumId: 'Unknown Album|$artist'.hashCode,
        uri: blobUrlFor(bytes, _mime(ext)),
        dateAddedSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));
    }
    return (tracks, const <String>[]);
  }

  Future<Track?> readFile(String path) async => null;

  String _mime(String ext) => switch (ext) {
        'mp3' => 'audio/mpeg',
        'm4a' || 'aac' => 'audio/mp4',
        'flac' => 'audio/flac',
        'ogg' || 'opus' => 'audio/ogg',
        'wav' => 'audio/wav',
        _ => 'audio/mpeg',
      };
}
