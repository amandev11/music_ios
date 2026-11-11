package com.aurora.music.audio.analysis

import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.ln1p
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import kotlin.math.PI

/**
 * Log-mel front end Beat This! was trained on (torchaudio MelSpectrogram, center=True, reflect pad,
 * periodic Hann, magnitude / sqrt(n_fft), Slaney mel 30..11000 Hz without area normalisation,
 * log1p(1000 * x)). Input must be mono at [SAMPLE_RATE].
 */
object MelFrontEnd {
    const val SAMPLE_RATE = 22_050
    const val N_FFT = 1024
    const val HOP = 441
    const val MELS = 128
    const val FRAME_RATE = SAMPLE_RATE.toDouble() / HOP

    private const val F_MIN = 30.0
    private const val F_MAX = 11_000.0
    private const val LOG_MULTIPLIER = 1000.0
    private const val AMPLITUDE_FLOOR = 1e-10
    private const val BINS = N_FFT / 2 + 1

    class Spectrogram(val values: FloatArray, val frames: Int)

    private class Filter(val firstBin: Int, val weights: DoubleArray)

    private val fft = Fft(N_FFT)
    private val window = DoubleArray(N_FFT) { 0.5 - 0.5 * cos(2.0 * PI * it / N_FFT) }
    private val filters: Array<Filter> by lazy(::buildFilterbank)

    fun compute(samples: FloatArray): Spectrogram? {
        val pad = N_FFT / 2
        if (samples.size <= pad + 1) return null

        val n = samples.size
        val padded = FloatArray(n + 2 * pad)
        for (i in 0 until pad) padded[i] = samples[pad - i]
        System.arraycopy(samples, 0, padded, pad, n)
        for (i in 0 until pad) padded[pad + n + i] = samples[n - 2 - i]

        val frames = (padded.size - N_FFT) / HOP + 1
        if (frames <= 0) return null

        val out = FloatArray(frames * MELS)
        val re = DoubleArray(N_FFT)
        val im = DoubleArray(N_FFT)
        val magnitude = DoubleArray(BINS)
        val norm = sqrt(N_FFT.toDouble())
        val bank = filters

        for (frame in 0 until frames) {
            val start = frame * HOP
            for (i in 0 until N_FFT) {
                re[i] = padded[start + i] * window[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            for (b in 0 until BINS) magnitude[b] = sqrt(re[b] * re[b] + im[b] * im[b]) / norm

            val row = frame * MELS
            for (m in 0 until MELS) {
                val f = bank[m]
                var energy = 0.0
                for (o in f.weights.indices) energy += magnitude[f.firstBin + o] * f.weights[o]
                out[row + m] = ln1p(LOG_MULTIPLIER * max(energy, AMPLITUDE_FLOOR)).toFloat()
            }
        }
        return Spectrogram(out, frames)
    }

    private fun hzToMel(hz: Double): Double {
        val fSp = 200.0 / 3.0
        val minLogMel = 1000.0 / fSp
        val logStep = ln(6.4) / 27.0
        return if (hz >= 1000.0) minLogMel + ln(hz / 1000.0) / logStep else hz / fSp
    }

    private fun melToHz(mel: Double): Double {
        val fSp = 200.0 / 3.0
        val minLogMel = 1000.0 / fSp
        val logStep = ln(6.4) / 27.0
        return if (mel >= minLogMel) 1000.0 * exp(logStep * (mel - minLogMel)) else fSp * mel
    }

    private fun buildFilterbank(): Array<Filter> {
        val melMin = hzToMel(F_MIN)
        val melMax = hzToMel(F_MAX)
        val edges = DoubleArray(MELS + 2) { melToHz(melMin + (melMax - melMin) * it / (MELS + 1)) }
        fun toBin(hz: Double) = hz * N_FFT / SAMPLE_RATE

        return Array(MELS) { m ->
            val left = edges[m]
            val centre = edges[m + 1]
            val right = edges[m + 2]
            val first = max(0.0, floor(toBin(left))).toInt()
            val last = min(BINS - 1, ceil(toBin(right)).toInt())
            if (last < first) {
                Filter(0, DoubleArray(0))
            } else {
                Filter(first, DoubleArray(last - first + 1) { i ->
                    val hz = (first + i).toDouble() * SAMPLE_RATE / N_FFT
                    val rising = if (centre > left) (hz - left) / (centre - left) else 0.0
                    val falling = if (right > centre) (right - hz) / (right - centre) else 0.0
                    max(0.0, min(rising, falling))
                })
            }
        }
    }

}
