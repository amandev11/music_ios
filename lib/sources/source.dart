import '../core/models.dart';

/// Something playable: a direct URL for just_audio, or a YouTube video id for the web IFrame player.
class Playable {
  const Playable.url(this.url, {this.headers = const {}, this.kbps}) : youtubeId = null;
  const Playable.youtube(this.youtubeId)
      : url = null,
        headers = const {},
        kbps = null;

  final String? url;
  final Map<String, String> headers;
  final String? youtubeId;
  final int? kbps;
}

abstract class MusicSource {
  SourceKind get kind;

  /// Tracks keyed for this source (see [TrackKeys]).
  Future<List<Track>> search(String query, {int limit = 20});

  /// An openable stream for this source's own id, or null when it does not have one.
  Future<Playable?> stream(String rawId);
}

String decodeEntities(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');
