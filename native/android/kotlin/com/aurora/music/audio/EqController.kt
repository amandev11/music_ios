package com.aurora.music.audio

import android.media.audiofx.Equalizer
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import kotlin.math.ln
import kotlin.math.roundToInt

/**
 * System equalizer attached to the player's audio session. Flutter edits a fixed 10-band curve in dB;
 * it is interpolated (log-frequency) onto whatever bands the device's Equalizer exposes. The session id
 * changes when ExoPlayer recreates its AudioTrack, so the effect is rebuilt on every change.
 */
@UnstableApi
class EqController {
    private var equalizer: Equalizer? = null
    private var player: ExoPlayer? = null
    private var enabled = false
    private var gains = DoubleArray(FREQS.size)

    private val listener = object : Player.Listener {
        override fun onAudioSessionIdChanged(audioSessionId: Int) = rebuild(audioSessionId)
    }

    fun attach(p: ExoPlayer?) {
        player?.removeListener(listener)
        release()
        player = p
        p?.addListener(listener)
        if (p != null) rebuild(p.audioSessionId)
    }

    fun set(enabled: Boolean, gains: List<Double>) {
        this.enabled = enabled
        this.gains = DoubleArray(FREQS.size) { gains.getOrElse(it) { 0.0 } }
        apply()
    }

    fun info(): Map<String, Any?> {
        val e = equalizer
        return mapOf(
            "supported" to (e != null),
            "bands" to (e?.numberOfBands?.toInt() ?: 0),
        )
    }

    private fun rebuild(session: Int) {
        release()
        if (session == C.AUDIO_SESSION_ID_UNSET || session == 0) return
        equalizer = try { Equalizer(0, session) } catch (_: Exception) { null }
        apply()
    }

    private fun apply() {
        val e = equalizer ?: return
        try {
            e.setEnabled(enabled)
            val range = e.bandLevelRange
            val lo = range[0].toInt()
            val hi = range[1].toInt()
            for (band in 0 until e.numberOfBands) {
                val hz = e.getCenterFreq(band.toShort()) / 1000.0
                val millibels = (interpolate(hz) * 100).roundToInt().coerceIn(lo, hi)
                e.setBandLevel(band.toShort(), millibels.toShort())
            }
        } catch (_: Exception) {
        }
    }

    private fun interpolate(hz: Double): Double {
        if (hz <= FREQS.first()) return gains.first()
        if (hz >= FREQS.last()) return gains.last()
        for (i in 0 until FREQS.size - 1) {
            if (hz <= FREQS[i + 1]) {
                val t = (ln(hz) - ln(FREQS[i])) / (ln(FREQS[i + 1]) - ln(FREQS[i]))
                return gains[i] + (gains[i + 1] - gains[i]) * t
            }
        }
        return 0.0
    }

    private fun release() {
        try { equalizer?.release() } catch (_: Exception) {}
        equalizer = null
    }

    private companion object {
        val FREQS = doubleArrayOf(31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0)
    }
}
