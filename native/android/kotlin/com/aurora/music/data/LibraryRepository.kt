package com.aurora.music.data

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import com.aurora.music.model.Album
import com.aurora.music.model.LibraryState
import com.aurora.music.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface RemoteCatalog {
    suspend fun search(query: String): List<Track>
    suspend fun resolve(mediaId: String): Track?
}

object NoRemoteCatalog : RemoteCatalog {
    override suspend fun search(query: String): List<Track> = emptyList()
    override suspend fun resolve(mediaId: String): Track? = null
}

class LibraryRepository(
    private val context: Context,
    private val scope: CoroutineScope,
    private val remote: RemoteCatalog = NoRemoteCatalog,
) {
    private val indexer = MediaStoreIndexer(context.contentResolver)
    private val mutex = Mutex()

    private val _tracks = MutableStateFlow<List<Track>>(emptyList())
    val tracks: StateFlow<List<Track>> = _tracks.asStateFlow()

    private val _albums = MutableStateFlow<List<Album>>(emptyList())
    val albums: StateFlow<List<Album>> = _albums.asStateFlow()

    private val _state = MutableStateFlow(
        if (hasAudioPermission()) LibraryState.Scanning else LibraryState.NeedsPermission
    )
    val state: StateFlow<LibraryState> = _state.asStateFlow()

    @Volatile private var byId: Map<String, Track> = emptyMap()
    private var debounce: Job? = null

    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            debounce?.cancel()
            debounce = scope.launch {
                delay(1_500)
                scan(force = true)
            }
        }
    }

    init {
        context.contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, observer
        )
    }

    fun refresh() {
        scope.launch { scan(force = true) }
    }

    suspend fun ensureLoaded() = scan(force = false)

    fun hasAudioPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    private suspend fun scan(force: Boolean) = mutex.withLock {
        if (!force && _state.value == LibraryState.Ready) return@withLock
        if (!hasAudioPermission()) {
            _state.value = LibraryState.NeedsPermission
            return@withLock
        }
        _state.value = LibraryState.Scanning
        val result = withContext(Dispatchers.IO) {
            runCatching { indexer.queryTracks() }.getOrDefault(emptyList())
        }
        val albums = withContext(Dispatchers.Default) { buildAlbums(result) }
        byId = result.associateBy { it.mediaId }
        _tracks.value = result
        _albums.value = albums
        _state.value = LibraryState.Ready
    }

    private fun buildAlbums(tracks: List<Track>): List<Album> =
        tracks.groupBy { it.albumId }
            .map { (id, list) ->
                val first = list.first()
                Album(
                    id = id,
                    title = first.album,
                    artist = first.albumArtist ?: first.artist,
                    artworkUri = first.artworkUri,
                    year = list.maxOf { it.year },
                    trackCount = list.size,
                )
            }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })

    suspend fun resolve(mediaId: String): Track? {
        ensureLoaded()
        return byId[mediaId] ?: remote.resolve(mediaId)
    }

    suspend fun tracksForAlbum(albumId: Long): List<Track> {
        ensureLoaded()
        return _tracks.value
            .filter { it.albumId == albumId }
            .sortedWith(compareBy({ it.discNumber }, { it.trackNumber }, { it.title }))
    }

    suspend fun searchLocal(query: String): List<Track> {
        ensureLoaded()
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        return _tracks.value.filter {
            it.title.contains(q, ignoreCase = true) ||
                it.artist.contains(q, ignoreCase = true) ||
                it.album.contains(q, ignoreCase = true)
        }
    }

    suspend fun searchRemote(query: String): List<Track> {
        val q = query.trim()
        if (q.length < 2) return emptyList()
        return runCatching { remote.search(q) }.getOrDefault(emptyList())
    }

    suspend fun search(query: String): List<Track> = searchLocal(query) + searchRemote(query)
}
