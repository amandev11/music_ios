package com.aurora.music.data.sources

import android.net.Uri
import com.aurora.music.model.SourceType
import com.aurora.music.model.Track

enum class SourceKind(val label: String, val prefix: String) {
    LOCAL("This Device", "local:"),
    YOUTUBE("YouTube Music", "yt:"),
    JIOSAAVN("JioSaavn", "saavn:"),
}

/** Media ids double as routing keys: the prefix says which source serves the track. */
object TrackKeys {
    const val STREAM_SCHEME = "aurora"
    const val STREAM_HOST = "stream"

    fun youtube(videoId: String) = "${SourceKind.YOUTUBE.prefix}$videoId"
    fun saavn(id: String) = "${SourceKind.JIOSAAVN.prefix}$id"

    fun kindOf(mediaId: String): SourceKind =
        SourceKind.entries.firstOrNull { mediaId.startsWith(it.prefix) } ?: SourceKind.LOCAL

    fun rawId(mediaId: String): String = mediaId.removePrefix(kindOf(mediaId).prefix)

    fun isRemote(mediaId: String) = kindOf(mediaId) != SourceKind.LOCAL

    /** URI handed to ExoPlayer; the real URL is resolved lazily when playback opens it. */
    fun streamUri(key: String): String =
        Uri.Builder().scheme(STREAM_SCHEME).authority(STREAM_HOST).appendQueryParameter("k", key).build().toString()

    fun keyFrom(uri: Uri): String? =
        if (uri.scheme == STREAM_SCHEME && uri.authority == STREAM_HOST) uri.getQueryParameter("k") else null
}

data class SourceStream(
    val url: String,
    val mimeType: String? = null,
    val kbps: Int? = null,
    val headers: Map<String, String> = emptyMap(),
    val durationSec: Int? = null,
)

interface MusicSource {
    val kind: SourceKind

    /** Tracks matching [query], already keyed for this source (see [TrackKeys]). */
    suspend fun search(query: String, limit: Int = 20): List<Track>

    /** An openable stream for this source's own id, or null when it turns out not to have it. */
    suspend fun stream(rawId: String): SourceStream?
}

internal fun remoteTrack(
    key: String,
    title: String,
    artist: String,
    album: String,
    durationSec: Long,
    artwork: String?,
    mime: String? = null,
) = Track(
    mediaId = key,
    title = title,
    artist = artist.ifBlank { "Unknown Artist" },
    albumArtist = null,
    album = album,
    albumId = key.hashCode().toLong(),
    durationMs = durationSec * 1000L,
    trackNumber = 0,
    discNumber = 0,
    year = 0,
    uri = TrackKeys.streamUri(key),
    artworkUri = artwork,
    mimeType = mime,
    dateAddedSec = 0L,
    source = SourceType.NETWORK,
)
