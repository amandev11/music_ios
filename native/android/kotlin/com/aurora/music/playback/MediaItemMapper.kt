package com.aurora.music.playback

import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.aurora.music.model.Album
import com.aurora.music.model.QueueItem
import com.aurora.music.model.Track

object MediaIds {
    const val ROOT = "root"
    const val SONGS = "songs"
    const val ALBUMS = "albums"
    private const val ALBUM_PREFIX = "album:"

    fun album(id: Long) = "$ALBUM_PREFIX$id"
    fun parseAlbum(mediaId: String): Long? =
        if (mediaId.startsWith(ALBUM_PREFIX)) mediaId.removePrefix(ALBUM_PREFIX).toLongOrNull() else null
}

fun Track.toMediaItem(): MediaItem =
    MediaItem.Builder()
        .setMediaId(mediaId)
        .setUri(uri)
        .setMimeType(mimeType)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setDisplayTitle(title)
                .setArtist(artist)
                .setAlbumTitle(album)
                .setAlbumArtist(albumArtist ?: artist)
                .setArtworkUri(artworkUri?.toUri())
                .setTrackNumber(trackNumber.takeIf { it > 0 })
                .setReleaseYear(year.takeIf { it > 0 })
                .setDurationMs(durationMs)
                .setIsPlayable(true)
                .setIsBrowsable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                .build()
        )
        .build()

fun Album.toNodeItem(): MediaItem =
    browsableNode(MediaIds.album(id), title, MediaMetadata.MEDIA_TYPE_ALBUM, artworkUri, artist)

fun browsableNode(
    id: String,
    title: String,
    mediaType: Int,
    artworkUri: String? = null,
    subtitle: String? = null,
): MediaItem =
    MediaItem.Builder()
        .setMediaId(id)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setSubtitle(subtitle)
                .setArtworkUri(artworkUri?.toUri())
                .setIsBrowsable(true)
                .setIsPlayable(false)
                .setMediaType(mediaType)
                .build()
        )
        .build()

fun MediaItem.toQueueItem(index: Int): QueueItem {
    val m = mediaMetadata
    return QueueItem(
        index = index,
        mediaId = mediaId,
        title = (m.title ?: m.displayTitle)?.toString().orEmpty(),
        artist = m.artist?.toString().orEmpty(),
        album = m.albumTitle?.toString().orEmpty(),
        artworkUri = m.artworkUri?.toString(),
        durationMs = m.durationMs ?: 0L,
    )
}
