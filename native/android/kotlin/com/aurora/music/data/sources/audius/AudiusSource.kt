package com.aurora.music.data.sources.audius

import com.aurora.music.data.sources.MusicSource
import com.aurora.music.data.sources.SourceKind
import com.aurora.music.data.sources.SourceStream
import com.aurora.music.data.sources.remoteTrack
import com.aurora.music.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Audius: an open, artist-owned catalogue with a public API. Full-length 320 kbps MP3 streams, no key. */
class AudiusSource(client: OkHttpClient) : MusicSource {
    override val kind = SourceKind.AUDIUS

    private val http = client.newBuilder()
        .callTimeout(8, TimeUnit.SECONDS)
        .connectTimeout(4, TimeUnit.SECONDS)
        .build()

    override suspend fun search(query: String, limit: Int): List<Track> = withContext(Dispatchers.IO) {
        val url = "$BASE/v1/tracks/search".toHttpUrl().newBuilder()
            .addQueryParameter("query", query)
            .addQueryParameter("app_name", APP)
            .addQueryParameter("limit", limit.coerceIn(1, 30).toString())
            .build()
        val body = runCatching {
            http.newCall(Request.Builder().url(url).build()).execute().use { if (it.isSuccessful) it.body?.string() else null }
        }.getOrNull() ?: return@withContext emptyList()
        val arr = runCatching { JSONObject(body).optJSONArray("data") }.getOrNull() ?: return@withContext emptyList()
        (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }.mapNotNull { t ->
            val id = t.optString("id").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            if (!t.optBoolean("is_streamable", true)) return@mapNotNull null
            val art = t.optJSONObject("artwork")
            remoteTrack(
                key = "${SourceKind.AUDIUS.prefix}$id",
                title = t.optString("title"),
                artist = t.optJSONObject("user")?.optString("name").orEmpty(),
                album = t.optString("genre"),
                durationSec = t.optLong("duration"),
                artwork = art?.optString("1000x1000")?.takeIf { it.isNotBlank() }
                    ?: art?.optString("480x480")?.takeIf { it.isNotBlank() },
                mime = "audio/mpeg",
            )
        }
    }

    override suspend fun stream(rawId: String): SourceStream? =
        SourceStream(url = "$BASE/v1/tracks/$rawId/stream?app_name=$APP", mimeType = "audio/mpeg", kbps = 320)

    private companion object {
        const val BASE = "https://api.audius.co"
        const val APP = "keystone"
    }
}
