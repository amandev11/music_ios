package com.aurora.music.audio

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Automix: an equal-power crossfade into the next queue item.
 *
 * ExoPlayer cannot overlap two items, so a second player starts the next track while the main one
 * fades out. When the fade ends the main player is moved onto the next item at the aux player's
 * position, and a short reverse crossfade hands playback back to it, so the session, notification and
 * visualiser keep following a single player. Everything runs on the main thread.
 */
@UnstableApi
class AutomixController(context: Context, private val tempo: () -> Pair<Float, Float> = { 0f to 0f }) {
    private val prefs = context.getSharedPreferences("automix", Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())

    var enabled: Boolean = prefs.getBoolean("on", false)
        private set
    var seconds: Float = prefs.getFloat("sec", 8f)
        private set

    /** True: the blend length is chosen per song (from its tempo or length). False: always [seconds]. */
    var auto: Boolean = prefs.getBoolean("auto", true)
        private set

    private var plannedMs = 0L

    private var engine: BitChordAudioEngine? = null
    private var aux: ExoPlayer? = null
    private var fading = false
    private var token = 0

    private val poll = object : Runnable {
        override fun run() {
            tick()
            handler.postDelayed(this, 250)
        }
    }

    fun attach(e: BitChordAudioEngine?) {
        handler.removeCallbacks(poll)
        abort()
        engine = e
        if (e != null) handler.post(poll)
    }

    fun set(enabled: Boolean, seconds: Float, auto: Boolean) {
        this.enabled = enabled
        this.seconds = seconds.coerceIn(1f, 30f)
        this.auto = auto
        prefs.edit().putBoolean("on", this.enabled).putFloat("sec", this.seconds).putBoolean("auto", auto).apply()
        if (!enabled) abort()
    }

    private fun tick() {
        val p = engine?.player ?: return
        if (!enabled || fading || !p.isPlaying || p.repeatMode == Player.REPEAT_MODE_ONE) return
        val next = p.nextMediaItemIndex
        if (next == C.INDEX_UNSET) return
        val dur = p.duration
        if (dur == C.TIME_UNSET || dur <= 0) return
        val fadeMs = fadeMsFor(dur)
        if (fadeMs < 1000 || dur < fadeMs * 2 + 2000) return
        val remaining = dur - p.currentPosition
        if (remaining in 801..fadeMs) {
            plannedMs = fadeMs
            startFade(p, next)
        }
    }

    /** Blend length for the playing song: a fixed time, or about 16 beats (6-16 s), or 4.5% of the song. */
    private fun fadeMsFor(dur: Long): Long {
        if (!auto) return min((seconds * 1000).toLong(), dur / 4)
        val (bpm, confidence) = tempo()
        val natural = if (bpm in 60f..200f && confidence > 0.4f) {
            (16 * 60000f / bpm).toLong().coerceIn(6000L, 16000L)
        } else {
            (dur * 0.045f).toLong().coerceIn(4000L, 9000L)
        }
        return min(natural, dur / 4)
    }

    private fun startFade(main: ExoPlayer, next: Int) {
        val e = engine ?: return
        fading = true
        val my = ++token
        val startedIndex = main.currentMediaItemIndex
        val a = e.createAuxPlayer()
        aux = a
        a.volume = 0f
        a.setMediaItem(main.getMediaItemAt(next))
        a.prepare()
        a.playWhenReady = true

        val t0 = SystemClock.uptimeMillis()
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                when {
                    a.isPlaying -> ramp(main, a, next, startedIndex, my)
                    SystemClock.uptimeMillis() - t0 > 6000 || !main.isPlaying -> abort()
                    else -> handler.postDelayed(this, 50)
                }
            }
        })
    }

    private fun ramp(main: ExoPlayer, a: ExoPlayer, next: Int, startedIndex: Int, my: Int) {
        val remaining = main.duration - main.currentPosition
        val total = min(min(plannedMs, main.duration / 4), remaining - 500)
        if (total < 800) { abort(); return }
        val t0 = SystemClock.uptimeMillis()
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                if (!main.isPlaying || main.currentMediaItemIndex != startedIndex) { abort(); return }
                val lin = ((SystemClock.uptimeMillis() - t0).toFloat() / total).coerceIn(0f, 1f)
                val x = lin * lin * (3f - 2f * lin) // smoothstep: soft start and finish, equal power between
                main.volume = cos(x * PI / 2).toFloat()
                a.volume = sin(x * PI / 2).toFloat()
                if (lin < 1f) handler.postDelayed(this, 40) else handoff(main, a, next, my)
            }
        })
    }

    private fun handoff(main: ExoPlayer, a: ExoPlayer, next: Int, my: Int) {
        // The aux player carries the sound while the main one loads the next item at (roughly) the same spot.
        main.seekTo(next, a.currentPosition + HANDOFF_LATENCY_MS)
        val t0 = SystemClock.uptimeMillis()
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                val ready = main.currentMediaItemIndex == next && main.playbackState == Player.STATE_READY && main.isPlaying
                when {
                    ready -> crossBack(main, a, my)
                    SystemClock.uptimeMillis() - t0 > 5000 -> finish(main)
                    else -> handler.postDelayed(this, 40)
                }
            }
        })
    }

    private fun crossBack(main: ExoPlayer, a: ExoPlayer, my: Int) {
        val t0 = SystemClock.uptimeMillis()
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                val x = ((SystemClock.uptimeMillis() - t0).toFloat() / BACK_MS).coerceIn(0f, 1f)
                main.volume = sin(x * PI / 2).toFloat()
                a.volume = cos(x * PI / 2).toFloat()
                if (x < 1f) handler.postDelayed(this, 30) else finish(main)
            }
        })
    }

    private fun finish(main: ExoPlayer) {
        token++
        main.volume = 1f
        releaseAux()
        fading = false
    }

    private fun abort() {
        token++
        engine?.player?.volume = 1f
        releaseAux()
        fading = false
    }

    private fun releaseAux() {
        try { aux?.release() } catch (_: Exception) {}
        aux = null
    }

    private companion object {
        const val HANDOFF_LATENCY_MS = 700L
        const val BACK_MS = 180f
    }
}
