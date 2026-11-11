package com.aurora.music.data.sources.youtube

import com.aurora.music.data.sources.MusicSource
import com.aurora.music.data.sources.SourceKind
import com.aurora.music.data.sources.SourceStream
import com.aurora.music.data.sources.TrackKeys
import com.aurora.music.data.sources.remoteTrack
import com.aurora.music.model.Track
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeStreamLinkHandlerFactory
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.MediaFormat
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * YouTube Music through NewPipeExtractor: the "failsafe" path BitChord falls back to when its own
 * player-client catalogue is turned away. It re-derives signature and `n` parameter itself and is
 * updated upstream when YouTube changes.
 */
class YouTubeMusicSource(
    baseClient: OkHttpClient,
    /** Bitrate ceiling in kbps; lower it on metered connections. */
    @Volatile var maxKbps: Int = Int.MAX_VALUE,
) : MusicSource {

    override val kind = SourceKind.YOUTUBE

    /**
     * Own leash and own connection pool. A pooled connection the far end has quietly stopped answering
     * does not fail, it hangs; and a read timeout alone is per read, so a drip-fed response never ends.
     */
    private val client = baseClient.newBuilder()
        .callTimeout(30, TimeUnit.SECONDS)
        .connectionPool(ConnectionPool(2, 30, TimeUnit.SECONDS))
        .build()

    private val initialised by lazy {
        NewPipe.init(NewPipeDownloader(client), Localization("en", "IN"), ContentCountry("IN"))
        true
    }

    /**
     * One extraction at a time. Each runs YouTube's player JavaScript through Rhino for the `n`
     * transform: CPU work that does not share out when concurrent (1.8 s alone, 16 s with two in flight).
     */
    private val gate = Mutex()

    override suspend fun search(query: String, limit: Int): List<Track> = withContext(Dispatchers.IO) {
        try {
            check(initialised)
            val extractor = ServiceList.YouTube.getSearchExtractor(
                query, listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS), "",
            )
            extractor.fetchPage()
            extractor.initialPage.items
                .filterIsInstance<StreamInfoItem>()
                .mapNotNull(::toTrack)
                .take(limit)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            emptyList()
        }
    }

    override suspend fun stream(rawId: String): SourceStream? {
        var attempt = 0
        while (attempt < ATTEMPTS) {
            if (attempt > 0) delay(RETRY_MS * attempt)
            try {
                return extract(rawId)
            } catch (e: CancellationException) {
                throw e
            } catch (_: ContentNotAvailableException) {
                // Age-restricted, region-blocked, private, paid: a verdict about the track, not this minute.
                return null
            } catch (_: LinkageError) {
                // The extractor cannot run on this OS build; retrying yields the same error.
                return null
            } catch (_: Exception) {
                attempt++
            }
        }
        return null
    }

    private suspend fun extract(videoId: String): SourceStream = gate.withLock {
        withContext(Dispatchers.IO) {
            withTimeout(EXTRACT_TIMEOUT_MS) {
                check(initialised)
                // Driven through the stream extractor directly rather than StreamInfo.getInfo: getInfo
                // transforms `n` for every video format too (49.8 s measured vs 2.3 s for audio alone).
                val extractor = ServiceList.YouTube.getStreamExtractor("https://www.youtube.com/watch?v=$videoId")
                extractor.fetchPage()
                val chosen = pickAudio(extractor.audioStreams)
                    ?: throw IOException("No audio streams for $videoId")
                SourceStream(
                    url = chosen.content,
                    mimeType = chosen.format?.mimeType,
                    kbps = chosen.averageBitrate.takeIf { it > 0 },
                    // googlevideo throttles or refuses a fetch whose headers disagree with the client that
                    // minted the URL; the resolver rewrites these per URL.
                    headers = emptyMap(),
                )
            }
        }
    }

    /** Progressive streams only (DASH/HLS entries carry a manifest, not a URL); best bitrate under the cap. */
    private fun pickAudio(all: List<AudioStream>): AudioStream? {
        val progressive = all.filter {
            !it.content.isNullOrBlank() && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP
        }
        val capped = progressive.filter { it.averageBitrate <= 0 || it.averageBitrate <= maxKbps }
            .ifEmpty { progressive.minByOrNull { it.averageBitrate }?.let(::listOf).orEmpty() }
        return capped.sortedWith(
            compareByDescending<AudioStream> { it.averageBitrate }
                .thenByDescending { it.format == MediaFormat.WEBMA_OPUS },
        ).firstOrNull()
    }

    private fun toTrack(item: StreamInfoItem): Track? {
        val id = runCatching { YoutubeStreamLinkHandlerFactory.getInstance().getId(item.url) }.getOrNull()
            ?: return null
        val thumb = item.thumbnails.maxByOrNull { it.height }?.url?.let(::upscale)
        return remoteTrack(
            key = TrackKeys.youtube(id),
            title = item.name.orEmpty(),
            artist = item.uploaderName.orEmpty().removeSuffix(" - Topic"),
            album = "",
            durationSec = item.duration.coerceAtLeast(0L),
            artwork = thumb,
        )
    }

    /** YouTube Music art is served small; googleusercontent URLs take a size suffix. */
    private fun upscale(url: String): String =
        if ("googleusercontent.com" in url || "ggpht.com" in url) {
            url.replace(Regex("=w\\d+-h\\d+[^&?]*"), "=w544-h544-l90-rj")
        } else url

    private companion object {
        const val ATTEMPTS = 3
        const val RETRY_MS = 1_000L
        const val EXTRACT_TIMEOUT_MS = 40_000L
    }
}
