package com.aurora.music.audio

import androidx.core.net.toUri
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.ResolvingDataSource
import com.aurora.music.data.sources.SourceRegistry
import com.aurora.music.data.sources.SourceStream
import com.aurora.music.data.sources.TrackKeys
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.util.Locale

/**
 * googlevideo throttles to a crawl, or answers 403, when the fetch's headers disagree with the client
 * that minted the URL. The URL names that client in its `c` parameter, so dress the fetch to match.
 */
object GoogleVideoClients {
    private const val WEB_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    private const val NARROW_RANGE = 512L * 1024
    private const val RANGE = 1024L * 1024

    fun headersFor(url: String): Map<String, String> {
        val uri = url.toUri()
        val host = uri.host ?: return emptyMap()
        if (!host.endsWith("googlevideo.com")) return emptyMap()
        val client = uri.getQueryParameter("c")?.uppercase(Locale.ROOT).orEmpty()
        return when {
            client.startsWith("IOS") -> mapOf("User-Agent" to "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)")
            client == "ANDROID_VR" -> mapOf("User-Agent" to "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip")
            client == "ANDROID_MUSIC" -> mapOf("User-Agent" to "com.google.android.apps.youtube.music/8.39.42 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002) gzip")
            client.startsWith("ANDROID") -> mapOf("User-Agent" to "com.google.android.youtube/21.26.364 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002; Cronet/132.0.6834.79) gzip")
            client == "WEB_REMIX" -> mapOf("User-Agent" to WEB_UA, "Origin" to "https://music.youtube.com", "Referer" to "https://music.youtube.com/")
            client.startsWith("WEB") || client == "MWEB" -> mapOf("User-Agent" to WEB_UA, "Origin" to "https://www.youtube.com", "Referer" to "https://www.youtube.com/")
            else -> mapOf("User-Agent" to WEB_UA)
        }
    }

    fun rangeBytesFor(url: String): Long {
        val uri = url.toUri()
        if (uri.host?.endsWith("googlevideo.com") != true) return Long.MAX_VALUE
        val client = uri.getQueryParameter("c")?.uppercase(Locale.ROOT)
        return if (client == "ANDROID_VR" || client?.startsWith("TVHTML5_SIMPLY") == true) NARROW_RANGE else RANGE
    }
}

/**
 * Turns `aurora://stream?k=<key>` into the real CDN URL at the moment ExoPlayer opens it. URLs are
 * never stored in the queue: they expire, and resolving late means the queue survives process death.
 */
@UnstableApi
class StreamResolver(private val registry: SourceRegistry) : ResolvingDataSource.Resolver {

    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
        val key = TrackKeys.keyFrom(dataSpec.uri) ?: return dataSpec
        val stream: SourceStream = try {
            runBlocking { withTimeout(RESOLVE_TIMEOUT_MS) { registry.resolveStream(key) } }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            throw IOException("Timed out resolving $key", e)
        } ?: throw IOException("No source could serve $key")

        return dataSpec.buildUpon()
            .setUri(stream.url.toUri())
            .setHttpRequestHeaders(stream.headers + GoogleVideoClients.headersFor(stream.url))
            .build()
    }

    private companion object {
        const val RESOLVE_TIMEOUT_MS = 45_000L
    }
}
