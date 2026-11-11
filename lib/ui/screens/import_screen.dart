import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../sources/playlist_import.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/playlists.dart';
import 'home.dart';
import 'playlist_screen.dart';

/// Bring a playlist over from another service: paste its link (Spotify, Apple Music, YouTube / YouTube
/// Music, Deezer), or paste a list / load a CSV export from any other service.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _link = TextEditingController();
  final _name = TextEditingController();
  final _text = TextEditingController();
  late final _importer = PlaylistImporter(AppController.I.settings);

  bool _busy = false;
  String _status = '';
  double? _progress;
  List<ImportItem> _missed = const [];
  String? _error;
  List<Track>? _pending;
  final _pendingName = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    _text.dispose();
    _pendingName.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ImportedPlaylist?> Function() read) async {
    setState(() {
      _busy = true;
      _error = null;
      _missed = const [];
      _pending = null;
      _status = 'Reading playlist...';
      _progress = null;
    });
    final list = await read();
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _busy = false;
        _error = 'Could not read that playlist. Check the link is public, or paste the track list below instead.';
      });
      return;
    }
    var tracks = <Track>[...list.ready];
    var missed = <ImportItem>[];
    if (list.items.isNotEmpty) {
      setState(() => _status = 'Matching ${list.items.length} songs...');
      final r = await _importer.match(list.items, AppController.I.backend.searchRemote, (d, t) {
        if (mounted) setState(() => _progress = d / t);
      });
      tracks = [...tracks, ...r.matched];
      missed = r.missed;
    }
    if (!mounted) return;
    if (tracks.isEmpty) {
      setState(() {
        _busy = false;
        _missed = missed;
        _error = 'None of the songs could be found on the available sources.';
      });
      return;
    }
    // Nothing is stored yet: the user reviews the result and chooses Save or Discard.
    _pendingName.text = list.name.trim().isEmpty ? 'Imported playlist' : list.name.trim();
    setState(() {
      _busy = false;
      _pending = tracks;
      _missed = missed;
      _status = 'Found ${tracks.length} of ${tracks.length + missed.length} songs.';
      _progress = null;
    });
  }

  void _save() {
    final tracks = _pending;
    if (tracks == null || tracks.isEmpty) return;
    final name = _pendingName.text.trim().isEmpty ? 'Imported playlist' : _pendingName.text.trim();
    final id = UserPlaylists.create(name);
    for (final t in tracks) {
      UserPlaylists.add(id, t);
    }
    setState(() {
      _pending = null;
      _missed = const [];
      _status = 'Saved ${tracks.length} songs to "$name".';
    });
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => PlaylistScreen(id: id)));
  }

  void _discard() => setState(() {
        _pending = null;
        _missed = const [];
        _status = 'Import discarded.';
      });

  void _removePending(Track t) => setState(() => _pending = [for (final x in _pending!) if (x.mediaId != t.mediaId) x]);

  Widget _review(BuildContext context) {
    final tracks = _pending!;
    return Glass(
      radius: BorderRadius.circular(24),
      blur: 24,
      border: true,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Review import', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${tracks.length} songs ready${_missed.isEmpty ? '' : ' · ${_missed.length} not found'}. Remove any you do not want, then save or discard.',
              style: TextStyle(color: context.secondaryText, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(controller: _pendingName, decoration: const InputDecoration(hintText: 'Playlist name')),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tracks.length,
              itemBuilder: (_, i) {
                final t = tracks[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Artwork(t, size: 40, radius: 8, px: 120),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.secondaryText, fontSize: 12)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: Icon(Icons.close_rounded, size: 18, color: context.secondaryText),
                      onPressed: () => _removePending(t),
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            AccentButton(icon: Icons.check_rounded, label: 'Save playlist', filled: true, onTap: tracks.isEmpty ? () {} : _save),
            AccentButton(icon: Icons.delete_outline_rounded, label: 'Discard', onTap: _discard),
          ]),
        ]),
      ),
    );
  }

  Future<void> _pickCsv() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['csv', 'txt'], withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    _text.text = utf8.decode(f.bytes!, allowMalformed: true);
    if (_name.text.isEmpty) _name.text = f.name.replaceAll(RegExp(r'\.\w+$'), '');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, scrolledUnderElevation: 0, foregroundColor: context.accent),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, kListBottomPad), children: [
              const Text('Import a playlist', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Songs are matched to JioSaavn and YouTube by title and artist, so a few may not be found. No account or login is needed; the playlist must be public.',
                style: TextStyle(color: context.secondaryText),
              ),
              const SizedBox(height: 24),
              if (_pending != null) ...[
                _review(context),
                const SizedBox(height: 24),
              ],
              const Text('From a link', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Spotify, Apple Music, YouTube / YouTube Music or Deezer playlist links.', style: TextStyle(color: context.secondaryText, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: _link,
                decoration: const InputDecoration(hintText: 'https://open.spotify.com/playlist/...'),
                onSubmitted: (_) => _busy ? null : _run(() => _importer.fromUrl(_link.text)),
              ),
              const SizedBox(height: 12),
              AccentButton(icon: Icons.download_rounded, label: 'Import from link', filled: true, onTap: () => _busy ? null : _run(() => _importer.fromUrl(_link.text))),
              const SizedBox(height: 32),
              const Text('From a list or CSV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Works for any service: export your playlist as CSV (Exportify for Spotify, TuneMyMusic, Soundiiz...) or paste one song per line as "Artist - Title".',
                style: TextStyle(color: context.secondaryText, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(hintText: 'Playlist name')),
              const SizedBox(height: 12),
              TextField(controller: _text, maxLines: 8, minLines: 5, decoration: const InputDecoration(hintText: 'Paste songs or CSV here')),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                AccentButton(icon: Icons.upload_file_rounded, label: 'Choose CSV file', onTap: _pickCsv),
                AccentButton(icon: Icons.playlist_add_rounded, label: 'Import list', filled: true, onTap: () => _busy ? null : _run(() async => _importer.fromText(_name.text, _text.text))),
              ]),
              const SizedBox(height: 24),
              if (_busy || _status.isNotEmpty) Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_busy) Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: _progress)),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFE5484D)))),
              if (_missed.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Not found (${_missed.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final m in _missed.take(40)) Text('${m.title}${m.artist.isEmpty ? '' : ' - ${m.artist}'}', style: TextStyle(color: context.secondaryText, fontSize: 13)),
              ],
            ]),
          ),
        ),
      );
}
