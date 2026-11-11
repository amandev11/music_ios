package com.aurora.music.audio.analysis

import android.content.Context
import android.util.LruCache
import androidx.media3.common.util.UnstableApi
import com.aurora.music.audio.BitChordAudioEngine
import com.aurora.music.audio.EngineRegistry
import com.aurora.music.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** Owns the model session, the live beat clock and per-track analysis cache. */
@UnstableApi
class AudioFeatureHub(private val context: Context, private val scope: CoroutineScope) {

    private val tracker = BeatTracker(modelBytes = {
        context.assets.open(MODEL_ASSET).use { it.readBytes() }
    })
    private val trackAnalyzer = TrackAnalyzer(context, tracker)
    private val cache = LruCache<String, TrackAnalysis>(64)
    private val gate = Semaphore(1)

    val clock = BeatClock()

    private val _spectrum = MutableStateFlow<SpectrumAnalyzer?>(null)
    val spectrum: StateFlow<SpectrumAnalyzer?> = _spectrum.asStateFlow()

    @Volatile var originMs: Double = 0.0
        private set

    private var analyzer: RealtimeBeatAnalyzer? = null
    private var engineJob: Job? = null

    fun start() {
        if (engineJob != null) return
        engineJob = scope.launch {
            EngineRegistry.engine.collect { engine -> attach(engine) }
        }
    }

    private fun attach(engine: BitChordAudioEngine?) {
        analyzer?.stop()
        analyzer = null
        clock.clear()
        _spectrum.value = null
        if (engine == null) return
        analyzer = RealtimeBeatAnalyzer(engine, tracker, clock, scope).also { it.start() }
        _spectrum.value = SpectrumAnalyzer(engine.pcmTap)
    }

    /** Media-time origin of the current PCM epoch, for [SpectrumAnalyzer.sample]. */
    fun currentOriginMs(): Double = analyzer?.originMs ?: 0.0

    suspend fun analysisFor(track: Track): TrackAnalysis? {
        cache.get(track.mediaId)?.let { return it }
        val result = gate.withPermit { trackAnalyzer.analyze(track.uri) }
        if (result != null) cache.put(track.mediaId, result)
        return result
    }

    suspend fun analysisFor(mediaId: String, uri: String): TrackAnalysis? {
        cache.get(mediaId)?.let { return it }
        val result = gate.withPermit { trackAnalyzer.analyze(uri) }
        if (result != null) cache.put(mediaId, result)
        return result
    }

    /** Applies the tempo ratio that moves a track at [currentBpm] onto [targetBpm]. */
    fun matchTempo(engine: BitChordAudioEngine, currentBpm: Float, targetBpm: Float) =
        engine.matchTempo(currentBpm, targetBpm)

    fun release() {
        engineJob?.cancel()
        analyzer?.stop()
        tracker.release()
    }

    private companion object {
        const val MODEL_ASSET = "beat_this_int8.onnx"
    }
}
