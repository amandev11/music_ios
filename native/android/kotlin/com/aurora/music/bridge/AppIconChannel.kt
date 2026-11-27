package com.aurora.music.bridge

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Switches the launcher icon (and optionally the launcher label) by enabling exactly one of the
 * activity-alias entries that tool_setup.py writes into the manifest:
 *   Icon_<id>  - icon only, label stays "Keystone"
 *   IconN_<id> - icon plus its own name as the label
 */
class AppIconChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "aurora/appicon")
    private val pm get() = context.packageManager
    private val pkg get() = context.packageName

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ids" -> result.success(aliases().map { it.className.removePrefix("com.aurora.music.") })
                    "set" -> {
                        val id = call.argument<String>("id") ?: "keycapkeystone"
                        val named = call.argument<Boolean>("named") ?: false
                        result.success(apply(id, named))
                    }
                    "current" -> result.success(current())
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("icon", t.message, null)
            }
        }
    }

    private fun aliases(): List<ComponentName> {
        val info = pm.getPackageInfo(pkg, PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS)
        return info.activities.orEmpty()
            .map { it.name }
            .filter { it.startsWith("com.aurora.music.Icon_") || it.startsWith("com.aurora.music.IconN_") }
            .map { ComponentName(pkg, it) }
    }

    private fun apply(id: String, named: Boolean): Boolean {
        val wanted = "com.aurora.music." + (if (named) "IconN_" else "Icon_") + id
        val all = aliases()
        if (all.none { it.className == wanted }) return false
        // Enable the new one first so the launcher never has zero entries.
        pm.setComponentEnabledSetting(ComponentName(pkg, wanted), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        for (c in all) {
            if (c.className != wanted) {
                pm.setComponentEnabledSetting(c, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
        }
        return true
    }

    private fun current(): Map<String, Any> {
        for (c in aliases()) {
            val state = pm.getComponentEnabledSetting(c)
            val enabled = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            if (enabled) {
                val n = c.className.removePrefix("com.aurora.music.")
                return mapOf("id" to n.substringAfter('_'), "named" to n.startsWith("IconN_"))
            }
        }
        return mapOf("id" to "keycapkeystone", "named" to false)
    }
}
