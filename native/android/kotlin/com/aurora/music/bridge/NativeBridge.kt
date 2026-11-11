package com.aurora.music.bridge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Size
import androidx.media3.common.util.UnstableApi
import com.aurora.music.AppGraph
import com.aurora.music.audio.AutomixController
import com.aurora.music.audio.EngineRegistry
import com.aurora.music.audio.EqController
import com.aurora.music.audio.OutputProtector
import com.aurora.music.audio.analysis.BeatPulse
import com.aurora.music.model.Album
import com.aurora.music.model.LibraryState
import com.aurora.music.model.PlaybackSnapshot
import com.aurora.music.model.Progress
import com.aurora.music.model.QueueItem
import com.aurora.music.model.RepeatMode
import com.aurora.music.model.SourceType
import com.aurora.music.model.Track
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * Exposes the native Media3 + ONNX engine to Flutter. State is pushed on event channels; everything
 * else is request/response on [METHODS]. Track maps carry every [Track] field so Flutter can hand
 * them straight back into playback calls.
 */
@UnstableApi
class NativeBridge(
    private val context: Context,
    private val graph: AppGraph,
    messenger: BinaryMessenger,
    private val requestPermission: () -> Unit,
) {
    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main.immediate +
            CoroutineExceptionHandler { _, e -> Log.e("Aurora", "bridge job failed", e) },
    )
    private val methods = MethodChannel(messenger, METHODS)

    private val library = Sink()
    private val snapshot = Sink()
    private val progress = Sink()
    private val frame = Sink()
    private val errors = Sink()
    private val eq = EqController()
    private val protector = OutputProtector()
    private val automix = AutomixController(context) { graph.features.clock.bpm to graph.features.clock.confidence }

    private var frameJob: Job? = null

    init {
        EventChannel(messenger, "aurora/library").setStreamHandler(library.handler())
        EventChannel(messenger, "aurora/snapshot").setStreamHandler(snapshot.handler { pushSnapshot(graph.player.snapshot.value) })
        EventChannel(messenger, "aurora/progress").setStreamHandler(progress.handler())
        EventChannel(messenger, "aurora/errors").setStreamHandler(errors.handler())
        EventChannel(messenger, "aurora/frame").setStreamHandler(frame.handler { ensureFrameLoop() })

        methods.setMethodCallHandler(::onCall)
        graph.player.connect()

        scope.launch {
            combine(graph.library.state, graph.library.tracks, graph.library.albums) { s, t, a -> Triple(s, t, a) }
                .collect { (s, t, a) ->
                    library.send(mapOf(
                        "state" to s.name,
                        "tracks" to t.map { it.toMap() },
                        "albums" to a.map { it.toMap() },
                    ))
                }
        }
        scope.launch { graph.player.snapshot.collect(::pushSnapshot) }
        scope.launch { graph.player.errors.collect { errors.send(it) } }
        scope.launch {
            EngineRegistry.engine.collect { e ->
                eq.attach(e?.player)
                protector.attach(e?.player)
                automix.attach(e)
            }
        }
        scope.launch { graph.player.progress.collect { progress.send(listOf(it.positionMs, it.durationMs, it.bufferedMs)) } }
        scope.launch { graph.library.ensureLoaded() }
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        frameJob?.cancel()
        scope.cancel()
    }

    // ---- Requests ------------------------------------------------------------------------------

    @Suppress("UNCHECKED_CAST")
    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        val p = player()
        fun tracks(key: String) = (call.argument<List<Map<String, Any?>>>(key) ?: emptyList()).map { it.toTrack() }
        try {
            when (call.method) {
                "requestPermission" -> { requestPermission(); result.success(null) }
                "refresh" -> { graph.library.refresh(); result.success(null) }
                "play" -> {
                    p.playTracks(tracks("tracks"), call.argument<Int>("index") ?: 0, call.argument<Boolean>("shuffle") ?: false)
                    result.success(null)
                }
                "toggle" -> { p.togglePlayPause(); result.success(null) }
                "next" -> { p.next(); result.success(null) }
                "previous" -> { p.previous(); result.success(null) }
                "seek" -> { p.seekTo((call.argument<Number>("ms") ?: 0).toLong()); result.success(null) }
                "skipTo" -> { p.skipTo(call.argument<Int>("index") ?: 0); result.success(null) }
                "move" -> { p.moveQueueItem(call.argument<Int>("from") ?: 0, call.argument<Int>("to") ?: 0); result.success(null) }
                "remove" -> { p.removeQueueItem(call.argument<Int>("index") ?: 0); result.success(null) }
                "playNext" -> { tracks("tracks").firstOrNull()?.let(p::playNext); result.success(null) }
                "addToQueue" -> { tracks("tracks").firstOrNull()?.let(p::addToQueue); result.success(null) }
                "setShuffle" -> { p.setShuffle(call.argument<Boolean>("on") ?: false); result.success(null) }
                "cycleRepeat" -> { p.cycleRepeat(); result.success(null) }
                "setSpeed" -> { p.setSpeed((call.argument<Double>("speed") ?: 1.0).toFloat()); result.success(null) }

                "searchLocal" -> reply(result, emptyList<Any>()) { graph.library.searchLocal(call.argument<String>("q").orEmpty()).map { it.toMap() } }
                "searchRemote" -> reply(result, emptyList<Any>()) { graph.library.searchRemote(call.argument<String>("q").orEmpty()).map { it.toMap() } }
                "albumTracks" -> reply(result, emptyList<Any>()) {
                    graph.library.tracksForAlbum((call.argument<Number>("albumId") ?: 0).toLong()).map { it.toMap() }
                }

                "protectSet" -> {
                    protector.set(call.argument<Boolean>("on") ?: true)
                    result.success(null)
                }
                "eqInfo" -> result.success(eq.info())
                "eqSet" -> {
                    eq.set(call.argument<Boolean>("enabled") ?: false, call.argument<List<Double>>("gains") ?: emptyList())
                    result.success(null)
                }
                "volume" -> { p.setVolume((call.argument<Double>("value") ?: 1.0).toFloat()); result.success(null) }
                "automixSet" -> {
                    automix.set(
                        call.argument<Boolean>("enabled") ?: false,
                        (call.argument<Number>("seconds") ?: 8.0).toFloat(),
                        call.argument<Boolean>("auto") ?: true,
                    )
                    pushSnapshot(graph.player.snapshot.value)
                    result.success(null)
                }
                "spatialAvailable" -> result.success(graph.spatial.isAvailable())
                "spatialEnabled" -> result.success(graph.spatial.enabled.value)
                "toggleSpatial" -> {
                    graph.spatial.toggle(EngineRegistry.engine.value)
                    result.success(graph.spatial.enabled.value)
                }
                "tempo" -> result.success(mapOf(
                    "bpm" to graph.features.clock.bpm.toDouble(),
                    "confidence" to graph.features.clock.confidence.toDouble(),
                ))
                "analyze" -> scope.launch {
                    val id = call.argument<String>("mediaId").orEmpty()
                    val uri = call.argument<String>("uri").orEmpty()
                    val a = runCatching { graph.features.analysisFor(id, uri) }.getOrNull()
                    result.success(a?.let {
                        mapOf(
                            "bpm" to it.bpm.toDouble(),
                            "confidence" to it.confidence.toDouble(),
                            "firstBeatSec" to it.firstBeatSec.toDouble(),
                            "waveform" to it.waveform.map { v -> v.toDouble() },
                        )
                    })
                }
                "artwork" -> scope.launch {
                    val bytes = withContext(Dispatchers.IO) {
                        runCatching { loadArtwork(call.argument<String>("uri").orEmpty(), call.argument<Int>("px") ?: 512) }.getOrNull()
                    }
                    result.success(bytes)
                }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            Log.w("Aurora", "method ${call.method} failed", e)
            try { result.error("native", e.message, null) } catch (_: Throwable) {}
        }
    }

    private fun player() = graph.player

    /** Runs [block] off the call stack and always answers [result] exactly once, even on failure. */
    private fun reply(result: MethodChannel.Result, fallback: Any?, block: suspend () -> Any?) {
        scope.launch {
            val value = try { block() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
                Log.w("Aurora", "call failed", e); fallback
            }
            try { result.success(value) } catch (_: Throwable) {}
        }
    }

    // ---- Push streams --------------------------------------------------------------------------

    private fun pushSnapshot(s: PlaybackSnapshot) {
        snapshot.send(mapOf(
            "isPlaying" to s.isPlaying,
            "isBuffering" to s.isBuffering,
            "currentIndex" to s.currentIndex,
            "shuffle" to s.shuffle,
            "repeat" to when (s.repeat) { RepeatMode.OFF -> 0; RepeatMode.ALL -> 1; RepeatMode.ONE -> 2 },
            "speed" to s.speed.toDouble(),
            "hasNext" to s.hasNext,
            "hasPrevious" to s.hasPrevious,
            "automix" to automix.enabled,
            "queue" to s.queue.map { it.toMap() },
        ))
    }

    /**
     * 60 Hz audio frame while Flutter listens and something is playing:
     * [envelope, beatInBar, beatsPerBar, bpm, confidence, rms, spectrum x32].
     */
    private fun ensureFrameLoop() {
        if (frameJob?.isActive == true) return
        frameJob = scope.launch {
            var last: Progress? = null
            var sampleNanos = 0L
            val spectrum = FloatArray(32)
            val out = DoubleArray(6 + 32)
            while (isActive) {
                val snap = graph.player.snapshot.value
                if (!frame.active) break
                val now = System.nanoTime()
                val p = graph.player.progress.value
                if (p !== last) { last = p; sampleNanos = now }
                val elapsed = if (snap.isPlaying) ((now - sampleNanos) / 1_000_000.0 * snap.speed).toLong() else 0L
                val position = (p.positionMs + elapsed).coerceAtLeast(0L)

                val hub = graph.features
                val pulse: BeatPulse = if (snap.isPlaying) hub.clock.pulseAt(position) else BeatPulse()
                val rms = hub.spectrum.value?.sample(position, hub.currentOriginMs(), spectrum) ?: 0f
                out[0] = pulse.envelope.toDouble()
                out[1] = pulse.beatInBar.toDouble()
                out[2] = pulse.beatsPerBar.toDouble()
                out[3] = pulse.bpm.toDouble()
                out[4] = pulse.confidence.toDouble()
                out[5] = rms.toDouble()
                for (i in 0 until 32) out[6 + i] = spectrum[i].toDouble()
                frame.send(out.copyOf())
                delay(if (snap.isPlaying) 16 else 100)
            }
        }
    }

    // ---- Artwork -------------------------------------------------------------------------------

    private fun loadArtwork(uri: String, px: Int): ByteArray? {
        val parsed = Uri.parse(uri)
        val bmp: Bitmap = (if (Build.VERSION.SDK_INT >= 29) {
            runCatching { context.contentResolver.loadThumbnail(parsed, Size(px, px), null) }.getOrNull()
        } else null) ?: decodeStream(parsed, px) ?: return null
        return ByteArrayOutputStream().use {
            bmp.compress(Bitmap.CompressFormat.JPEG, 90, it)
            it.toByteArray()
        }
    }

    private fun decodeStream(uri: Uri, px: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= px && bounds.outHeight / (sample * 2) >= px) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
    }

    // ---- Event sink plumbing -------------------------------------------------------------------

    private class Sink {
        private var sink: EventChannel.EventSink? = null
        val active get() = sink != null

        fun send(value: Any?) { try { sink?.success(value) } catch (_: Throwable) { sink = null } }

        fun handler(onListen: () -> Unit = {}) = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                onListen()
            }
            override fun onCancel(arguments: Any?) { sink = null }
        }
    }

    private companion object {
        const val METHODS = "aurora/native"
    }
}

// ---- Map codecs --------------------------------------------------------------------------------

internal fun Track.toMap(): Map<String, Any?> = mapOf(
    "mediaId" to mediaId, "title" to title, "artist" to artist, "albumArtist" to albumArtist,
    "album" to album, "albumId" to albumId, "durationMs" to durationMs, "trackNumber" to trackNumber,
    "discNumber" to discNumber, "year" to year, "uri" to uri, "artworkUri" to artworkUri,
    "mimeType" to mimeType, "dateAddedSec" to dateAddedSec,
    "remote" to (source == SourceType.NETWORK),
)

internal fun Album.toMap(): Map<String, Any?> = mapOf(
    "id" to id, "title" to title, "artist" to artist, "artworkUri" to artworkUri,
    "year" to year, "trackCount" to trackCount,
)

internal fun QueueItem.toMap(): Map<String, Any?> = mapOf(
    "index" to index, "mediaId" to mediaId, "title" to title, "artist" to artist, "album" to album,
    "artworkUri" to artworkUri, "durationMs" to durationMs,
)

internal fun Map<String, Any?>.toTrack(): Track {
    val id = this["mediaId"] as String
    val remote = com.aurora.music.data.sources.TrackKeys.isRemote(id)
    // Queue snapshots (and so "recently played") carry no uri: rebuild it from the media id.
    val given = this["uri"] as? String
    val rebuilt = when {
        !given.isNullOrEmpty() -> given
        remote -> com.aurora.music.data.sources.TrackKeys.streamUri(id)
        else -> id.removePrefix("local:").toLongOrNull()
            ?.let { android.content.ContentUris.withAppendedId(android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, it).toString() }
            ?: ""
    }
    return toTrackWith(rebuilt, remote)
}

private fun Map<String, Any?>.toTrackWith(resolvedUri: String, remote: Boolean): Track = Track(
    mediaId = this["mediaId"] as String,
    title = this["title"] as? String ?: "",
    artist = this["artist"] as? String ?: "",
    albumArtist = this["albumArtist"] as? String,
    album = this["album"] as? String ?: "",
    albumId = (this["albumId"] as? Number)?.toLong() ?: 0L,
    durationMs = (this["durationMs"] as? Number)?.toLong() ?: 0L,
    trackNumber = (this["trackNumber"] as? Number)?.toInt() ?: 0,
    discNumber = (this["discNumber"] as? Number)?.toInt() ?: 0,
    year = (this["year"] as? Number)?.toInt() ?: 0,
    uri = resolvedUri,
    artworkUri = this["artworkUri"] as? String,
    mimeType = this["mimeType"] as? String,
    dateAddedSec = (this["dateAddedSec"] as? Number)?.toLong() ?: 0L,
    source = if (remote) SourceType.NETWORK else SourceType.LOCAL,
)
