package com.aurora.music.audio.analysis

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** In-place radix-2 complex FFT. Instances are immutable after construction and thread-safe. */
class Fft(val size: Int) {
    private val cosTable: DoubleArray
    private val sinTable: DoubleArray
    private val reversed: IntArray

    init {
        require(size >= 2 && size and (size - 1) == 0) { "size must be a power of two" }
        cosTable = DoubleArray(size / 2) { cos(2.0 * PI * it / size) }
        sinTable = DoubleArray(size / 2) { -sin(2.0 * PI * it / size) }
        val bits = Integer.numberOfTrailingZeros(size)
        reversed = IntArray(size) { Integer.reverse(it) ushr (32 - bits) }
    }

    fun transform(re: DoubleArray, im: DoubleArray) {
        for (i in 0 until size) {
            val j = reversed[i]
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var length = 2
        while (length <= size) {
            val half = length shr 1
            val step = size / length
            var start = 0
            while (start < size) {
                var k = 0
                for (offset in 0 until half) {
                    val wr = cosTable[k]
                    val wi = sinTable[k]
                    val a = start + offset
                    val b = a + half
                    val xr = re[b] * wr - im[b] * wi
                    val xi = re[b] * wi + im[b] * wr
                    re[b] = re[a] - xr
                    im[b] = im[a] - xi
                    re[a] += xr
                    im[a] += xi
                    k += step
                }
                start += length
            }
            length = length shl 1
        }
    }
}
