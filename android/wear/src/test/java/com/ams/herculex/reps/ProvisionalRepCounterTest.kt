package com.ams.herculex.reps

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Plain JVM test — [ProvisionalRepCounter] has no Android dependency, so no
 * Robolectric runner is needed here (unlike the sync tests, which need a
 * Context for SharedPreferences).
 */
class ProvisionalRepCounterTest {

    private data class Sample(val tMs: Long, val x: Float, val y: Float, val z: Float)

    /**
     * A physically-shaped pull-up/dip trace on the linear-acceleration
     * magnitude: a large concentric bump, a pause at the top, then a much
     * smaller eccentric bump on the way down. The eccentric bump is
     * deliberately below the amplitude gate — a counter that counted bare
     * peaks would return 2x here.
     */
    private fun cleanCycles(
        cycles: Int,
        periodMs: Long = 1600L,
        peak: Float = 7f,
        sampleMs: Long = 20L,
    ): List<Sample> {
        val out = mutableListOf<Sample>()
        var t = 0L
        val total = cycles * periodMs
        while (t < total) {
            val phase = (t % periodMs).toDouble() / periodMs
            val value = when {
                phase < 0.35 -> peak * sin(PI * phase / 0.35).toFloat()
                phase < 0.55 -> 0f
                phase < 0.85 -> peak * 0.25f * sin(PI * (phase - 0.55) / 0.30).toFloat()
                else -> 0f
            }
            out += Sample(t, 0f, 0f, value)
            t += sampleMs
        }
        return out
    }

    /**
     * Walking to the water fountain: low-amplitude, ~500 ms cadence. The
     * watch must not buzz.
     */
    private fun walkingNoise(
        durationMs: Long = 30_000L,
        periodMs: Long = 500L,
        amplitude: Float = 0.6f,
        sampleMs: Long = 20L,
    ): List<Sample> {
        val out = mutableListOf<Sample>()
        var t = 0L
        while (t < durationMs) {
            val value = amplitude * abs(sin(PI * t.toDouble() / periodMs)).toFloat()
            out += Sample(t, 0f, 0f, value)
            t += sampleMs
        }
        return out
    }

    private fun feed(counter: ProvisionalRepCounter, samples: List<Sample>): Int {
        var ticks = 0
        for (s in samples) {
            if (counter.onSample(s.tMs, s.x, s.y, s.z)) ticks += 1
        }
        return ticks
    }

    @Test
    fun `counts eight clean cycles within one rep`() {
        val counter = ProvisionalRepCounter()
        val ticks = feed(counter, cleanCycles(cycles = 8))

        assertTrue(
            "expected 8 +/- 1 reps, got ${counter.count}",
            abs(counter.count - 8) <= 1,
        )
        assertEquals(
            "every true return must correspond to exactly one counted rep",
            counter.count,
            ticks,
        )
    }

    @Test
    fun `walking noise counts exactly zero`() {
        val counter = ProvisionalRepCounter()
        val ticks = feed(counter, walkingNoise())

        assertEquals("the watch must not buzz on a walk", 0, counter.count)
        assertEquals(0, ticks)
    }

    @Test
    fun `reset returns the count to zero`() {
        val counter = ProvisionalRepCounter()
        feed(counter, cleanCycles(cycles = 8))
        assertTrue(counter.count > 0)

        counter.reset()

        assertEquals(0, counter.count)
    }

    @Test
    fun `reset clears filter state so the next set counts independently`() {
        val counter = ProvisionalRepCounter()
        feed(counter, cleanCycles(cycles = 8))
        counter.reset()
        feed(counter, cleanCycles(cycles = 8))

        assertTrue(
            "expected 8 +/- 1 reps on the second set, got ${counter.count}",
            abs(counter.count - 8) <= 1,
        )
    }
}
