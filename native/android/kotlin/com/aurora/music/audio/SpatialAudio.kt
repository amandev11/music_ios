package com.aurora.music.audio

import android.content.Context
import android.media.AudioManager
import android.os.Build
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Spatial audio preference. The platform spatialiser (Android 12L+) does the rendering when the output
 * device supports it (headphones with head tracking, a Dolby/DTS-capable route); this only opts the
 * player in or out via its audio attributes.
 */
@UnstableApi
class SpatialAudio(context: Context) {
    private val prefs = context.getSharedPreferences("aurora_audio", Context.MODE_PRIVATE)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val _enabled = MutableStateFlow(prefs.getBoolean(KEY, true))
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    /** True when the current output route can be spatialised right now. */
    fun isAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 32 && runCatching {
            val s = audioManager.spatializer
            s.isAvailable && s.isEnabled
        }.getOrDefault(false)

    fun toggle(engine: BitChordAudioEngine?) {
        val next = !_enabled.value
        _enabled.value = next
        prefs.edit().putBoolean(KEY, next).apply()
        engine?.setSpatialAudio(next)
    }

    fun apply(engine: BitChordAudioEngine) = engine.setSpatialAudio(_enabled.value)

    private companion object {
        const val KEY = "spatial_enabled"
    }
}
