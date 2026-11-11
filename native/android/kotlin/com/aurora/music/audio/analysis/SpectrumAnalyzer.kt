package com.aurora.music.audio.analysis

import com.aurora.music.audio.PcmTap
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/** Log-spaced spectrum bands from the PCM tap, positioned at the audible (not decoded) frame. */
class SpectrumAnalyzer(private val tap: PcmTap, val bands: Int = 32) {

    private val fft = Fft(SIZE)
    private val window = DoubleArray(SIZE) { 0.5 - 0.5 * cos(2.0 * PI * it / SIZE) }
    private val re = DoubleArray(SIZE)
    private val im = DoubleArray(SIZE)
    private val buf = FloatArray(SIZE)
    private val smoothed = FloatArray(bands)
    private var edgesRate = 0
    private var edges = IntArray(bands + 1)

    /**
     * Fills [out] (size >= bands) with 0..1 magnitudes and returns RMS 0..1.
     * [originMs] maps tap frame 0 to media time; [positionMs] is the heard position.
     */
    @Synchronized
    fun sample(positionMs: Long, originMs: Double, out: FloatArray): Float {
        val sr = tap.sampleRate
        if (sr <= 0) return 0f
        val centreFrame = ((positionMs - originMs) / 1000.0 * sr).toLong()
        val start = centreFrame - SIZE / 2
        if (start < 0 || tap.read(start, buf) != SIZE) {
            decay(out)
            return 0f
        }
        var sum = 0.0
        for (i in 0 until SIZE) {
            re[i] = buf[i] * window[i]
            im[i] = 0.0
            sum += buf[i] * buf[i]
        }
        fft.transform(re, im)
        ensureEdges(sr)
        for (b in 0 until bands) {
            var acc = 0.0
            val lo = edges[b]
            val hi = max(lo + 1, edges[b + 1])
            for (k in lo until hi) acc += sqrt(re[k] * re[k] + im[k] * im[k])
            val mag = acc / (hi - lo) / (SIZE / 4.0)
            val db = 20.0 * log10(mag + 1e-7)
            val norm = ((db + 70.0) / 70.0).coerceIn(0.0, 1.0).toFloat()
            // Fast attack, slower release.
            smoothed[b] = if (norm > smoothed[b]) norm else smoothed[b] * 0.82f + norm * 0.18f
            out[b] = smoothed[b]
        }
        return min(1f, sqrt(sum / SIZE).toFloat() * 3f)
    }

    private fun decay(out: FloatArray) {
        for (b in 0 until bands) {
            smoothed[b] *= 0.85f
            out[b] = smoothed[b]
        }
    }

    private fun ensureEdges(sr: Int) {
        if (edgesRate == sr) return
        edgesRate = sr
        val fMin = 40.0
        val fMax = min(16_000.0, sr / 2.0 - 100.0)
        val binHz = sr.toDouble() / SIZE
        edges = IntArray(bands + 1) { i ->
            val f = fMin * (fMax / fMin).pow(i.toDouble() / bands)
            (f / binHz).toInt().coerceIn(1, SIZE / 2 - 1)
        }
        for (i in 1..bands) if (edges[i] <= edges[i - 1]) edges[i] = min(SIZE / 2 - 1, edges[i - 1] + 1)
    }

    private companion object {
        const val SIZE = 2048
        @Suppress("unused") val LN2 = ln(2.0)
    }
}
