package com.aurora.music.audio.analysis

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.nio.ByteOrder
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlin.math.max

class TrackAnalysis(
    val bpm: Float,
    val confidence: Float,
    val firstBeatSec: Float,
    /** Peak amplitude per bucket, 0..1. */
    val waveform: FloatArray,
    /** Seconds per beat and per bar, and where the first full bar starts (seconds from the song start). */
    val beatSec: Float = 0f,
    val barSec: Float = 0f,
    val downbeatSec: Float = 0f,
    /** First / last audible moment (ms): lets a blend skip leading silence and start before a fade-out tail. */
    val introMs: Long = 0L,
    val outroMs: Long = 0L,
    /** RMS level of the whole song, used to match the loudness of the next song. */
    val loudness: Float = 0f,
    val durationMs: Long = 0L,
)

/** Decodes a track once to produce a waveform overview and a tempo estimate from its middle 30 s. */
class TrackAnalyzer(private val context: Context, private val tracker: BeatTracker) {

    suspend fun analyze(
        uri: String,
        buckets: Int = 160,
        source: (() -> android.media.MediaDataSource)? = null,
    ): TrackAnalysis? = withContext(Dispatchers.Default) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (source != null) extractor.setDataSource(source()) else extractor.setDataSource(context, Uri.parse(uri), null)
            val trackIndex = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return@withContext null
            extractor.selectTrack(trackIndex)
            val format = extractor.getTrackFormat(trackIndex)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return@withContext null
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var float = false

            val totalEstimate = max(1L, durationUs * sampleRate / 1_000_000L)
            val bucketSize = max(1L, totalEstimate / buckets)
            val peaks = FloatArray(buckets)

            val regionStart = max(0L, totalEstimate / 2 - REGION_SEC * sampleRate / 2)
            val regionEnd = regionStart + REGION_SEC * sampleRate
            var region = FloatArray((REGION_SEC * sampleRate).toInt())
            var regionFill = 0

            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var frame = 0L
            var firstLoud = -1L
            var lastLoud = -1L
            var sumSq = 0.0
            var count = 0L

            while (!outputDone) {
                coroutineContext.ensureActive()
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                when {
                    o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val out = codec.outputFormat
                        sampleRate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        float = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    o >= 0 -> {
                        val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                        buf.position(info.offset).limit(info.offset + info.size)
                        val frames = if (float) buf.remaining() / (4 * channels) else buf.remaining() / (2 * channels)
                        val fb = if (float) buf.asFloatBuffer() else null
                        val sb = if (!float) buf.asShortBuffer() else null
                        repeat(frames) {
                            var s = 0f
                            repeat(channels) { s += fb?.get() ?: (sb!!.get() / 32768f) }
                            s /= channels
                            val bucket = (frame / bucketSize).toInt().coerceAtMost(buckets - 1)
                            val a = abs(s)
                            if (a > 0.02f) {
                                if (firstLoud < 0) firstLoud = frame
                                lastLoud = frame
                            }
                            sumSq += (s * s).toDouble()
                            count++
                            if (a > peaks[bucket]) peaks[bucket] = a
                            if (frame in regionStart until regionEnd) {
                                if (regionFill >= region.size) region = region.copyOf(region.size * 2)
                                region[regionFill++] = s
                            }
                            frame++
                        }
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }

            val maxPeak = peaks.maxOrNull()?.takeIf { it > 0f } ?: 1f
            val waveform = FloatArray(buckets) { (peaks[it] / maxPeak).coerceIn(0f, 1f) }

            val pcm = Resampler(sampleRate, MelFrontEnd.SAMPLE_RATE).process(region.copyOf(regionFill))
            val grid = tracker.track(pcm)
            val regionStartSec = regionStart.toDouble() / sampleRate
            var beatSec = 0.0
            var barSec = 0.0
            var downSec = 0.0
            if (grid != null && grid.bpm in 40.0..220.0 && grid.beatsSec.isNotEmpty()) {
                beatSec = 60.0 / grid.bpm
                barSec = beatSec * grid.beatsPerBar
                val d0 = grid.downbeatsSec.firstOrNull() ?: grid.beatsSec.first()
                downSec = (regionStartSec + d0) % barSec
                if (downSec < 0) downSec += barSec
            }
            TrackAnalysis(
                bpm = grid?.bpm?.toFloat() ?: 0f,
                confidence = grid?.confidence?.toFloat() ?: 0f,
                firstBeatSec = grid?.beatsSec?.firstOrNull()?.toFloat() ?: 0f,
                waveform = waveform,
                beatSec = beatSec.toFloat(),
                barSec = barSec.toFloat(),
                downbeatSec = downSec.toFloat(),
                introMs = if (firstLoud < 0) 0L else firstLoud * 1000L / sampleRate,
                outroMs = if (lastLoud < 0) 0L else lastLoud * 1000L / sampleRate,
                loudness = if (count > 0) Math.sqrt(sumSq / count).toFloat() else 0f,
                durationMs = frame * 1000L / sampleRate,
            )
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            extractor.release()
        }
    }

    private companion object {
        const val TIMEOUT_US = 5_000L
        const val REGION_SEC = 30L
    }
}
