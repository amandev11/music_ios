package com.aurora.music.audio.analysis

import kotlin.math.floor
import kotlin.math.max

data class BeatPulse(
    /** 0..1 position inside the current beat (0 = on the beat). */
    val phase: Float = 0f,
    /** 0-based beat inside the bar, or -1 when the bar position is unknown. */
    val beatInBar: Int = -1,
    val beatsPerBar: Int = 4,
    val bpm: Float = 0f,
    val confidence: Float = 0f,
    /** Monotonic beat counter; changes exactly when a new beat starts. */
    val beatCount: Long = -1L,
) {
    val isLocked: Boolean get() = bpm > 0f && confidence > 0.4f
    val isDownbeat: Boolean get() = beatInBar == 0

    /** Sharp attack, exponential release; 1 on the beat. */
    val envelope: Float get() = if (!isLocked) 0f else kotlin.math.exp(-phase * 4.5f)
}

/** Media-time beat grid; [pulseAt] is lock-free and safe to call from the UI thread each frame. */
class BeatClock {

    private class Live(
        val beatsMs: DoubleArray,
        val downbeatsMs: DoubleArray,
        val bpm: Double,
        val confidence: Double,
        val beatsPerBar: Int,
    )

    @Volatile private var live: Live? = null

    fun clear() {
        live = null
    }

    fun update(grid: BeatGrid, originMs: Double, windowStartSec: Double) {
        val offset = originMs + windowStartSec * 1000.0
        live = Live(
            beatsMs = DoubleArray(grid.beatsSec.size) { offset + grid.beatsSec[it] * 1000.0 },
            downbeatsMs = DoubleArray(grid.downbeatsSec.size) { offset + grid.downbeatsSec[it] * 1000.0 },
            bpm = grid.bpm,
            confidence = grid.confidence,
            beatsPerBar = grid.beatsPerBar,
        )
    }

    val bpm: Float get() = live?.bpm?.toFloat() ?: 0f
    val confidence: Float get() = live?.confidence?.toFloat() ?: 0f

    fun pulseAt(positionMs: Long): BeatPulse {
        val g = live ?: return BeatPulse()
        val beats = g.beatsMs
        if (beats.isEmpty()) return BeatPulse()
        val interval = 60_000.0 / g.bpm
        val p = positionMs.toDouble()

        // Index of the last observed beat <= p (or -1).
        var lo = 0
        var hi = beats.size - 1
        var idx = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (beats[mid] <= p) { idx = mid; lo = mid + 1 } else hi = mid - 1
        }

        val anchor: Double
        val steps: Long
        if (idx < 0) {
            anchor = beats[0]
            steps = floor((p - anchor) / interval).toLong()
        } else {
            anchor = beats[idx]
            // Within the observed grid snap to the real beat; beyond it extrapolate by tempo.
            val next = beats.getOrNull(idx + 1)
            steps = if (next != null) 0L else floor((p - anchor) / interval).toLong()
        }
        val beatStart = if (idx >= 0 && steps == 0L) anchor else anchor + steps * interval
        val length = if (idx >= 0 && steps == 0L) (beats.getOrNull(idx + 1)?.minus(anchor) ?: interval) else interval
        val phase = ((p - beatStart) / max(length, 1.0)).coerceIn(0.0, 0.999)

        var beatInBar = -1
        val downs = g.downbeatsMs
        if (downs.isNotEmpty()) {
            val ref = downs.lastOrNull { it <= beatStart + interval * 0.25 } ?: downs.first()
            val n = Math.round((beatStart - ref) / interval).toInt()
            beatInBar = ((n % g.beatsPerBar) + g.beatsPerBar) % g.beatsPerBar
        }
        val count = Math.round((beatStart - beats[0]) / interval)
        return BeatPulse(
            phase = phase.toFloat(),
            beatInBar = beatInBar,
            beatsPerBar = g.beatsPerBar,
            bpm = g.bpm.toFloat(),
            confidence = g.confidence.toFloat(),
            beatCount = count,
        )
    }
}
