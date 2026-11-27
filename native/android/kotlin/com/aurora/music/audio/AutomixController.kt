package com.aurora.music.audio

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.aurora.music.audio.analysis.TrackAnalysis
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Automix with a DJ's habits, mirroring the Dart planner used on the other platforms:
 *  - both songs are analysed ahead of time (tempo, bar grid, silence, loudness);
 *  - when the tempos are within 8% the next song is time-stretched to the playing one and started on one of
 *    its own bar lines, while the blend itself starts on a bar line (a 4-bar phrase when that is close) of
 *    the playing song, so the beats stay locked;
 *  - the tempo of the incoming song eases back to normal during the blend, its level is matched, and leading
 *    silence is skipped;
 *  - styles: 0 smooth, 1 club (incoming song enters early, outgoing leaves late), 2 quick cut (4 beats);
 *  - "Mix now" blends at the next bar line.
 * Songs without a usable analysis fall back to a smart equal-power crossfade.
 *
 * ExoPlayer cannot overlap two items, so a second player carries the next song during the blend; afterwards
 * the main player is moved onto it and a short reverse crossfade hands playback back, so the session,
 * notification and visualiser keep following one player. Everything runs on the main thread.
 */
@UnstableApi
class AutomixController(
    context: Context,
    private val scope: CoroutineScope,
    private val tempo: () -> Pair<Float, Float> = { 0f to 0f },
    private val analyze: suspend (mediaId: String, uri: String) -> TrackAnalysis? = { _, _ -> null },
) {
    private val prefs = context.getSharedPreferences("automix", Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())

    var enabled: Boolean = prefs.getBoolean("on", false)
        private set
    var seconds: Float = prefs.getFloat("sec", 8f)
        private set

    /** True: the blend length is chosen per song. False: always [seconds]. */
    var auto: Boolean = prefs.getBoolean("auto", true)
        private set

    /** False: plain crossfade of [seconds] only (the "Crossfade" mode). */
    var beatMix: Boolean = prefs.getBoolean("beat", true)
        private set

    /** 0 smooth, 1 club, 2 quick cut. */
    var dj: Int = prefs.getInt("dj", 1)
        private set

    /** Human-readable description of the blend in progress ("" when idle). */
    var info: String = ""
        private set
    var onChange: (() -> Unit)? = null

    private class Plan(
        val aId: String,
        val bId: String,
        val startMs: Long,
        val fadeMs: Long,
        val bSeekMs: Long,
        val bSpeed: Float,
        val bTrim: Float,
        val label: String,
    )

    private var plan: Plan? = null
    private var planning: String? = null
    private var attempted: String? = null
    private val known = HashMap<String, TrackAnalysis>()

    private var engine: BitChordAudioEngine? = null
    private var aux: ExoPlayer? = null
    private var fading = false
    private var arming = false
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
        plan = null
        planning = null
        attempted = null
        engine = e
        if (e != null) handler.post(poll)
    }

    fun set(enabled: Boolean, seconds: Float, auto: Boolean, beatMix: Boolean = true, dj: Int = this.dj) {
        this.enabled = enabled
        this.seconds = seconds.coerceIn(1f, 30f)
        this.auto = auto
        this.beatMix = beatMix
        this.dj = dj.coerceIn(0, 2)
        prefs.edit().putBoolean("on", this.enabled).putFloat("sec", this.seconds).putBoolean("auto", auto)
            .putBoolean("beat", beatMix).putInt("dj", this.dj).apply()
        plan = null
        planning = null
        if (!enabled) abort()
    }

    /** Starts blending into the next song at the next bar line of the playing one. */
    fun mixNow(): Boolean {
        val p = engine?.player ?: return false
        if (fading || arming || !p.isPlaying) return false
        val next = p.nextMediaItemIndex
        if (next == C.INDEX_UNSET) return false
        val dur = p.duration
        val pos = p.currentPosition
        if (dur == C.TIME_UNSET || dur - pos < 2500) return false
        val aItem = p.currentMediaItem ?: return false
        val bItem = p.getMediaItemAt(next)
        plan = buildNow(aItem, bItem, pos, dur)
        planning = aItem.mediaId + ">" + bItem.mediaId
        attempted = null
        return true
    }

    private fun tick() {
        val p = engine?.player ?: return
        if (!enabled || fading || arming || !p.isPlaying || p.repeatMode == Player.REPEAT_MODE_ONE) return
        val next = p.nextMediaItemIndex
        if (next == C.INDEX_UNSET) return
        val dur = p.duration
        if (dur == C.TIME_UNSET || dur <= 0) return
        val aItem = p.currentMediaItem ?: return
        val bItem = p.getMediaItemAt(next)
        val key = aItem.mediaId + ">" + bItem.mediaId
        val pos = p.currentPosition
        if (attempted == key) return

        val current = plan?.takeIf { it.aId == aItem.mediaId && it.bId == bItem.mediaId }
        if (current == null) {
            if (planning != key && pos > 2500) beginPlanning(key, aItem, bItem, dur)
            return
        }
        // Late (analysis finished after the ideal start): blend from here, unaligned, rather than skip it.
        val pl = if (current.startMs < pos - 300) late(current, pos, dur) ?: return else current
        if (pos >= pl.startMs - PREP_MS) {
            if (aux == null) prepareAux(p, next, pl)
            if (pos >= pl.startMs - ARM_MS) {
                attempted = key
                arming = true
                val my = ++token
                handler.post(armLoop(p, p.currentMediaItemIndex, next, pl, my, bItem))
            }
        }
    }

    // ---- Planning ------------------------------------------------------------------------------------

    private fun uriOf(item: MediaItem): String = item.localConfiguration?.uri?.toString().orEmpty()

    private fun beginPlanning(key: String, aItem: MediaItem, bItem: MediaItem, aDur: Long) {
        planning = key
        scope.launch {
            val a = withTimeoutOrNull(90_000) { analyze(aItem.mediaId, uriOf(aItem)) }
            val b = withTimeoutOrNull(90_000) { analyze(bItem.mediaId, uriOf(bItem)) }
            if (a != null) known[aItem.mediaId] = a
            if (b != null) known[bItem.mediaId] = b
            if (planning != key) return@launch
            val cur = engine?.player?.currentMediaItem?.mediaId
            if (cur != aItem.mediaId) return@launch
            val bDur = bItem.mediaMetadata.durationMs ?: b?.durationMs ?: 0L
            plan = build(aItem.mediaId, bItem.mediaId, aDur, bDur, a, b)
        }
    }

    private fun reliable(a: TrackAnalysis?): Boolean =
        a != null && a.beatSec > 0f && a.barSec > 0f && a.confidence > 0.4f && a.bpm in 60f..200f

    private fun trim(a: TrackAnalysis?, b: TrackAnalysis?): Float =
        if (a == null || b == null || a.loudness <= 0f || b.loudness <= 0f) 1f else (a.loudness / b.loudness).coerceIn(0.5f, 1f)

    private fun skip(b: TrackAnalysis?): Long = if (b != null && b.introMs > 600) max(0L, b.introMs - 150) else 0L

    private fun foldRatio(a: TrackAnalysis, b: TrackAnalysis): Float {
        var bBpm = b.bpm
        for (f in floatArrayOf(0.5f, 2f)) {
            if (abs(b.bpm * f - a.bpm) < abs(bBpm - a.bpm)) bBpm = b.bpm * f
        }
        return a.bpm / bBpm
    }

    private fun build(aId: String, bId: String, aDur: Long, bDur: Long, a: TrackAnalysis?, b: TrackAnalysis?): Plan? {
        val userLength = !auto || !beatMix
        val maxMs = if (!userLength) 30_000L else (seconds * 1000).toLong()
        val trim = trim(a, b)
        val skipB = skip(b)
        val endA = if (a != null && a.outroMs > 0) min(a.outroMs, aDur) else aDur

        fun cap(ms: Long): Long {
            val share = if (userLength) 0.45 else 0.25
            var f = min(ms, (aDur * share).toLong())
            if (bDur > 0) f = min(f, (bDur * share).toLong())
            return max(f, 1500L)
        }

        fun plain(): Plan {
            val fade = cap(if (!userLength) min(maxMs, 16_000L) else maxMs)
            return Plan(aId, bId, max(0L, endA - fade), fade, skipB, 1f, trim, "smart crossfade ${fade / 1000}s")
        }

        if (!beatMix) return plain()
        if (!reliable(a) || !reliable(b)) return plain()
        a!!
        b!!
        val ratio = foldRatio(a, b)
        if (abs(ratio - 1f) > 0.08f) return plain()

        val beatMs = a.beatSec * 1000.0
        val barMs = a.barSec * 1000.0
        val firstDown = a.downbeatSec * 1000.0
        var fade: Long
        if (userLength) {
            fade = cap(maxMs)
        } else {
            var beats = max(8, floor(maxMs / beatMs / 4).toInt() * 4)
            if (beats * beatMs > maxMs) beats -= 4
            fade = cap((max(beats, 4) * beatMs).toLong())
            // No key analysis here: keep a blend modest so two clashing keys never ring for half a minute.
            fade = if (dj == 2) cap((4 * beatMs).toLong()) else min(fade, cap(((if (dj == 0) 32 else 16) * beatMs).toLong()))
        }

        val target = endA - fade
        var k = floor((target - firstDown) / barMs).toLong()
        var start = firstDown + k * barMs
        while (start + fade > aDur - 250 && k > 0) {
            k--
            start = firstDown + k * barMs
        }
        var phrase = false
        val over = k % 4
        if (k >= 4 && over <= 2) {
            val cand = firstDown + (k - over) * barMs
            if (cand >= aDur * 0.35) {
                start = cand
                phrase = true
            }
        }
        if (start < aDur * 0.35) return plain()

        val bBar = b.barSec * 1000.0
        val bDown = b.downbeatSec * 1000.0
        var j = ceil((skipB - bDown) / bBar).toLong()
        if (j < 0) j = 0
        val bStart = bDown + j * bBar
        val style = when (dj) { 2 -> "quick cut"; 0 -> "smooth"; else -> "club" }
        val label = "$style beat-matched ×${"%.3f".format(ratio)}, ${"%.1f".format(fade / 1000.0)}s" + if (phrase) ", on the phrase" else ""
        return Plan(aId, bId, start.toLong(), fade, bStart.toLong(), ratio, trim, label)
    }

    private fun buildNow(aItem: MediaItem, bItem: MediaItem, pos: Long, dur: Long): Plan {
        val a = known[aItem.mediaId]
        val b = known[bItem.mediaId]
        val bDur = bItem.mediaMetadata.durationMs ?: b?.durationMs ?: 0L
        val trim = trim(a, b)
        val skipB = skip(b)
        if (reliable(a) && reliable(b)) {
            a!!
            b!!
            val ratio = foldRatio(a, b)
            if (abs(ratio - 1f) <= 0.08f) {
                val barMs = a.barSec * 1000.0
                val firstDown = a.downbeatSec * 1000.0
                val k = ceil((pos + 650 - firstDown) / barMs).toLong()
                val start = (firstDown + k * barMs).toLong()
                var fade = ((if (dj == 2) 4 else 8) * a.beatSec * 1000.0).toLong()
                fade = min(fade, ((dur - start) * 0.9).toLong())
                if (bDur > 0) fade = min(fade, (bDur * 0.45).toLong())
                if (fade >= 1500 && start + 1000 < dur) {
                    val bBar = b.barSec * 1000.0
                    val bDown = b.downbeatSec * 1000.0
                    var j = ceil((skipB - bDown) / bBar).toLong()
                    if (j < 0) j = 0
                    return Plan(aItem.mediaId, bItem.mediaId, start, fade, (bDown + j * bBar).toLong(), ratio, trim,
                        "mix now, beat-matched ×${"%.3f".format(ratio)}, ${"%.1f".format(fade / 1000.0)}s")
                }
            }
        }
        val fade = min(6000L, ((dur - pos) * 0.7).toLong())
        return Plan(aItem.mediaId, bItem.mediaId, pos + 900, fade, skipB, 1f, trim, "mix now, ${fade / 1000}s")
    }

    private fun late(p: Plan, pos: Long, dur: Long): Plan? {
        val start = pos + 900
        val fade = min(p.fadeMs, ((dur - start) * 0.8).toLong())
        if (fade < 1500) return null
        return Plan(p.aId, p.bId, start, fade, p.bSeekMs, 1f, p.bTrim, "crossfade ${fade / 1000}s")
    }

    // ---- Running a blend -----------------------------------------------------------------------------

    private fun prepareAux(main: ExoPlayer, next: Int, pl: Plan) {
        val e = engine ?: return
        val a = e.createAuxPlayer()
        aux = a
        a.volume = 0f
        a.playbackParameters = PlaybackParameters(pl.bSpeed.coerceIn(0.5f, 2f), 1f)
        a.setMediaItem(main.getMediaItemAt(next), pl.bSeekMs)
        a.prepare()
        a.playWhenReady = false
    }

    /** Waits (polling finely) for the exact moment, so the incoming downbeat lands on the outgoing bar line. */
    private fun armLoop(main: ExoPlayer, startedIndex: Int, next: Int, pl: Plan, my: Int, bItem: MediaItem) = object : Runnable {
        override fun run() {
            if (my != token) return
            if (!main.isPlaying || main.currentMediaItemIndex != startedIndex) { abort(); return }
            if (aux == null) prepareAux(main, next, pl)
            val a = aux ?: run { abort(); return }
            val pos = main.currentPosition
            if (pos < pl.startMs - AUX_LATENCY_MS) {
                handler.postDelayed(this, 8)
            } else if (a.playbackState == Player.STATE_READY) {
                go(main, a, next, startedIndex, pl, my, bItem)
            } else if (pos > pl.startMs + 2500) {
                abort()
            } else {
                handler.postDelayed(this, 10)
            }
        }
    }

    private fun go(main: ExoPlayer, a: ExoPlayer, next: Int, startedIndex: Int, pl: Plan, my: Int, bItem: MediaItem) {
        arming = false
        fading = true
        a.playWhenReady = true
        info = "Mixing into ${bItem.mediaMetadata.title ?: "next song"} · ${pl.label}"
        onChange?.invoke()
        val t0 = SystemClock.uptimeMillis()
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                when {
                    a.isPlaying -> ramp(main, a, next, startedIndex, pl, my)
                    SystemClock.uptimeMillis() - t0 > 6000 || !main.isPlaying -> abort()
                    else -> handler.postDelayed(this, 20)
                }
            }
        })
    }

    private fun smooth(x: Float): Float {
        val l = x.coerceIn(0f, 1f)
        return l * l * (3f - 2f * l)
    }

    private fun ramp(main: ExoPlayer, a: ExoPlayer, next: Int, startedIndex: Int, pl: Plan, my: Int) {
        val remaining = main.duration - main.currentPosition
        val total = min(pl.fadeMs, remaining - 400)
        if (total < 800) { abort(); return }
        val t0 = SystemClock.uptimeMillis()
        var lastSpeedAt = 0L
        var lastSpeed = pl.bSpeed
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                if (!main.isPlaying || main.currentMediaItemIndex != startedIndex) { abort(); return }
                val now = SystemClock.uptimeMillis()
                val lin = ((now - t0).toFloat() / total).coerceIn(0f, 1f)
                val xA: Float
                val xB: Float
                when (dj) {
                    2 -> { val c = smooth((lin - 0.3f) / 0.4f); xA = c; xB = c }
                    1 -> { xB = smooth(lin * 1.25f); xA = smooth((lin - 0.2f) / 0.8f) }
                    else -> { val s = smooth(lin); xA = s; xB = s }
                }
                main.volume = cos(xA * PI / 2).toFloat()
                a.volume = (sin(xB * PI / 2) * (pl.bTrim + (1f - pl.bTrim) * xB)).toFloat()
                if (pl.bSpeed != 1f && now - lastSpeedAt >= 120) {
                    lastSpeedAt = now
                    val spd = pl.bSpeed + (1f - pl.bSpeed) * lin * lin
                    if (abs(spd - lastSpeed) > 0.002f) {
                        lastSpeed = spd
                        a.playbackParameters = PlaybackParameters(spd, 1f)
                    }
                }
                if (lin < 1f) handler.postDelayed(this, 30) else handoff(main, a, next, my)
            }
        })
    }

    private fun handoff(main: ExoPlayer, a: ExoPlayer, next: Int, my: Int) {
        a.playbackParameters = PlaybackParameters(1f, 1f)
        main.seekTo(next, a.currentPosition + HANDOFF_LATENCY_MS)
        val t0 = SystemClock.uptimeMillis()
        handler.post(object : Runnable {
            override fun run() {
                if (my != token) return
                val ready = main.currentMediaItemIndex == next && main.playbackState == Player.STATE_READY && main.isPlaying
                when {
                    ready -> crossBack(main, a, my)
                    SystemClock.uptimeMillis() - t0 > 5000 -> finish(main)
                    else -> handler.postDelayed(this, 30)
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
                if (x < 1f) handler.postDelayed(this, 25) else finish(main)
            }
        })
    }

    private fun finish(main: ExoPlayer) {
        token++
        main.volume = 1f
        releaseAux()
        fading = false
        arming = false
        plan = null
        planning = null
        attempted = null
        clearInfo()
    }

    private fun abort() {
        token++
        engine?.player?.volume = 1f
        releaseAux()
        fading = false
        arming = false
        clearInfo()
    }

    private fun clearInfo() {
        if (info.isNotEmpty()) {
            info = ""
            onChange?.invoke()
        }
    }

    private fun releaseAux() {
        try { aux?.release() } catch (_: Exception) {}
        aux = null
    }

    private companion object {
        const val PREP_MS = 14_000L
        const val ARM_MS = 1_500L
        const val AUX_LATENCY_MS = 70L
        const val HANDOFF_LATENCY_MS = 700L
        const val BACK_MS = 180f
    }
}
