package com.aurora.music.playback

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.aurora.music.model.PlaybackSnapshot
import com.aurora.music.model.Progress
import com.aurora.music.model.RepeatMode
import com.aurora.music.model.Track
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@UnstableApi
class PlayerController(private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var controller: MediaController? = null
    private var connectJob: Job? = null
    private var tickJob: Job? = null

    private val _snapshot = MutableStateFlow(PlaybackSnapshot())
    val snapshot: StateFlow<PlaybackSnapshot> = _snapshot.asStateFlow()

    private val _progress = MutableStateFlow(Progress())
    val progress: StateFlow<Progress> = _progress.asStateFlow()

    private val _errors = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val errors: SharedFlow<String> = _errors.asSharedFlow()

    private val listener = object : Player.Listener {
        override fun onPlayerError(error: PlaybackException) {
            _errors.tryEmit(error.cause?.message ?: error.message ?: error.errorCodeName)
        }

        override fun onEvents(player: Player, events: Player.Events) {
            sync(player, rebuildQueue = events.contains(Player.EVENT_TIMELINE_CHANGED))
            updateTicker(player)
        }
    }

    fun connect() {
        if (controller != null || connectJob?.isActive == true) return
        connectJob = scope.launch {
            try {
                val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
                val c = MediaController.Builder(context, token).buildAsync().await()
                controller = c
                c.addListener(listener)
                sync(c, rebuildQueue = true)
                updateTicker(c)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                controller = null
            }
        }
    }

    fun release() {
        tickJob?.cancel()
        connectJob?.cancel()
        controller?.run {
            removeListener(listener)
            release()
        }
        controller = null
    }

    fun playTracks(tracks: List<Track>, startIndex: Int = 0, shuffle: Boolean = false) {
        val c = controller ?: return
        if (tracks.isEmpty()) return
        c.shuffleModeEnabled = shuffle
        c.setMediaItems(tracks.map { it.toMediaItem() }, startIndex.coerceIn(0, tracks.lastIndex), C.TIME_UNSET)
        c.prepare()
        c.play()
    }

    fun play() { controller?.play() }
    fun pause() { controller?.pause() }

    fun togglePlayPause() {
        val c = controller ?: return
        if (c.isPlaying) c.pause() else {
            if (c.playbackState == Player.STATE_IDLE) c.prepare()
            c.play()
        }
    }

    fun seekTo(positionMs: Long) {
        val c = controller ?: return
        c.seekTo(positionMs.coerceAtLeast(0L))
        pushProgress(c)
    }

    fun next() { controller?.seekToNext() }
    fun previous() { controller?.seekToPrevious() }

    fun skipTo(index: Int) {
        val c = controller ?: return
        if (index in 0 until c.mediaItemCount) {
            c.seekTo(index, 0L)
            c.play()
        }
    }

    fun moveQueueItem(from: Int, to: Int) {
        val c = controller ?: return
        val last = c.mediaItemCount - 1
        if (from in 0..last && to in 0..last && from != to) c.moveMediaItem(from, to)
    }

    fun removeQueueItem(index: Int) {
        val c = controller ?: return
        if (index in 0 until c.mediaItemCount) c.removeMediaItem(index)
    }

    fun playNext(track: Track) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) playTracks(listOf(track))
        else c.addMediaItem(c.currentMediaItemIndex + 1, track.toMediaItem())
    }

    fun addToQueue(track: Track) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) playTracks(listOf(track)) else c.addMediaItem(track.toMediaItem())
    }

    fun setShuffle(enabled: Boolean) { controller?.shuffleModeEnabled = enabled }

    fun cycleRepeat() {
        val c = controller ?: return
        c.repeatMode = when (c.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    fun setVolume(v: Float) { controller?.volume = v.coerceIn(0f, 1f) }

    fun setSpeed(speed: Float) {
        controller?.playbackParameters = PlaybackParameters(speed.coerceIn(0.5f, 2f), 1f)
    }

    private fun sync(p: Player, rebuildQueue: Boolean) {
        _snapshot.update { old ->
            old.copy(
                isPlaying = p.isPlaying,
                playWhenReady = p.playWhenReady,
                isBuffering = p.playbackState == Player.STATE_BUFFERING,
                currentIndex = if (p.mediaItemCount > 0) p.currentMediaItemIndex else -1,
                shuffle = p.shuffleModeEnabled,
                repeat = when (p.repeatMode) {
                    Player.REPEAT_MODE_ALL -> RepeatMode.ALL
                    Player.REPEAT_MODE_ONE -> RepeatMode.ONE
                    else -> RepeatMode.OFF
                },
                speed = p.playbackParameters.speed,
                hasNext = p.hasNextMediaItem(),
                hasPrevious = p.hasPreviousMediaItem(),
                queue = if (rebuildQueue) {
                    List(p.mediaItemCount) { p.getMediaItemAt(it).toQueueItem(it) }
                } else old.queue,
            )
        }
        pushProgress(p)
    }

    private fun pushProgress(p: Player) {
        val duration = p.duration.takeIf { it != C.TIME_UNSET } ?: 0L
        _progress.value = Progress(p.currentPosition, duration, p.bufferedPosition)
    }

    private fun updateTicker(p: Player) {
        if (p.isPlaying) {
            if (tickJob?.isActive == true) return
            tickJob = scope.launch {
                while (isActive) {
                    controller?.let(::pushProgress)
                    delay(TICK_MS)
                }
            }
        } else {
            tickJob?.cancel()
            tickJob = null
        }
    }

    private companion object {
        const val TICK_MS = 50L
    }
}
