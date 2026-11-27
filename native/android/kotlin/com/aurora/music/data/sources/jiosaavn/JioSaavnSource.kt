package com.aurora.music.data.sources.jiosaavn

import android.util.Base64
import com.aurora.music.data.sources.MusicSource
import com.aurora.music.data.sources.SourceKind
import com.aurora.music.data.sources.SourceStream
import com.aurora.music.data.sources.TrackKeys
import com.aurora.music.data.sources.remoteTrack
import com.aurora.music.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

/** A decoded CDN URL and the bitrate it will really deliver. */
data class SaavnStream(val url: String, val kbps: Int?)

/**
 * Picks the highest rendition the CDN really has. The encrypted URL names the 96 kbps object and the
 * catalogue says whether a parallel 320 exists; rewriting without that flag would claim a bitrate
 * the CDN cannot serve. Query parameters after the extension are preserved.
 */
internal fun selectBestSaavnStream(decryptedUrl: String, supports320: Boolean): SaavnStream? {
    if (decryptedUrl.isBlank()) return null
    val rendition = Regex("_(48|96|160|320)\\.(mp4|aac|mp3)(?=[?#]|$)", RegexOption.IGNORE_CASE)
        .find(decryptedUrl) ?: return SaavnStream(decryptedUrl, null)
    val offered = rendition.groupValues[1].toInt()
    if (!supports320) return SaavnStream(decryptedUrl, offered)
    return SaavnStream(decryptedUrl.replaceRange(rendition.range, "_320.${rendition.groupValues[2]}"), 320)
}

class JioSaavnSource(
    client: OkHttpClient,
) : MusicSource {

    override val kind = SourceKind.JIOSAAVN

    private val http = client.newBuilder()
        .callTimeout(8, TimeUnit.SECONDS)
        .connectTimeout(4, TimeUnit.SECONDS)
        .build()

    /** Search rows already carry the encrypted URL; keep it so playback skips a round trip. */
    private val encrypted = ConcurrentHashMap<String, Pair<String, Boolean>>()

    override suspend fun search(query: String, limit: Int): List<Track> {
        val body = call("search.getResults", "q" to query, "p" to "1", "n" to limit.coerceIn(1, 30).toString())
            ?: return emptyList()
        val results = runCatching { JSONObject(body).optJSONArray("results") }.getOrNull() ?: return emptyList()
        val songs = (0 until results.length()).mapNotNull { results.optJSONObject(it) }
        // Uncensored rows first; the catalogue files clean duplicates under the same title.
        return songs.sortedByDescending { isExplicit(it) }.mapNotNull(::toTrack).take(limit)
    }

    override suspend fun stream(rawId: String): SourceStream? {
        val cached = encrypted[rawId]
        val (enc, has320) = cached ?: fetchDetails(rawId) ?: return null
        val chosen = selectBestSaavnStream(decrypt(enc), has320) ?: return null
        // 48/96 kbps is below what YouTube serves; a miss lets the registry fall through to it.
        if (chosen.kbps != null && chosen.kbps <= MIN_USABLE_KBPS) return null
        return SourceStream(url = chosen.url, mimeType = "audio/mp4", kbps = chosen.kbps)
    }

    private suspend fun fetchDetails(id: String): Pair<String, Boolean>? {
        val body = call("song.getDetails", "pids" to id) ?: return null
        val root = runCatching { JSONObject(body) }.getOrNull() ?: return null
        // song.getDetails answers either {"songs":[…]} or a map keyed by the requested id.
        val song = root.optJSONArray("songs")?.optJSONObject(0)
            ?: root.optJSONObject(id)
            ?: root.keys().asSequence().mapNotNull { root.optJSONObject(it) }.firstOrNull()
            ?: return null
        val info = song.optJSONObject("more_info") ?: return null
        val enc = info.optString("encrypted_media_url")
        if (enc.isBlank()) return null
        return (enc to info.optString("320kbps").equals("true", true)).also { encrypted[id] = it }
    }

    private fun toTrack(song: JSONObject): Track? {
        val id = song.optString("id").takeIf { it.isNotBlank() } ?: return null
        val info = song.optJSONObject("more_info") ?: JSONObject()
        val enc = info.optString("encrypted_media_url")
        if (enc.isNotBlank()) encrypted[id] = enc to info.optString("320kbps").equals("true", true)

        val artists = info.optJSONObject("artistMap")?.optJSONArray("primary_artists")
        val artist = artists?.let { a ->
            (0 until a.length()).mapNotNull { a.optJSONObject(it)?.optString("name")?.takeIf { n -> n.isNotBlank() } }
        }.orEmpty().joinToString(", ")

        val image = song.optString("image")
            .replace(Regex("150x150|50x50"), "500x500")
            .replace(Regex("^http://"), "https://")
            .takeIf { it.isNotBlank() }

        return remoteTrack(
            key = TrackKeys.saavn(id),
            title = decodeEntities(song.optString("title")),
            artist = decodeEntities(artist),
            album = decodeEntities(info.optString("album")),
            durationSec = info.optString("duration").toLongOrNull() ?: 0L,
            artwork = image,
            mime = "audio/mp4",
        )
    }

    private fun isExplicit(song: JSONObject): Boolean =
        song.optString("explicit_content").let { it == "1" || it.equals("true", true) }

    private suspend fun call(method: String, vararg params: Pair<String, String>): String? =
        withContext(Dispatchers.IO) {
            runCatching {
                val url = BASE_URL.toHttpUrl().newBuilder()
                    .addQueryParameter("__call", method)
                    .addQueryParameter("_format", "json")
                    .addQueryParameter("_marker", "0")
                    .addQueryParameter("api_version", "4")
                    .addQueryParameter("ctx", "android")
                    .apply { params.forEach { (k, v) -> addQueryParameter(k, v) } }
                    .build()
                val request = Request.Builder().url(url)
                    .header("Accept", "application/json")
                    .header("User-Agent", USER_AGENT)
                    .header("Accept-Language", "en-IN,en;q=0.9")
                    .header("Cookie", "explicit_content=1")
                    .build()
                http.newCall(request).execute().use { r -> if (r.isSuccessful) r.body?.string() else null }
            }.getOrNull()
        }

    /** The catalogue's own client-side obfuscation: DES/ECB over a base64 URL. */
    private fun decrypt(encryptedUrl: String): String = runCatching {
        val cipher = Cipher.getInstance("DES/ECB/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(DES_KEY.toByteArray(Charsets.UTF_8), "DES"))
        String(cipher.doFinal(Base64.decode(encryptedUrl, Base64.DEFAULT)), Charsets.UTF_8).trim()
    }.getOrDefault("")

    private fun decodeEntities(s: String): String =
        s.replace("&quot;", "\"").replace("&amp;", "&").replace("&#039;", "'").replace("&lt;", "<").replace("&gt;", ">")

    private companion object {
        const val BASE_URL = "https://www.jiosaavn.com/api.php"
        const val DES_KEY = "38346591"
        const val MIN_USABLE_KBPS = 96
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    }
}
