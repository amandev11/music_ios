package com.aurora.music.audio

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

@UnstableApi
class BitChordAudioEngine(context: Context, streamResolver: ResolvingDataSource.Resolver? = null) {

    val pcmProcessor = PcmTapAudioProcessor()
    val pcmTap: PcmTap get() = pcmProcessor.tap

    private val appContext = context.applicationContext

    private val cache = SimpleCache(
        File(appContext.cacheDir, "audio_cache"),
        LeastRecentlyUsedCacheEvictor(CACHE_BYTES),
        StandaloneDatabaseProvider(appContext),
    )

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    val player: ExoPlayer
    private lateinit var dataSources: DataSource.Factory

    init {
        val okhttp = OkHttpDataSource.Factory(http).setUserAgent(USER_AGENT)
        // aurora://stream?k=<key> is swapped for the real CDN URL as the cache misses through to the
        // network; the cache key stays the stable aurora:// URI, so expiring URLs never split an entry.
        val upstream: DataSource.Factory = if (streamResolver != null) {
            ResolvingDataSource.Factory(ChunkedDataSource.Factory(okhttp, STREAM_CHUNK_BYTES), streamResolver)
        } else okhttp
        val cached = CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(upstream)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

        // http(s) goes through the cache; content:// and file:// use their native sources.
        dataSources = DefaultDataSource.Factory(appContext, cached)

        val renderers = object : DefaultRenderersFactory(appContext) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): AudioSink = DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(false)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                .setAudioProcessors(arrayOf(pcmProcessor))
                .build()
        }.setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)

        player = ExoPlayer.Builder(appContext, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSources))
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setUseLazyPreparation(true)
            .build()
    }

    /** A second player on the same cache/resolver chain, used for Automix crossfades. No audio focus, no PCM tap. */
    fun createAuxPlayer(): ExoPlayer = ExoPlayer.Builder(appContext)
        .setMediaSourceFactory(DefaultMediaSourceFactory(dataSources))
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
            false,
        )
        .build()

    /** Lets the platform spatialiser (Android 12L+) virtualise multichannel/stereo output, or opts out. */
    fun setSpatialAudio(enabled: Boolean) {
        val attrs = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .setSpatializationBehavior(
                if (enabled) C.SPATIALIZATION_BEHAVIOR_AUTO else C.SPATIALIZATION_BEHAVIOR_NEVER
            )
            .build()
        player.setAudioAttributes(attrs, true)
    }

    fun setTempoRatio(ratio: Float) {
        player.playbackParameters = PlaybackParameters(ratio.coerceIn(MIN_TEMPO, MAX_TEMPO), 1f)
    }

    /** Tempo ratio that makes [currentBpm] land on [targetBpm]; folds half/double-time into range. */
    fun matchTempo(currentBpm: Float, targetBpm: Float) {
        if (currentBpm <= 0f || targetBpm <= 0f) return
        var ratio = targetBpm / currentBpm
        while (ratio > MAX_TEMPO) ratio /= 2f
        while (ratio < MIN_TEMPO) ratio *= 2f
        setTempoRatio(ratio)
    }

    fun release() {
        player.release()
        cache.release()
    }

    companion object {
        const val MIN_TEMPO = 0.5f
        const val MAX_TEMPO = 2.0f
        private const val CACHE_BYTES = 512L * 1024 * 1024
        private const val STREAM_CHUNK_BYTES = 1024L * 1024
        private const val USER_AGENT = "Aurora/1.0"
    }
}

object EngineRegistry {
    private val _engine = MutableStateFlow<BitChordAudioEngine?>(null)
    val engine: StateFlow<BitChordAudioEngine?> = _engine.asStateFlow()

    fun publish(engine: BitChordAudioEngine) {
        _engine.value = engine
    }

    fun clear(engine: BitChordAudioEngine) {
        if (_engine.value === engine) _engine.value = null
    }
}
