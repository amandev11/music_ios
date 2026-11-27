package com.aurora.music.playback

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.aurora.music.MainActivity
import com.aurora.music.MusicApp
import com.aurora.music.R
import com.aurora.music.audio.BitChordAudioEngine
import com.aurora.music.audio.EngineRegistry
import com.aurora.music.audio.StreamResolver
import com.aurora.music.data.sources.TrackKeys
import com.aurora.music.widget.NowPlayingWidget
import android.graphics.Bitmap
import android.util.Log
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.guava.future

@UnstableApi
class PlaybackService : MediaLibraryService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var engine: BitChordAudioEngine
    private lateinit var session: MediaLibrarySession

    private val library get() = (application as MusicApp).graph.library

    private var artLoader: ArtworkBitmapLoader? = null
    private var widgetArtKey: String? = null

    private val modeListener = object : Player.Listener {
        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) = refreshButtons()
        override fun onRepeatModeChanged(repeatMode: Int) = refreshButtons()
        override fun onEvents(player: Player, events: Player.Events) {
            if (events.containsAny(
                    Player.EVENT_MEDIA_ITEM_TRANSITION, Player.EVENT_IS_PLAYING_CHANGED,
                    Player.EVENT_MEDIA_METADATA_CHANGED, Player.EVENT_PLAYBACK_STATE_CHANGED,
                )
            ) pushWidget(player)
        }
    }

    /** Mirrors the current item onto the home-screen widget. Never throws. */
    private fun pushWidget(player: Player) {
        try {
            val item = player.currentMediaItem
            val m = item?.mediaMetadata
            val title = (m?.title ?: m?.displayTitle)?.toString()
            val artist = m?.artist?.toString().orEmpty()
            val uri = m?.artworkUri
            val key = item?.mediaId
            if (title == null) {
                widgetArtKey = null
                NowPlayingWidget.push(this, "", "", false, null)
                return
            }
            val changed = key != widgetArtKey
            if (changed) widgetArtKey = key
            NowPlayingWidget.push(this, title, artist, player.isPlaying, null, clearArt = changed)
            if (uri != null && changed) {
                val f = artLoader?.loadBitmap(uri) ?: return
                f.addListener({
                    try {
                        val bmp: Bitmap = f.get()
                        if (widgetArtKey == key) NowPlayingWidget.push(this, title, artist, engine.player.isPlaying, bmp)
                    } catch (t: Throwable) {
                        Log.d("Aurora", "widget artwork unavailable", t)
                    }
                }, androidx.core.content.ContextCompat.getMainExecutor(this))
            }
        } catch (t: Throwable) {
            Log.w("Aurora", "widget push failed", t)
        }
    }

    override fun onCreate() {
        super.onCreate()
        engine = BitChordAudioEngine(this, StreamResolver((application as MusicApp).graph.sources))
        EngineRegistry.publish(engine)

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        session = MediaLibrarySession.Builder(this, engine.player, LibraryCallback())
            .setSessionActivity(contentIntent)
            .setBitmapLoader(ArtworkBitmapLoader(this).also { artLoader = it })
            .build()

        setMediaNotificationProvider(
            DefaultMediaNotificationProvider.Builder(this)
                .setChannelId(CHANNEL_ID)
                .setChannelName(R.string.playback_channel)
                .setNotificationId(NOTIFICATION_ID)
                .build()
        )

        engine.player.addListener(modeListener)
        refreshButtons()
        pushWidget(engine.player)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app out of recents ends playback completely.
        runCatching {
            val p = session.player
            p.playWhenReady = false
            p.stop()
            p.clearMediaItems()
        }
        widgetArtKey = null
        NowPlayingWidget.push(this, "", "", false, null)
        stopSelf()
    }

    override fun onDestroy() {
        engine.player.removeListener(modeListener)
        session.release()
        EngineRegistry.clear(engine)
        engine.release()
        scope.cancel()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun refreshButtons() {
        session.setCustomLayout(buttons())
    }

    private fun buttons(): ImmutableList<CommandButton> {
        val p = engine.player
        val shuffle = CommandButton.Builder(
            if (p.shuffleModeEnabled) CommandButton.ICON_SHUFFLE_ON else CommandButton.ICON_SHUFFLE_OFF
        ).setDisplayName("Shuffle").setSessionCommand(CMD_SHUFFLE).build()

        val repeat = CommandButton.Builder(
            when (p.repeatMode) {
                Player.REPEAT_MODE_ALL -> CommandButton.ICON_REPEAT_ALL
                Player.REPEAT_MODE_ONE -> CommandButton.ICON_REPEAT_ONE
                else -> CommandButton.ICON_REPEAT_OFF
            }
        ).setDisplayName("Repeat").setSessionCommand(CMD_REPEAT).build()

        return ImmutableList.of(shuffle, repeat)
    }

    private inner class LibraryCallback : MediaLibrarySession.Callback {

        @Suppress("DEPRECATION")
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): MediaSession.ConnectionResult {
            val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS
                .buildUpon()
                .add(CMD_SHUFFLE)
                .add(CMD_REPEAT)
                .build()
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(commands)
                .setCustomLayout(buttons())
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            val p = engine.player
            when (customCommand.customAction) {
                ACTION_SHUFFLE -> p.shuffleModeEnabled = !p.shuffleModeEnabled
                ACTION_REPEAT -> p.repeatMode = when (p.repeatMode) {
                    Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
                    Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
                    else -> Player.REPEAT_MODE_OFF
                }
                else -> return Futures.immediateFuture(SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED))
            }
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(
                LibraryResult.ofItem(
                    browsableNode(MediaIds.ROOT, "Aurora", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED),
                    params,
                )
            )

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> = scope.future {
            val item = when (mediaId) {
                MediaIds.ROOT -> browsableNode(MediaIds.ROOT, "Aurora", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                MediaIds.SONGS -> browsableNode(MediaIds.SONGS, "Songs", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                MediaIds.ALBUMS -> browsableNode(MediaIds.ALBUMS, "Albums", MediaMetadata.MEDIA_TYPE_FOLDER_ALBUMS)
                else -> library.resolve(mediaId)?.toMediaItem()
            }
            if (item != null) LibraryResult.ofItem(item, null)
            else LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE)
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = scope.future {
            library.ensureLoaded()
            val items: List<MediaItem> = when {
                parentId == MediaIds.ROOT -> listOf(
                    browsableNode(MediaIds.SONGS, "Songs", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED),
                    browsableNode(MediaIds.ALBUMS, "Albums", MediaMetadata.MEDIA_TYPE_FOLDER_ALBUMS),
                )
                parentId == MediaIds.SONGS -> library.tracks.value.map { it.toMediaItem() }
                parentId == MediaIds.ALBUMS -> library.albums.value.map { it.toNodeItem() }
                else -> MediaIds.parseAlbum(parentId)
                    ?.let { library.tracksForAlbum(it).map { t -> t.toMediaItem() } }
                    ?: return@future LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE)
            }
            LibraryResult.ofItemList(ImmutableList.copyOf(items.paged(page, pageSize)), params)
        }

        override fun onSearch(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<Void>> = scope.future {
            val count = library.search(query).size
            session.notifySearchResultChanged(browser, query, count, params)
            LibraryResult.ofVoid()
        }

        override fun onGetSearchResult(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = scope.future {
            val items = library.search(query).map { it.toMediaItem() }
            LibraryResult.ofItemList(ImmutableList.copyOf(items.paged(page, pageSize)), params)
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> = scope.future {
            mediaItems.map { item ->
                when {
                    item.localConfiguration != null -> item
                    // Remote ids always play through the lazy resolver, even after process death.
                    TrackKeys.isRemote(item.mediaId) ->
                        item.buildUpon().setUri(TrackKeys.streamUri(item.mediaId)).build()
                    else -> library.resolve(item.mediaId)?.toMediaItem() ?: item
                }
            }.toMutableList()
        }
    }

    private fun <T> List<T>.paged(page: Int, pageSize: Int): List<T> {
        if (pageSize <= 0 || pageSize == Int.MAX_VALUE) return this
        val from = (page.toLong() * pageSize).coerceAtMost(size.toLong()).toInt()
        return subList(from, (from + pageSize).coerceAtMost(size))
    }

    companion object {
        const val CHANNEL_ID = "aurora_playback"
        const val NOTIFICATION_ID = 1001
        const val ACTION_SHUFFLE = "com.aurora.music.TOGGLE_SHUFFLE"
        const val ACTION_REPEAT = "com.aurora.music.CYCLE_REPEAT"
        val CMD_SHUFFLE = SessionCommand(ACTION_SHUFFLE, Bundle.EMPTY)
        val CMD_REPEAT = SessionCommand(ACTION_REPEAT, Bundle.EMPTY)
    }
}
