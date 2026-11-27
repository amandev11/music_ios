import 'dart:typed_data';

import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';

/// Desktop and iOS: folder scan and file picking, with tags and embedded artwork read from the file.
class LocalScanner {
  static const _exts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
    '.aiff',
    '.alac',
  };

  bool get supportsFolders =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<String?> pickFolder() => FilePicker.platform.getDirectoryPath();

  Future<List<Track>> scanFolder(String path) async {
    final out = <Track>[];
    try {
      await for (final e in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final lower = e.path.toLowerCase();
        if (!_exts.any(lower.endsWith)) continue;
        final t = await readFile(e.path);
        if (t != null) out.add(t);
      }
    } catch (_) {}
    return out;
  }

  bool get _isIos => Platform.isIOS;

  /// iPhone: files are copied in here, because the picker hands out temporary paths and an app container
  /// path changes between installs. Visible in the Files app under "Aurora" too.
  Future<Directory> libraryDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/Music');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Everything inside the app's own Music folder (iPhone / any non-desktop platform).
  Future<List<Track>> scanAppLibrary() async {
    if (supportsFolders) return const [];
    try {
      return await scanFolder((await libraryDir()).path);
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _copyIn(PlatformFile f) async {
    final src = f.path;
    if (src == null) return null;
    final dir = await libraryDir();
    final name = f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var dest = File('${dir.path}/$name');
    if (await dest.exists()) {
      if (await dest.length() == await File(src).length()) return dest.path;
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      dest = File(
        '${dir.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext',
      );
    }
    await File(src).copy(dest.path);
    return dest.path;
  }

  /// [source]: 'library' = the iPhone Music library picker, 'files' = the Files picker, 'any' = default.
  Future<(List<Track>, List<String>)> pickFiles({String source = 'any'}) async {
    FilePickerResult? res;
    try {
      if (_isIos && source == 'library') {
        res = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: true,
        );
      } else if (_isIos) {
        res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const [
            'mp3',
            'm4a',
            'aac',
            'flac',
            'ogg',
            'opus',
            'wav',
            'aiff',
            'alac',
            'wma',
          ],
          allowMultiple: true,
        );
      } else {
        res = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: true,
        );
      }
    } catch (_) {
      return (const <Track>[], const <String>[]);
    }
    if (res == null) return (const <Track>[], const <String>[]);
    final paths = <String>[];
    for (final f in res.files) {
      if (f.path == null) continue;
      try {
        paths.add(_isIos ? (await _copyIn(f) ?? f.path!) : f.path!);
      } catch (_) {}
    }
    final tracks = <Track>[];
    for (final p in paths) {
      final t = await readFile(p);
      if (t != null) tracks.add(t);
    }
    // iPhone files live in the app library and are rescanned on launch: nothing to persist by path.
    return (tracks, _isIos ? const <String>[] : paths);
  }

  Future<Track?> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final name = path.split(RegExp(r'[\\/]')).last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
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
