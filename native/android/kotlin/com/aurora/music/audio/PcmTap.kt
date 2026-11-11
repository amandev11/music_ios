package com.aurora.music.audio

import androidx.media3.common.C
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.min

/**
 * Single-producer (audio thread) / multi-consumer lock-free mono ring buffer.
 * Frame indices are monotonic since the last [reset] (seek / track change).
 */
class PcmTap(private val capacity: Int = 1 shl 20) {
    init {
        require(capacity > 0 && capacity and (capacity - 1) == 0) { "capacity must be a power of two" }
    }

    private val ring = FloatArray(capacity)
    private val mask = capacity - 1
    private val written = AtomicLong(0L)

    @Volatile var sampleRate: Int = 0
        private set

    @Volatile var channelCount: Int = 0
        private set

    @Volatile var generation: Int = 0
        private set

    /** Invoked on the audio thread after every [reset]; must be cheap (post elsewhere). */
    @Volatile var onReset: (() -> Unit)? = null

    fun configure(sampleRate: Int, channelCount: Int) {
        this.sampleRate = sampleRate
        this.channelCount = channelCount
        reset()
    }

    fun reset() {
        written.set(0L)
        generation++
        onReset?.invoke()
    }

    fun framesWritten(): Long = written.get()

    fun write(input: ByteBuffer, encoding: Int) {
        val ch = channelCount
        if (ch <= 0) return
        val view = input.asReadOnlyBuffer().order(ByteOrder.nativeOrder())
        var w = written.get()
        if (encoding == C.ENCODING_PCM_FLOAT) {
            val f = view.asFloatBuffer()
            val frames = f.remaining() / ch
            repeat(frames) {
                var s = 0f
                repeat(ch) { s += f.get() }
                ring[w.toInt() and mask] = s / ch
                w++
            }
        } else {
            val sh = view.asShortBuffer()
            val frames = sh.remaining() / ch
            val scale = 1f / (ch * 32768f)
            repeat(frames) {
                var s = 0
                repeat(ch) { s += sh.get() }
                ring[w.toInt() and mask] = s * scale
                w++
            }
        }
        written.set(w)
    }

    /** Copies up to dst.size samples starting at [fromFrame]. Returns count, or -1 if overwritten. */
    fun read(fromFrame: Long, dst: FloatArray): Int {
        val end = written.get()
        if (fromFrame < end - capacity) return -1
        val n = min(dst.size.toLong(), end - fromFrame).toInt()
        if (n <= 0) return 0
        var idx = fromFrame
        for (i in 0 until n) {
            dst[i] = ring[idx.toInt() and mask]
            idx++
        }
        return if (written.get() - capacity > fromFrame) -1 else n
    }

    fun readLatest(dst: FloatArray): Int {
        val from = (written.get() - dst.size).coerceAtLeast(0L)
        return read(from, dst)
    }
}
