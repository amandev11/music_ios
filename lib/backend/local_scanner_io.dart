import 'dart:typed_data';

import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';

import '../core/models.dart';

/// Desktop and iOS: folder scan and file picking, with tags and embedded artwork read from the file.
class LocalScanner {
  static const _exts = {'.mp3', '.m4a', '.aac', '.flac', '.ogg', '.opus', '.wav', '.wma', '.aiff', '.alac'};

  bool get supportsFolders => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<String?> pickFolder() => FilePicker.platform.getDirectoryPath();

  Future<List<Track>> scanFolder(String path) async {
    final out = <Track>[];
    try {
      await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final lower = e.path.toLowerCase();
        if (!_exts.any(lower.endsWith)) continue;
        final t = await readFile(e.path);
        if (t != null) out.add(t);
      }
    } catch (_) {}
    return out;
  }

  Future<(List<Track>, List<String>)> pickFiles() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (res == null) return (const <Track>[], const <String>[]);
    final paths = [for (final f in res.files) if (f.path != null) f.path!];
    final tracks = <Track>[];
    for (final p in paths) {
      final t = await readFile(p);
      if (t != null) tracks.add(t);
    }
    return (tracks, paths);
  }

  Future<Track?> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final name = path.split(RegExp(r'[\\/]')).last;
    final stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    String title = stem, artist = 'Unknown Artist', album = 'Unknown Album';
    int year = 0, trackNo = 0, durationMs = 0;
    List<int>? art;
    try {
      final m = readMetadata(file, getImage: true);
      if ((m.title ?? '').trim().isNotEmpty) title = m.title!.trim();
      if ((m.artist ?? '').trim().isNotEmpty) artist = m.artist!.trim();
      if ((m.album ?? '').trim().isNotEmpty) album = m.album!.trim();
      year = m.year?.year ?? 0;
      trackNo = m.trackNumber ?? 0;
      durationMs = m.duration?.inMilliseconds ?? 0;
      if (m.pictures.isNotEmpty) art = m.pictures.first.bytes;
    } catch (_) {}
    return Track(
      mediaId: TrackKeys.local(path),
      title: title,
      artist: artist,
      album: album,
      albumId: '$album|$artist'.hashCode,
      durationMs: durationMs,
      trackNumber: trackNo,
      year: year,
      uri: path,
      artworkBytes: art == null ? null : Uint8List.fromList(art),
      dateAddedSec: file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000,
    );
  }
}
