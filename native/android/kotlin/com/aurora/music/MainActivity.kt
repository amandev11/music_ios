package com.aurora.music

import android.Manifest
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.media3.common.util.UnstableApi
import com.aurora.music.bridge.NativeBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

@UnstableApi
class MainActivity : FlutterActivity() {

    private var bridge: NativeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Plugins are registered by super; never let a native-engine failure kill the launch.
        try {
            val graph = (application as MusicApp).graph
            bridge = NativeBridge(applicationContext, graph, flutterEngine.dartExecutor.binaryMessenger) { requestAudioPermissions() }
        } catch (t: Throwable) {
            android.util.Log.e("Aurora", "native bridge failed to start", t)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.dispose()
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun requestAudioPermissions() {
        val perms = if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        ActivityCompat.requestPermissions(this, perms, 4711)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) runCatching { (application as MusicApp).graph.library.refresh() }
    }
}
