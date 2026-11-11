import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import 'playlists.dart';

/// Heart that adds or removes [track] from the pinned Liked Songs playlist.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.track, this.size = 24, this.color});
  final Track? track;
  final double size;

  /// Colour of the outline heart; the filled heart is always the accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: AppController.I.settings,
      builder: (context, _) {
        final liked = UserPlaylists.isLiked(t.mediaId);
        return IconButton(
          tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
          visualDensity: VisualDensity.compact,
          icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: size, color: liked ? (context.isDark ? Colors.white : Colors.black87) : (color ?? context.secondaryText)),
          onPressed: () => UserPlaylists.toggleLike(t),
        );
      },
    );
  }
}
