package com.aurora.music.playback

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.util.Size
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSourceBitmapLoader
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.ListeningExecutorService
import com.google.common.util.concurrent.MoreExecutors
import java.util.concurrent.Executors

@UnstableApi
class ArtworkBitmapLoader(private val context: Context) : BitmapLoader {

    private val fallback = DataSourceBitmapLoader(context)
    private val executor: ListeningExecutorService =
        MoreExecutors.listeningDecorator(Executors.newFixedThreadPool(2))

    override fun supportsMimeType(mimeType: String): Boolean = fallback.supportsMimeType(mimeType)

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> = fallback.decodeBitmap(data)

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val isTrackUri = Build.VERSION.SDK_INT >= 29 &&
            uri.scheme == "content" &&
            uri.authority == "media" &&
            uri.path?.startsWith("/external/audio/media/") == true
        if (!isTrackUri) return fallback.loadBitmap(uri)
        return executor.submit<Bitmap> {
            context.contentResolver.loadThumbnail(uri, Size(THUMB_PX, THUMB_PX), null)
        }
    }

    private companion object {
        const val THUMB_PX = 512
    }
}
