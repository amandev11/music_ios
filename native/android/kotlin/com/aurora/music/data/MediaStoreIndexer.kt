package com.aurora.music.data

import android.content.ContentResolver
import android.content.ContentUris
import android.os.Build
import android.provider.MediaStore
import com.aurora.music.model.SourceType
import com.aurora.music.model.Track

class MediaStoreIndexer(private val resolver: ContentResolver) {

    fun queryTracks(minDurationMs: Long = 30_000L): List<Track> {
        val base = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val collection = if (Build.VERSION.SDK_INT >= 29) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else base

        val hasAlbumArtist = Build.VERSION.SDK_INT >= 30
        val projection = buildList {
            add(MediaStore.Audio.Media._ID)
            add(MediaStore.Audio.Media.TITLE)
            add(MediaStore.Audio.Media.ARTIST)
            add(MediaStore.Audio.Media.ALBUM)
            add(MediaStore.Audio.Media.ALBUM_ID)
            add(MediaStore.Audio.Media.DURATION)
            add(MediaStore.Audio.Media.TRACK)
            add(MediaStore.Audio.Media.YEAR)
            add(MediaStore.Audio.Media.DATE_ADDED)
            add(MediaStore.Audio.Media.MIME_TYPE)
            if (hasAlbumArtist) add(ALBUM_ARTIST_COLUMN)
        }.toTypedArray()

        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= ?"
        val args = arrayOf(minDurationMs.toString())
        val out = ArrayList<Track>(1024)

        resolver.query(collection, projection, selection, args, null)?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val iAlbumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val iDur = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val iTrack = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val iYear = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val iAdded = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val iMime = c.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val iAlbumArtist = if (hasAlbumArtist) c.getColumnIndex(ALBUM_ARTIST_COLUMN) else -1

            while (c.moveToNext()) {
                val id = c.getLong(iId)
                val albumId = c.getLong(iAlbumId)
                val uri = ContentUris.withAppendedId(base, id)
                val artwork = if (Build.VERSION.SDK_INT >= 29) {
                    uri.toString()
                } else {
                    ContentUris.withAppendedId(Uri_ALBUM_ART, albumId).toString()
                }
                val rawTrack = c.getInt(iTrack)
                out += Track(
                    mediaId = "$LOCAL_PREFIX$id",
                    title = c.getString(iTitle).clean() ?: "Unknown Title",
                    artist = c.getString(iArtist).clean() ?: "Unknown Artist",
                    albumArtist = if (iAlbumArtist >= 0) c.getString(iAlbumArtist).clean() else null,
                    album = c.getString(iAlbum).clean() ?: "Unknown Album",
                    albumId = albumId,
                    durationMs = c.getLong(iDur),
                    trackNumber = rawTrack % 1000,
                    discNumber = rawTrack / 1000,
                    year = c.getInt(iYear),
                    uri = uri.toString(),
                    artworkUri = artwork,
                    mimeType = c.getString(iMime),
                    dateAddedSec = c.getLong(iAdded),
                    source = SourceType.LOCAL,
                )
            }
        }
        return out.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
    }

    private fun String?.clean(): String? =
        this?.trim()?.takeIf { it.isNotEmpty() && it != "<unknown>" }

    companion object {
        const val LOCAL_PREFIX = "local:"
        private const val ALBUM_ARTIST_COLUMN = "album_artist"
        private val Uri_ALBUM_ART = android.net.Uri.parse("content://media/external/audio/albumart")
    }
}
