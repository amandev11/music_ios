import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/settings.dart';
import '../theme/theme.dart';
import '../widgets/page_header.dart';
import '../widgets/playlists.dart';
import 'appearance_screen.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';

/// Round profile picture: the saved photo, or initials on the accent colour.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      final photo = s.profilePhoto;
      ImageProvider? img;
      if (photo.isNotEmpty) {
        try {
          img = MemoryImage(base64Decode(photo));
        } catch (_) {}
      }
      final name = s.profileName.trim();
      final initials = name.isEmpty
          ? ''
          : name
                .split(RegExp(r'\s+'))
                .take(2)
                .map((w) => w.characters.first.toUpperCase())
                .join();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.hue.withValues(alpha: 0.9),
          image: img == null
              ? null
              : DecorationImage(image: img, fit: BoxFit.cover),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: img != null
            ? null
            : initials.isEmpty
            ? Icon(
                Icons.person_rounded,
                size: size * 0.55,
                color: context.onHue,
              )
            : Text(
                initials,
                style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w800,
                  color: context.onHue,
                ),
              ),
      );
    },
  );
}

class _Stats {
  _Stats(Settings s) {
    final plays = [
      for (final p in s.plays)
        if (p['skip'] != true) p,
    ];
    total = plays.length;
    hours = s.listenedMs / 3600000.0;
    final artists = <String, int>{};
    final songs = <String, (int, Map<String, dynamic>)>{};
    final days = <int>{};
    for (final p in plays) {
      final a = '${p['artist'] ?? ''}'.trim();
      if (a.isNotEmpty) artists[a] = (artists[a] ?? 0) + 1;
      final id = '${p['id']}';
      final prev = songs[id];
      songs[id] = ((prev?.$1 ?? 0) + 1, p);
      final ts = p['ts'];
      if (ts is int) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts);
        days.add(
          DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000,
        );
      }
    }
    topArtists =
        (artists.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .toList();
    topSongs = (songs.values.toList()..sort((a, b) => b.$1.compareTo(a.$1)))
        .take(5)
        .toList();
    artistCount = artists.length;
    final now = s.now;
    var day =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        86400000;
    if (!days.contains(day)) day--; // today may not have a play yet
    var n = 0;
    while (days.contains(day)) {
      n++;
      day--;
    }
    streak = n;
  }

  late final int total;
  late final double hours;
  late final int artistCount;
  late final int streak;
  late final List<MapEntry<String, int>> topArtists;
  late final List<(int, Map<String, dynamic>)> topSongs;
}

/// Who is listening: name, photo, listening stats, top artists and songs, and shortcuts to the personal pages.
/// Nothing here needs an account; it all lives on the device.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final bytes = r?.files.single.bytes;
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      AppController.I.settings.profilePhoto = base64Encode(
        png.buffer.asUint8List(),
      );
    } catch (e) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('That picture could not be used.')),
      );
    }
  }

  Future<void> _rename() async {
    final s = AppController.I.settings;
    final c = TextEditingController(text: s.profileName);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'What should we call you?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v != null) s.profileName = v;
  }

  void _open(Widget page) => Navigator.of(context).push(
    CupertinoPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(bottom: false, child: page),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppController.I.settings,
    builder: (context, _) {
      final s = AppController.I.settings;
      final st = _Stats(s);
      final liked = (UserPlaylists.all().first['tracks'] as List).length;
      final lists = UserPlaylists.all().length - 1;
      final name = s.profileName.isEmpty ? 'Music listener' : s.profileName;
      return ListView(
        padding: const EdgeInsets.only(bottom: 190),
        children: [
          const PageHeader('Profile'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Panel(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(
                      children: [
                        const ProfileAvatar(size: 84),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.bg,
                              border: Border.all(color: context.separator),
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: context.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'On this device · since ${_since(s.firstRunMs)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: context.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            ActionChip(
                              label: const Text('Edit name'),
                              onPressed: _rename,
                              avatar: const Icon(Icons.edit_outlined, size: 16),
                            ),
                            if (s.profilePhoto.isNotEmpty)
                              ActionChip(
                                label: const Text('Remove photo'),
                                onPressed: () => s.profilePhoto = '',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.1,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _stat(
                  context,
                  st.hours >= 10
                      ? st.hours.toStringAsFixed(0)
                      : st.hours.toStringAsFixed(1),
                  'hours listened',
                  Icons.headphones_rounded,
                ),
                _stat(
                  context,
                  '${st.total}',
                  'songs played',
                  Icons.play_circle_outline_rounded,
                ),
                _stat(
                  context,
                  '${st.artistCount}',
                  'artists heard',
                  Icons.person_search_rounded,
                ),
                _stat(
                  context,
                  '${st.streak}',
                  'day streak',
                  Icons.local_fire_department_rounded,
                ),
                _stat(context, '$liked', 'liked songs', Icons.favorite_rounded),
                _stat(
                  context,
                  '$lists',
                  'playlists',
                  Icons.queue_music_rounded,
                ),
                _stat(
                  context,
                  '${s.downloads.length}',
                  'downloaded',
                  Icons.download_done_rounded,
                ),
                _stat(
                  context,
                  '${s.favoriteArtists.length}',
                  'followed artists',
                  Icons.star_rounded,
                ),
              ],
            ),
          ),
          if (st.topArtists.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: PanelLabel('Top artists'),
            ),
            for (var i = 0; i < st.topArtists.length; i++)
              _rank(
                context,
                i + 1,
                st.topArtists[i].key,
                '${st.topArtists[i].value} plays',
                st.topArtists.first.value,
                st.topArtists[i].value,
              ),
          ],
          if (st.topSongs.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: PanelLabel('Top songs'),
            ),
            for (var i = 0; i < st.topSongs.length; i++)
              _rank(
                context,
                i + 1,
                '${st.topSongs[i].$2['title'] ?? ''}',
                '${st.topSongs[i].$2['artist'] ?? ''}',
                st.topSongs.first.$1,
                st.topSongs[i].$1,
              ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: PanelLabel('Yours'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _link(
                    context,
                    Icons.palette_outlined,
                    'Appearance',
                    'Style, accent colour, app icon',
                    () => _open(const AppearanceScreen()),
                  ),
                  _link(
                    context,
                    Icons.download_for_offline_outlined,
                    'Downloads',
                    '${s.downloads.length} songs saved for offline',
                    () => _open(const DownloadsScreen()),
                  ),
                  _link(
                    context,
                    Icons.settings_outlined,
                    'Settings',
                    'Playback, sources, backup',
                    () => _open(const SettingsScreen()),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  static String _since(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[d.month - 1]} ${d.year}';
  }

  Widget _stat(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        Icon(icon, size: 22, color: context.hue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.secondaryText),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _rank(
    BuildContext context,
    int n,
    String title,
    String sub,
    int max,
    int v,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: n == 1 ? context.hue : context.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : v / max,
                  minHeight: 4,
                  color: context.hue,
                  backgroundColor: context.separator,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _link(
    BuildContext context,
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap,
  ) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: context.hue),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub, style: TextStyle(color: context.secondaryText)),
    trailing: Icon(Icons.chevron_right_rounded, color: context.tertiaryText),
  );
}
