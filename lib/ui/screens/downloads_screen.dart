import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/downloads.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import '../widgets/page_header.dart';

String _size(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}

/// Songs saved on the device: play them offline, see what is downloading, free the space.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dm = AppController.I.downloads;
    return ListenableBuilder(
      listenable: Listenable.merge([dm, AppController.I.settings]),
      builder: (context, _) {
        final s = AppController.I.settings;
        final saved = dm.tracks;
        final pending = dm.jobs.values.toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: 190),
          children: [
            PageHeader(
              'Downloads',
              subtitle: saved.isEmpty
                  ? 'Nothing saved yet'
                  : '${saved.length} songs · ${_size(dm.totalBytes)}',
            ),
            if (!dm.supported)
              const SizedBox(
                height: 320,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Not on the web',
                  message: 'Offline downloads need the app on your phone or computer.',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text(
                        'Download liked songs automatically',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'New likes are saved for offline play',
                        style: TextStyle(color: context.secondaryText),
                      ),
                      value: s.autoDownloadLiked,
                      onChanged: (v) => s.autoDownloadLiked = v,
                    ),
                  ],
                ),
              ),
              if (saved.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: AccentButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Play all',
                          filled: true,
                          onTap: () => AppController.I.backend.playTracks([
                            for (final t in saved) dm.withLocalUri(t),
                          ], 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AccentButton(
                          icon: Icons.shuffle_rounded,
                          label: 'Shuffle',
                          onTap: () => AppController.I.backend.playTracks(
                            [for (final t in saved) dm.withLocalUri(t)],
                            0,
                            shuffle: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (pending.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(
                    'In progress',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                for (final j in pending) _JobRow(job: j),
              ],
              if (saved.isEmpty && pending.isEmpty)
                const SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.download_for_offline_outlined,
                    title: 'No Downloads',
                    message: 'Open the ⋯ menu on any song and choose Download.',
                  ),
                ),
              for (var i = 0; i < saved.length; i++)
                Dismissible(
                  key: ValueKey(saved[i].mediaId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: Colors.red.withValues(alpha: 0.7),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: Colors.white,
                    ),
                  ),
                  onDismissed: (_) => dm.remove(saved[i].mediaId),
                  child: InkWell(
                    onTap: () => AppController.I.backend.playTracks([
                      for (final t in saved) dm.withLocalUri(t),
                    ], i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Artwork(
                            saved[i],
                            size: 56,
                            radius: context.cardRadius.clamp(3.0, 10.0),
                            px: 160,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  saved[i].title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${saved[i].artist} · ${_size(((s.downloads[saved[i].mediaId]?['bytes']) as num?)?.toInt() ?? 0)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.download_done_rounded,
                            size: 20,
                            color: context.hue,
                          ),
                          IconButton(
                            tooltip: 'Remove download',
                            onPressed: () => dm.remove(saved[i].mediaId),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: context.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (saved.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: AccentButton(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Remove all downloads',
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remove all downloads?'),
                          content: const Text(
                            'The songs stay in your playlists and can be downloaded again.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await dm.removeAll();
                    },
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});
  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final t = job.track;
    final failed = job.state == DownloadState.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Artwork(t, size: 48, radius: 6, px: 120),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (failed)
                  Text(
                    job.error ?? 'Failed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFE5484D),
                    ),
                  )
                else if (job.state == DownloadState.queued &&
                    job.error == 'Waiting for Wi-Fi')
                  Text(
                    'Waiting for Wi-Fi. Allow mobile data in Audio settings to download now.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.secondaryText,
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value:
                          job.state == DownloadState.active && job.progress > 0
                          ? job.progress
                          : null,
                      minHeight: 4,
                      color: context.hue,
                      backgroundColor: context.separator,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => AppController.I.downloads.cancelOrRetry(t.mediaId),
            icon: Icon(
              failed ? Icons.refresh_rounded : Icons.close_rounded,
              color: context.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
