package com.aurora.music.audio.analysis

import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import com.aurora.music.audio.BitChordAudioEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.max

/**
 * Slides a window over the decoded PCM, runs Beat This! on it, and publishes a media-time grid.
 *
 * Time model: tap frame f of the current epoch plays at media time `originMs + f / sampleRate`.
 * The tap sits before tempo processing, so this holds at any playback speed. The origin is
 * captured on every flush (seek/start) and shifted by the previous item's duration on gapless
 * transitions.
 */
@UnstableApi
class RealtimeBeatAnalyzer(
    private val engine: BitChordAudioEngine,
    private val tracker: BeatTracker,
    val clock: BeatClock,
    private val scope: CoroutineScope,
) {
    private val main = Handler(Looper.getMainLooper())
    private val tap = engine.pcmTap

    @Volatile var originMs: Double = 0.0
        private set

    @Volatile private var epochStartFrame = 0L
    @Volatile private var lastAnalyzedEnd = 0L
    @Volatile private var playing = false
    private var lastItemDurationMs = 0L
    private var job: Job? = null

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            playing = isPlaying
        }

        override fun onMediaItemTransition(mediaItem: androidx.media3.common.MediaItem?, reason: Int) {
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO || reason == Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT) {
                // Gapless: tap frames keep counting. Next item's t=0 sits where the previous one ended.
                originMs -= lastItemDurationMs
                epochStartFrame = tap.framesWritten()
                lastAnalyzedEnd = epochStartFrame
                clock.clear()
            }
            lastItemDurationMs = durationOf(engine.player.currentMediaItem)
        }
    }

    fun start() {
        if (job != null) return
        tap.onReset = {
            main.post {
                originMs = engine.player.currentPosition.toDouble()
                epochStartFrame = 0L
                lastAnalyzedEnd = 0L
                clock.clear()
            }
        }
        main.post {
            engine.player.addListener(listener)
            playing = engine.player.isPlaying
            lastItemDurationMs = durationOf(engine.player.currentMediaItem)
            originMs = engine.player.currentPosition.toDouble() - tap.framesWritten() * 1000.0 / max(1, tap.sampleRate)
        }
        job = scope.launch(Dispatchers.Default) { loop() }
    }

    fun stop() {
        job?.cancel()
        job = null
        tap.onReset = null
        main.post { engine.player.removeListener(listener) }
    }

    private fun durationOf(item: androidx.media3.common.MediaItem?): Long {
        val d = item?.mediaMetadata?.durationMs ?: return 0L
        return if (d == C.TIME_UNSET) 0L else d
    }

    private suspend fun loop() {
        while (scope.isActive) {
            delay(TICK_MS)
            if (!playing) continue
            val sr = tap.sampleRate
            if (sr <= 0) continue

            val gen = tap.generation
            val end = tap.framesWritten()
            val epochStart = epochStartFrame
            val windowFrames = (WINDOW_SEC * sr).toLong()
            val start = max(epochStart, end - windowFrames)
            val available = end - start
            if (available < MIN_SEC * sr) continue
            if (end - lastAnalyzedEnd < HOP_SEC * sr) continue

            val pcm = FloatArray(available.toInt())
            if (tap.read(start, pcm) != pcm.size) continue
            if (tap.generation != gen) continue

            val resampled = Resampler(sr, MelFrontEnd.SAMPLE_RATE).process(pcm)
            val grid = runCatching { tracker.track(resampled) }.getOrNull()

            if (tap.generation != gen || epochStartFrame != epochStart) continue
            lastAnalyzedEnd = end
            if (grid == null) continue

            val origin = withContext(Dispatchers.Main.immediate) { originMs }
            if (tap.generation != gen || epochStartFrame != epochStart) continue
            clock.update(grid, origin, start.toDouble() / sr)
        }
    }

    private companion object {
        const val TICK_MS = 500L
        const val WINDOW_SEC = 12.0
        const val MIN_SEC = 5.0
        const val HOP_SEC = 2.0
    }
}
