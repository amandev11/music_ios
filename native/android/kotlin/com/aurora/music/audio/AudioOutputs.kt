package com.aurora.music.audio

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.provider.Settings
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

/** Lists the audio outputs Android reports (speaker, wired, Bluetooth, USB...) and pins playback to one. */
@UnstableApi
class AudioOutputs(private val context: Context) {
    private val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val prefs = context.getSharedPreferences("audio_output", Context.MODE_PRIVATE)

    private fun label(d: AudioDeviceInfo): String {
        val kind = when (d.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB audio"
            AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI"
            AudioDeviceInfo.TYPE_HEARING_AID -> "Hearing aid"
            AudioDeviceInfo.TYPE_DOCK -> "Dock"
            26, 27 -> "Bluetooth LE"
            else -> "Audio output"
        }
        val name = d.productName?.toString().orEmpty()
        return if (name.isBlank() || d.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER || name == Build_MODEL) kind else "$kind · $name"
    }

    private fun usable(d: AudioDeviceInfo): Boolean = d.isSink && when (d.type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_DOCK,
        26, 27 -> true
        else -> false
    }

    fun list(): List<Map<String, Any>> =
        am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter(::usable).map {
            mapOf("id" to it.id.toString(), "name" to label(it))
        }

    fun selected(): String = prefs.getString("id", "auto") ?: "auto"

    fun select(player: ExoPlayer?, id: String): Boolean {
        prefs.edit().putString("id", id).apply()
        return apply(player, id)
    }

    /** Re-applies the saved choice (the player is recreated now and then). */
    fun reapply(player: ExoPlayer?) { apply(player, selected()) }

    private fun apply(player: ExoPlayer?, id: String): Boolean {
        player ?: return false
        return try {
            if (id == "auto") {
                player.setPreferredAudioDevice(null)
                true
            } else {
                val dev = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.id.toString() == id }
                if (dev == null) {
                    // The chosen device is gone (unplugged): fall back to the system's pick.
                    player.setPreferredAudioDevice(null)
                    false
                } else {
                    player.setPreferredAudioDevice(dev)
                    true
                }
            }
        } catch (_: Throwable) {
            false
        }
    }

    /** The system media-output switcher (Bluetooth, cast...), or the Bluetooth settings page as a fallback. */
    fun openSystemSwitcher(): Boolean {
        val attempts = listOf(
            Intent("com.android.settings.panel.action.MEDIA_OUTPUT")
                .putExtra("com.android.settings.panel.extra.PACKAGE_NAME", context.packageName),
            Intent(Settings.ACTION_BLUETOOTH_SETTINGS),
        )
        for (i in attempts) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(i)
                return true
            } catch (_: Throwable) {
            }
        }
        return false
    }

    private companion object {
        val Build_MODEL: String = android.os.Build.MODEL
    }
}
