package com.aurora.music.model


enum class SourceType { LOCAL, NETWORK }

enum class RepeatMode { OFF, ALL, ONE }

data class Track(
    val mediaId: String,
    val title: String,
    val artist: String,
    val albumArtist: String?,
    val album: String,
    val albumId: Long,
    val durationMs: Long,
    val trackNumber: Int,
    val discNumber: Int,
    val year: Int,
    val uri: String,
    val artworkUri: String?,
    val mimeType: String?,
    val dateAddedSec: Long,
    val source: SourceType = SourceType.LOCAL,
)

data class Album(
    val id: Long,
    val title: String,
    val artist: String,
    val artworkUri: String?,
    val year: Int,
    val trackCount: Int,
)

data class QueueItem(
    val index: Int,
    val mediaId: String,
    val title: String,
    val artist: String,
    val album: String,
    val artworkUri: String?,
    val durationMs: Long,
) {
    val key: String get() = "$mediaId#$index"
}

data class PlaybackSnapshot(
    val isPlaying: Boolean = false,
    val playWhenReady: Boolean = false,
    val isBuffering: Boolean = false,
    val queue: List<QueueItem> = emptyList(),
    val currentIndex: Int = -1,
    val shuffle: Boolean = false,
    val repeat: RepeatMode = RepeatMode.OFF,
    val speed: Float = 1f,
    val hasNext: Boolean = false,
    val hasPrevious: Boolean = false,
) {
    val current: QueueItem? get() = queue.getOrNull(currentIndex)
}

data class Progress(
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val bufferedMs: Long = 0L,
) {
    val fraction: Float
        get() = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
}

enum class LibraryState { NeedsPermission, Scanning, Ready }
