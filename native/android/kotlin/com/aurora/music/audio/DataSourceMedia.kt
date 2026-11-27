package com.aurora.music.audio

import android.media.MediaDataSource
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.io.IOException

/**
 * Lets MediaExtractor read a streamed song through the player's own cache and resolver chain, so a song that
 * is only reachable as aurora://stream?... can still be analysed (tempo, bars, loudness) before it plays.
 */
@UnstableApi
class DataSourceMedia(private val factory: DataSource.Factory, private val uri: Uri) : MediaDataSource() {
    private var ds: DataSource? = null
    private var pos = -1L
    private var length = -1L

    @Synchronized
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (size == 0) return 0
        try {
            if (ds == null || pos != position) {
                runCatching { ds?.close() }
                ds = null
                val d = factory.createDataSource()
                val len = d.open(DataSpec(uri, position, C.LENGTH_UNSET.toLong()))
                if (length < 0 && len != C.LENGTH_UNSET.toLong()) length = position + len
                ds = d
                pos = position
            }
            val n = ds!!.read(buffer, offset, size)
            if (n == C.RESULT_END_OF_INPUT) return -1
            pos += n
            return n
        } catch (e: Exception) {
            runCatching { ds?.close() }
            ds = null
            pos = -1L
            throw IOException(e)
        }
    }

    @Synchronized
    override fun getSize(): Long {
        if (length >= 0) return length
        return try {
            val d = factory.createDataSource()
            val len = d.open(DataSpec(uri))
            runCatching { d.close() }
            if (len == C.LENGTH_UNSET.toLong()) -1L else len.also { length = it }
        } catch (e: Exception) {
            -1L
        }
    }

    @Synchronized
    override fun close() {
        runCatching { ds?.close() }
        ds = null
    }
}
