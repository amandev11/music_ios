package com.aurora.music.audio.analysis

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin

/** Band-limited (windowed-sinc) block resampler for mono float PCM. */
class Resampler(private val inRate: Int, private val outRate: Int, private val zeroCrossings: Int = 16) {

    private val ratio = inRate.toDouble() / outRate
    private val cutoff = if (outRate < inRate) outRate.toDouble() / inRate else 1.0
    private val support = zeroCrossings / cutoff
    private val table: FloatArray
    private val tableLen: Int

    init {
        require(inRate > 0 && outRate > 0)
        tableLen = (support * TABLE_STEPS).toInt() + 2
        table = FloatArray(tableLen) { i ->
            val x = i.toDouble() / TABLE_STEPS
            if (x >= support) 0f else {
                val sinc = if (x == 0.0) 1.0 else sin(PI * cutoff * x) / (PI * cutoff * x)
                val w = 0.42 + 0.5 * cos(PI * x / support) + 0.08 * cos(2.0 * PI * x / support)
                (cutoff * sinc * w).toFloat()
            }
        }
    }

    fun process(input: FloatArray): FloatArray {
        if (inRate == outRate) return input
        val outLen = (input.size / ratio).toInt()
        val out = FloatArray(outLen)
        for (o in 0 until outLen) {
            val centre = o * ratio
            val lo = ceil(centre - support).toInt().coerceAtLeast(0)
            val hi = floor(centre + support).toInt().coerceAtMost(input.size - 1)
            var acc = 0.0
            for (i in lo..hi) {
                val pos = abs(i - centre) * TABLE_STEPS
                val idx = pos.toInt()
                if (idx + 1 >= tableLen) continue
                val frac = pos - idx
                val k = table[idx] + (table[idx + 1] - table[idx]) * frac
                acc += input[i] * k
            }
            out[o] = acc.toFloat()
        }
        return out
    }

    private companion object {
        const val TABLE_STEPS = 256
    }
}
