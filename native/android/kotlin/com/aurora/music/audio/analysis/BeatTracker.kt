package com.aurora.music.audio.analysis

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

data class BeatGrid(
    val beatsSec: DoubleArray,
    val downbeatsSec: DoubleArray,
    val bpm: Double,
    val confidence: Double,
) {
    val intervalSec: Double get() = 60.0 / bpm

    val beatsPerBar: Int
        get() {
            if (downbeatsSec.size < 2) return 4
            val counts = IntArray(downbeatsSec.size - 1) { i ->
                beatsSec.count { it > downbeatsSec[i] - 1e-6 && it < downbeatsSec[i + 1] - 1e-6 }
            }.filter { it in 2..12 }
            return counts.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key ?: 4
        }
}

/**
 * Beat This! (CPJKU) beat/downbeat tracker on ONNX Runtime.
 * Model: input_spectrogram [1, time, 128] -> beat [1, time], downbeat [1, time] logits at 50 fps.
 * Input audio must be mono 22.05 kHz; use [Resampler] upstream.
 */
class BeatTracker(private val modelBytes: () -> ByteArray, private val threads: Int = 2) {

    @Volatile private var session: OrtSession? = null
    private val lock = Any()

    private fun session(): OrtSession? {
        session?.let { return it }
        synchronized(lock) {
            session?.let { return it }
            return runCatching {
                val opts = OrtSession.SessionOptions().apply {
                    setIntraOpNumThreads(threads)
                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                    setCPUArenaAllocator(false)
                    setMemoryPatternOptimization(false)
                }
                OrtEnvironment.getEnvironment().createSession(modelBytes(), opts).also { session = it }
            }.getOrNull()
        }
    }

    fun track(pcm22k: FloatArray): BeatGrid? {
        val spec = MelFrontEnd.compute(pcm22k) ?: return null
        val active = session() ?: return null
        val beatLogits = FloatArray(spec.frames)
        val downLogits = FloatArray(spec.frames)
        if (!infer(active, spec, beatLogits, downLogits)) return null

        val fps = MelFrontEnd.FRAME_RATE
        val beatFrames = pickPeaks(beatLogits)
        val beats = DoubleArray(beatFrames.size) { beatFrames[it] / fps }
        if (beats.size < MIN_BEATS) return null

        val bpm = tempoFromBeats(beats)
        if (bpm <= 0.0) return null

        val downs = pickPeaks(downLogits)
            .map { it / fps }
            .map { t -> beats.minByOrNull { abs(it - t) } ?: beats.first() }
            .distinct()
            .sorted()
            .toDoubleArray()

        val strengths = beatFrames.map { beatLogits.getOrElse(it.roundToInt()) { 0f }.toDouble() }
        return BeatGrid(beats, downs, bpm, confidence(beats, strengths))
    }

    @Suppress("UNCHECKED_CAST")
    private fun infer(
        session: OrtSession,
        spec: MelFrontEnd.Spectrogram,
        beatOut: FloatArray,
        downOut: FloatArray,
    ): Boolean = runCatching {
        val env = OrtEnvironment.getEnvironment()
        val inputName = session.inputNames.first()
        val stride = CHUNK_FRAMES - 2 * BORDER_FRAMES
        val mels = MelFrontEnd.MELS
        var start = 0
        while (start < spec.frames) {
            val length = min(CHUNK_FRAMES, spec.frames - start)
            if (length <= 2 * BORDER_FRAMES && start > 0) break
            val chunk = spec.values.copyOfRange(start * mels, (start + length) * mels)
            OnnxTensor.createTensor(env, FloatBuffer.wrap(chunk), longArrayOf(1, length.toLong(), mels.toLong()))
                .use { tensor ->
                    session.run(mapOf(inputName to tensor)).use { out ->
                        val beat = (out.get(0).value as Array<FloatArray>)[0]
                        val down = (out.get(1).value as Array<FloatArray>)[0]
                        val from = if (start == 0) 0 else BORDER_FRAMES
                        val to = if (start + length >= spec.frames) length else length - BORDER_FRAMES
                        for (i in from until to) {
                            val t = start + i
                            if (t >= beatOut.size) break
                            beatOut[t] = beat[i]
                            downOut[t] = down[i]
                        }
                    }
                }
            if (start + length >= spec.frames) break
            start += stride
        }
        true
    }.getOrDefault(false)

    fun release() {
        synchronized(lock) {
            runCatching { session?.close() }
            session = null
        }
    }

    companion object {
        const val CHUNK_FRAMES = 1500
        const val BORDER_FRAMES = 6
        private const val PEAK_WINDOW = 7
        private const val MIN_BEATS = 6
        private const val MIN_BPM = 40.0
        private const val MAX_BPM = 220.0

        fun pickPeaks(logits: FloatArray): List<Double> {
            val half = PEAK_WINDOW / 2
            val raw = ArrayList<Int>()
            for (i in logits.indices) {
                if (logits[i] <= 0f) continue
                var isMax = true
                for (o in -half..half) {
                    val j = i + o
                    if (j < 0 || j >= logits.size) continue
                    if (logits[j] > logits[i]) { isMax = false; break }
                }
                if (isMax) raw += i
            }
            val merged = ArrayList<Int>()
            var i = 0
            while (i < raw.size) {
                var mean = raw[i].toDouble()
                var count = 1
                while (i + 1 < raw.size && raw[i + 1] - mean <= 1) {
                    i++; count++
                    mean += (raw[i] - mean) / count
                }
                merged += mean.roundToInt()
                i++
            }
            return merged.map { f ->
                if (f <= 0 || f + 1 >= logits.size) return@map f.toDouble()
                val l = logits[f - 1].toDouble()
                val c = logits[f].toDouble()
                val r = logits[f + 1].toDouble()
                val d = l - 2 * c + r
                if (abs(d) <= 1e-9) f.toDouble() else f + (0.5 * (l - r) / d).coerceIn(-0.5, 0.5)
            }
        }

        private fun median(v: List<Double>): Double =
            if (v.isEmpty()) 0.0 else v.sorted()[v.size / 2]

        fun tempoFromBeats(beats: DoubleArray): Double {
            if (beats.size < MIN_BEATS) return 0.0
            val gaps = (1 until beats.size).map { beats[it] - beats[it - 1] }
            val rough = median(gaps)
            if (rough <= 0) return 0.0
            val kept = gaps.filter { abs(it - rough) <= rough * 0.2 }
            val interval = median(if (kept.size >= 4) kept else gaps)
            if (interval <= 0) return 0.0
            val bpm = 60.0 / interval
            return if (bpm in MIN_BPM..MAX_BPM) bpm else 0.0
        }

        private fun confidence(beats: DoubleArray, peakLogits: List<Double>): Double {
            if (beats.size < MIN_BEATS) return 0.0
            val gaps = (1 until beats.size).map { beats[it] - beats[it - 1] }
            val interval = median(gaps)
            if (interval <= 0) return 0.0
            val regular = gaps.count { abs(it - interval) <= interval * 0.1 }.toDouble() / gaps.size
            val strength = 1.0 / (1.0 + exp(-(median(peakLogits) - 0.5)))
            return max(0.0, min(0.95, 0.35 + 0.4 * regular + 0.25 * strength))
        }
    }
}
