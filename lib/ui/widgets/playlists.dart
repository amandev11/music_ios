import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';

/// User playlists live in Settings (JSON); these helpers keep the edits in one place.
class UserPlaylists {
  /// The pinned "Liked Songs" playlist always exists and always sits first.
  static const likedId = 'liked';

  static List<Map<String, dynamic>> all() {
    final l = AppController.I.settings.playlists;
    final i = l.indexWhere((p) => p['id'] == likedId);
    if (i < 0) {
      l.insert(0, {'id': likedId, 'name': 'Liked Songs', 'tracks': <Map<String, dynamic>>[]});
    } else if (i > 0) {
      l.insert(0, l.removeAt(i));
    }
    return l;
  }

  static bool isLiked(String mediaId) {
    final p = all().first;
    return (p['tracks'] as List).any((m) => (m as Map)['mediaId'] == mediaId);
  }

  /// Likes or unlikes [t]; newest likes go to the top.
  static void toggleLike(Track t) {
    final list = all();
    final tracks = List<Map<String, dynamic>>.from((list.first['tracks'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final i = tracks.indexWhere((m) => m['mediaId'] == t.mediaId);
    if (i >= 0) {
      tracks.removeAt(i);
    } else {
      tracks.insert(0, t.toMap().map((k, v) => MapEntry(k, v)));
    }
    list.first['tracks'] = tracks;
    AppController.I.settings.playlists = list;
  }

  static String create(String name) {
    final list = all();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    list.add({'id': id, 'name': name.trim().isEmpty ? 'New playlist' : name.trim(), 'tracks': <Map<String, dynamic>>[]});
    AppController.I.settings.playlists = list;
    return id;
  }

  static void add(String id, Track t) {
    final list = all();
    for (final p in list) {
      if (p['id'] == id) {
        final tracks = List<Map<String, dynamic>>.from((p['tracks'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        if (!tracks.any((m) => m['mediaId'] == t.mediaId)) tracks.add(t.toMap().map((k, v) => MapEntry(k, v)));
        p['tracks'] = tracks;
      }
    }
    AppController.I.settings.playlists = list;
  }

  static void removeTrack(String id, String mediaId) {
    final list = all();
    for (final p in list) {
      if (p['id'] == id) {
        p['tracks'] = [for (final m in (p['tracks'] as List)) if ((m as Map)['mediaId'] != mediaId) m];
      }
    }
    AppController.I.settings.playlists = list;
  }

  static void delete(String id) {
    if (id == likedId) return;
    AppController.I.settings.playlists = all()..removeWhere((p) => p['id'] == id);
  }

  static List<Track> tracks(Map<String, dynamic> p) =>
      [for (final m in (p['tracks'] as List)) Track.fromMap(Map<String, dynamic>.from(m as Map))];
}

Future<String?> newPlaylistDialog(BuildContext context) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Name'), onSubmitted: (v) => Navigator.pop(context, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Create')),
      ],
    ),
  );
  if (name == null) return null;
  return UserPlaylists.create(name);
}

Future<void> addToPlaylistDialog(BuildContext context, Track t) async {
  final lists = UserPlaylists.all();
  final pick = await showDialog<String>(
    context: context,
    builder: (_) => SimpleDialog(
      title: const Text('Add to playlist'),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, '+'), child: const Text('+  New playlist')),
        for (final p in lists) SimpleDialogOption(onPressed: () => Navigator.pop(context, p['id'] as String), child: Text(p['name'] as String)),
      ],
    ),
  );
  if (pick == null || !context.mounted) return;
  final id = pick == '+' ? await newPlaylistDialog(context) : pick;
  if (id != null) UserPlaylists.add(id, t);
}
