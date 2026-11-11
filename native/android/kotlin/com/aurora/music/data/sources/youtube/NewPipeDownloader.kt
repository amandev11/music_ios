package com.aurora.music.data.sources.youtube

import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException

/** OkHttp-backed [Downloader] for NewPipeExtractor, with the lessons BitChord paid for baked in. */
internal class NewPipeDownloader(private val client: OkHttpClient) : Downloader() {

    override fun execute(request: Request): Response {
        // The `next` (related videos) endpoint is never read here and is the one request that hangs for
        // seconds, failing whole extractions. A well-formed empty envelope (the library rejects JSON
        // bodies under 50 chars) lets the extractor carry on without it.
        if (NEXT_ENDPOINT in request.url()) {
            return Response(200, "OK", emptyMap(), EMPTY_NEXT_RESPONSE, request.url())
        }

        val builder = okhttp3.Request.Builder()
            .method(request.httpMethod(), request.dataToSend()?.toRequestBody())
            .url(request.url())

        var hasUserAgent = false
        request.headers().forEach { (name, values) ->
            if (name.equals("User-Agent", ignoreCase = true) && values.isNotEmpty()) hasUserAgent = true
            when {
                values.size > 1 -> {
                    builder.removeHeader(name)
                    values.forEach { builder.addHeader(name, it) }
                }
                values.size == 1 -> builder.header(name, values[0])
            }
        }
        // Chrome, not Firefox: with a Firefox default the player-JS fetch yields
        // "Could not parse deobfuscation function" on the same extractor version.
        if (!hasUserAgent) builder.header("User-Agent", CHROME_UA)

        val response = client.newCall(builder.build()).execute()
        if (response.code == 429) {
            response.close()
            throw ReCaptchaException("reCaptcha Challenge requested", request.url())
        }
        return response.use {
            Response(it.code, it.message, it.headers.toMultimap(), it.body?.string(), it.request.url.toString())
        }
    }

    private companion object {
        const val NEXT_ENDPOINT = "/youtubei/v1/next"
        const val EMPTY_NEXT_RESPONSE =
            """{"responseContext":{},"contents":{},"currentVideoEndpoint":{},"trackingParams":""}"""
        const val CHROME_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    }
}
