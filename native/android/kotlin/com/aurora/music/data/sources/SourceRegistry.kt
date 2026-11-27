package com.aurora.music.data.sources

import com.aurora.music.data.RemoteCatalog
import com.aurora.music.model.Track
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs

/**
 * Fans a query out to every enabled source and routes playback by track key.
 *
 * Playback resolution: ask the track's own source first; when it has nothing (JioSaavn offering only
 * 96 kbps, a region block on YouTube), look the same recording up on the other sources and play that.
 */
class SourceRegistry(sources: List<MusicSource>) : RemoteCatalog {

    private val byKind = sources.associateBy { it.kind }
    private val order = sources.map { it.kind }

    /** Metadata for every remote track seen, so a key can be re-matched or re-displayed later. */
    private val seen = ConcurrentHashMap<String, Track>()
    private val streams = ConcurrentHashMap<String, Cached>()

    private class Cached(val stream: SourceStream, val at: Long)

    // ---- RemoteCatalog ----------------------------------------------------------------------------

    override suspend fun search(query: String): List<Track> = search(query, PER_SOURCE)

    override suspend fun resolve(mediaId: String): Track? = seen[mediaId]

    suspend fun search(query: String, perSource: Int): List<Track> = coroutineScope {
        val lists = order.map { kind ->
            async {
                withTimeoutOrNull(SEARCH_TIMEOUT_MS) {
                    runCatching { byKind.getValue(kind).search(query, perSource) }
                        .onFailure { if (it is CancellationException) throw it }
                        .getOrDefault(emptyList())
                } ?: emptyList()
            }
        }.map { it.await() }

        lists.flatten().forEach { seen[it.mediaId] = it }
        dedupe(interleave(lists))
    }

    // ---- Playback ---------------------------------------------------------------------------------

    suspend fun resolveStream(key: String): SourceStream? {
        streams[key]?.takeIf { System.currentTimeMillis() - it.at < STREAM_TTL_MS }?.let { return it.stream }

        val kind = TrackKeys.kindOf(key)
        val primary = byKind[kind]
        val direct = primary?.let { runCatching { it.stream(TrackKeys.rawId(key)) }.getOrNull() }
        val found = direct ?: matchElsewhere(key, kind)
        if (found != null) streams[key] = Cached(found, System.currentTimeMillis())
        return found
    }

    fun forget(key: String) {
        streams.remove(key)
    }

    private suspend fun matchElsewhere(key: String, skip: SourceKind): SourceStream? {
        val wanted = seen[key] ?: return null
        val query = "${wanted.artist} ${wanted.title}".trim()
        for (kind in order) {
            if (kind == skip) continue
            val source = byKind[kind] ?: continue
            val candidates = runCatching { source.search(query, 8) }.getOrDefault(emptyList())
            val best = candidates
                .map { it to TrackMatch.score(wanted, it) }
                .filter { it.second >= TrackMatch.THRESHOLD }
                .maxByOrNull { it.second }?.first ?: continue
            candidates.forEach { seen[it.mediaId] = it }
            val stream = runCatching { source.stream(TrackKeys.rawId(best.mediaId)) }.getOrNull()
            if (stream != null) return stream
        }
        return null
    }

    // ---- Result shaping ---------------------------------------------------------------------------

    private fun interleave(lists: List<List<Track>>): List<Track> {
        val out = ArrayList<Track>()
        val longest = lists.maxOfOrNull { it.size } ?: 0
        for (i in 0 until longest) lists.forEach { l -> l.getOrNull(i)?.let(out::add) }
        return out
    }

    /** Same recording from several sources: keep the first by source priority (earlier = preferred). */
    private fun dedupe(tracks: List<Track>): List<Track> {
        val seenKeys = HashSet<String>()
        return tracks.filter { t ->
            val k = TrackMatch.normalize(t.title) + "|" + TrackMatch.normalize(t.artist).take(12)
            seenKeys.add(k)
        }
    }

    private companion object {
        const val PER_SOURCE = 12
        const val SEARCH_TIMEOUT_MS = 8_000L
        const val STREAM_TTL_MS = 20 * 60_000L
    }
}

/** Title/artist/duration similarity used to find the same recording on another source. */
internal object TrackMatch {
    const val THRESHOLD = 0.62

    fun normalize(s: String): String =
        s.lowercase()
            .replace(Regex("\\(.*?\\)|\\[.*?]"), " ")
            .replace(Regex("\\b(feat|ft|featuring|official|video|audio|lyrics?|remaster(ed)?|version)\\b.*"), " ")
            .replace(Regex("[^\\p{L}\\p{N}]+"), " ")
            .trim()

    private fun tokens(s: String) = normalize(s).split(' ').filter { it.isNotEmpty() }.toSet()

    private fun jaccard(a: Set<String>, b: Set<String>): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        return a.intersect(b).size.toDouble() / a.union(b).size
    }

    fun score(wanted: Track, candidate: Track): Double {
        val title = jaccard(tokens(wanted.title), tokens(candidate.title))
        if (title < 0.5) return 0.0
        val artist = jaccard(tokens(wanted.artist), tokens(candidate.artist))
        // Different cuts of one song (radio edit, extended) differ by many seconds; reject wide gaps.
        val d1 = wanted.durationMs / 1000
        val d2 = candidate.durationMs / 1000
        val duration = if (d1 > 0 && d2 > 0) {
            val diff = abs(d1 - d2)
            if (diff > 8) return 0.0
            1.0 - diff / 8.0 * 0.3
        } else 0.8
        return title * 0.5 + artist * 0.3 + duration * 0.2
    }
}
