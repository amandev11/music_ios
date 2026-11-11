package com.aurora.music

import android.app.Application
import androidx.media3.common.util.UnstableApi
import com.aurora.music.audio.EngineRegistry
import com.aurora.music.audio.SpatialAudio
import com.aurora.music.audio.analysis.AudioFeatureHub
import com.aurora.music.data.LibraryRepository
import com.aurora.music.data.sources.SourceRegistry
import com.aurora.music.data.sources.jiosaavn.JioSaavnSource
import com.aurora.music.data.sources.youtube.YouTubeMusicSource
import com.aurora.music.playback.PlayerController
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

class MusicApp : Application() {
    val graph: AppGraph by lazy { AppGraph(this) }
}

@UnstableApi
class AppGraph(app: Application) {
    // A failure in one background job must never take the process down.
    private val guard = CoroutineExceptionHandler { _, e -> Log.e("Aurora", "background job failed", e) }
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default + guard)
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + guard)
    private val http = OkHttpClient.Builder().retryOnConnectionFailure(true).build()

    val sources = SourceRegistry(listOf(JioSaavnSource(http), YouTubeMusicSource(http)))
    val library = LibraryRepository(app, appScope, sources)
    val player = PlayerController(app)
    val features = AudioFeatureHub(app, appScope).also { it.start() }
    val spatial = SpatialAudio(app)

    init {
        // ExoPlayer may only be touched on its application thread (main). Applying spatial audio from
        // Dispatchers.Default threw "Player is accessed on the wrong thread" on every launch.
        mainScope.launch {
            EngineRegistry.engine.collect { e ->
                if (e != null) runCatching { spatial.apply(e) }
                    .onFailure { Log.w("Aurora", "spatial audio unavailable", it) }
            }
        }
    }
}
