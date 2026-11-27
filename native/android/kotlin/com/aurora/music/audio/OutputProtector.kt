package com.aurora.music.audio

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

/**
 * Speaker protection on the player's audio session: a sub-bass cut (below ~30 Hz nothing is audible but it
 * overloads woofers and receiver protection circuits), a fast peak limiter at -3 dBFS so loud masters, EQ
 * boosts or spatial gain never clip, which is what trips a speaker or home-theatre amp at high volume.
 * Needs Android 9+ (DynamicsProcessing); silently does nothing on older versions. Rebuilt whenever ExoPlayer
 * recreates its AudioTrack (the session id changes).
 */
@UnstableApi
class OutputProtector {
    private var dp: DynamicsProcessing? = null
    private var player: ExoPlayer? = null
    private var enabled = true

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

    fun set(on: Boolean) {
        enabled = on
        try { dp?.enabled = on } catch (_: Throwable) {}
    }

    private fun rebuild(session: Int) {
        release()
        if (Build.VERSION.SDK_INT < 28 || session == C.AUDIO_SESSION_ID_UNSET || session == 0) return
        try {
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                2,      // channels
                true, 2, // pre-EQ with two bands: sub-bass cut + everything above
                false, 0,
                false, 0,
                true,   // limiter
            ).build()
            val d = DynamicsProcessing(0, session, config)
            d.setPreEqBandAllChannelsTo(0, DynamicsProcessing.EqBand(true, 30f, -12f))
            d.setPreEqBandAllChannelsTo(1, DynamicsProcessing.EqBand(true, 22000f, 0f))
            d.setLimiterAllChannelsTo(DynamicsProcessing.Limiter(true, true, 0, 1f, 80f, 20f, -6f, -2f))
            d.enabled = enabled
            dp = d
        } catch (t: Throwable) {
            Log.w("Aurora", "output protection unavailable", t)
            dp = null
        }
    }

    private fun release() {
        try { dp?.release() } catch (_: Throwable) {}
        dp = null
    }
}
