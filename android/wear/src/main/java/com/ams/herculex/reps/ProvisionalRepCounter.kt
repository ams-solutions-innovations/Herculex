package com.ams.herculex.reps

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * The live on-wrist rep counter. It drives the number shown on the watch and
 * the haptic tick, and **nothing else**.
 *
 * Deliberately simpler than the authoritative Dart detector on the phone: no
 * calibration, no feature extraction, no confidence model, no per-rep
 * bookkeeping. Its output is **never authoritative and never persisted** — it
 * crosses the bridge only as the `provisionalCount` field on
 * `MESSAGE_REP_CAPTURE_END`, which 10-03b treats as non-authoritative by
 * contract (10-CONTEXT "Where detection runs").
 *
 * Algorithm: adaptive-threshold *cycle* counting over the low-passed
 * acceleration magnitude. A rep is only counted on a closed
 * trough → peak → trough excursion whose peak clears both an absolute
 * amplitude floor and an adaptive multiple of the recent deviation, and only
 * after a refractory floor has elapsed. Counting bare peaks is what makes a
 * walk to the water fountain register as reps; the closed-cycle requirement
 * plus the amplitude gate is what stops it (same reasoning as the Dart
 * detector).
 *
 * Holds no persistence, no MessageClient reference and no Android dependency,
 * so it is a plain JVM unit under test.
 */
class ProvisionalRepCounter(
    private val minAmplitude: Float = MIN_AMPLITUDE_MS2,
    private val refractoryMs: Long = REFRACTORY_MS,
) {

    /** Reps counted since construction or the last [reset]. Provisional. */
    var count: Int = 0
        private set

    private var smoothed: Float = Float.NaN
    private var baseline: Float = Float.NaN
    private var deviation: Float = 0f

    /** True once the signal has sat below the trough threshold, i.e. a new cycle may open. */
    private var armed: Boolean = false
    private var inPeak: Boolean = false
    private var peakExcursion: Float = 0f
    private var lastRepAtMs: Long = Long.MIN_VALUE

    /**
     * Feed one raw accelerometer sample.
     *
     * @return true on the tick where a rep cycle closed, so the caller can
     *         fire the haptic. False on every other tick.
     */
    fun onSample(tMs: Long, x: Float, y: Float, z: Float): Boolean {
        val magnitude = sqrt(x * x + y * y + z * z)

        if (smoothed.isNaN()) {
            smoothed = magnitude
            baseline = magnitude
            return false
        }

        smoothed += SMOOTH_ALPHA * (magnitude - smoothed)
        val centered = smoothed - baseline

        // Slow trackers, updated *after* centring so a rep's own excursion
        // does not immediately erase itself from the threshold it must clear.
        baseline += BASELINE_ALPHA * centered
        deviation += DEVIATION_ALPHA * (abs(centered) - deviation)

        val enterThreshold = max(minAmplitude, ADAPTIVE_FACTOR * deviation)
        val exitThreshold = enterThreshold * HYSTERESIS

        if (!inPeak) {
            if (centered < exitThreshold) {
                // Sitting in a trough — the next rise may open a cycle.
                armed = true
            }
            if (armed && centered >= enterThreshold) {
                inPeak = true
                peakExcursion = centered
            }
            return false
        }

        peakExcursion = max(peakExcursion, centered)
        if (centered >= exitThreshold) {
            return false
        }

        // Closed trough → peak → trough cycle.
        inPeak = false
        armed = true
        val amplitudeOk = peakExcursion >= enterThreshold
        val refractoryOk = lastRepAtMs == Long.MIN_VALUE || (tMs - lastRepAtMs) >= refractoryMs
        peakExcursion = 0f

        if (!amplitudeOk || !refractoryOk) {
            return false
        }

        lastRepAtMs = tMs
        count += 1
        return true
    }

    /** Clears the count and all filter state, ready for the next set. */
    fun reset() {
        count = 0
        smoothed = Float.NaN
        baseline = Float.NaN
        deviation = 0f
        armed = false
        inPeak = false
        peakExcursion = 0f
        lastRepAtMs = Long.MIN_VALUE
    }

    private companion object {
        /**
         * Absolute peak excursion, in m/s², below which nothing is ever
         * counted. This — not the adaptive term — is what makes walking
         * count exactly zero: the adaptive threshold would happily rescale
         * itself down to whatever noise floor it is handed.
         */
        const val MIN_AMPLITUDE_MS2 = 2.5f

        /** No two reps closer together than this. */
        const val REFRACTORY_MS = 500L

        /** Peak must also clear this multiple of the recent mean deviation. */
        const val ADAPTIVE_FACTOR = 1.8f

        /** Fraction of the enter threshold at which a cycle is considered closed. */
        const val HYSTERESIS = 0.35f

        /** ~60 ms low-pass at 50 Hz — removes sensor grit, keeps rep shape. */
        const val SMOOTH_ALPHA = 0.3f

        /** ~4 s baseline tracker: slow enough not to chase a single rep. */
        const val BASELINE_ALPHA = 0.005f

        /** ~2 s deviation tracker feeding the adaptive term. */
        const val DEVIATION_ALPHA = 0.01f
    }
}
