package com.ams.herculex.reps

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Decides, from a low-rate accelerometer stream, when the wrist has started
 * working and when it has stopped.
 *
 * ## Why this is on the watch and not the phone
 *
 * The phone owns segmentation — [SetSegmenter][/lib/features/reps/domain/set_segmenter.dart]
 * finds the real set boundaries over the full-rate trace, and it is the
 * authority. But something has to decide when to *turn the full rate on*, and
 * that decision cannot live on the phone: the phone can only see what the
 * watch already sent, so asking it would mean streaming at full rate all the
 * time to find out whether full rate was needed.
 *
 * So this is deliberately the cheaper, dumber of the two. Its job is not to be
 * right about where a set starts — the phone re-decides that from the samples,
 * with padding to spare. Its job is to be *early and cheap*: escalate on any
 * plausible working motion, and never miss one. A false escalation costs a few
 * seconds of gyroscope; a missed one costs the whole set.
 *
 * That asymmetry is why [ENTER_THRESHOLD] is low and [QUIET_MS] is generous.
 *
 * ## Why an absolute threshold
 *
 * The detector and the segmenter both learn their thresholds from the signal.
 * This one cannot: it runs at 12.5 Hz on a device that has been asleep, often
 * with no rest history at all (the workout just started), and it must decide
 * within a second. An absolute floor on gravity-removed magnitude is the only
 * thing available that early, and being wrong in the escalating direction is
 * cheap.
 *
 * Pure and allocation-free per sample: this runs on every sample of a
 * multi-hour capture.
 */
class MotionGate(
    private val clock: () -> Long,
) {

    /** Slow-moving gravity estimate, so magnitude can be de-trended in place. */
    private var baseline: Double = GRAVITY
    private var quietSinceMs: Long = -1
    private var activeSinceMs: Long = -1

    /** True once [onSample] has seen sustained motion and not yet seen quiet. */
    var isActive: Boolean = false
        private set

    fun reset() {
        baseline = GRAVITY
        quietSinceMs = -1
        activeSinceMs = -1
        isActive = false
    }

    /**
     * Feeds one low-rate sample.
     *
     * @return true when the gate *changed* state, so the caller re-registers
     *         the sensors at the new rate exactly once per transition rather
     *         than on every sample.
     */
    fun onSample(tMs: Long, x: Float, y: Float, z: Float): Boolean {
        val magnitude = sqrt((x * x + y * y + z * z).toDouble())

        // Single-pole low pass. At 12.5 Hz an alpha of 0.02 gives a time
        // constant near four seconds — slow enough that a set's own motion
        // does not get absorbed into the baseline and cancel itself out, which
        // is the same self-defeat the phone's segmenter documents.
        baseline += BASELINE_ALPHA * (magnitude - baseline)
        val excursion = abs(magnitude - baseline)

        if (excursion > ENTER_THRESHOLD) {
            quietSinceMs = -1
            if (!isActive) {
                if (activeSinceMs < 0) activeSinceMs = tMs
                if (tMs - activeSinceMs >= SUSTAINED_MS) {
                    isActive = true
                    return true
                }
            }
        } else {
            activeSinceMs = -1
            if (isActive) {
                if (quietSinceMs < 0) quietSinceMs = tMs
                if (tMs - quietSinceMs >= QUIET_MS) {
                    isActive = false
                    return true
                }
            }
        }
        return false
    }

    companion object {
        private const val GRAVITY = 9.81

        /**
         * m/s² of gravity-removed excursion that counts as motion.
         *
         * Well below a rep — walking clears it easily, and that is intended.
         * The cost of escalating for a walk is a few seconds of full-rate
         * sensing that the phone then reports as no set; the cost of a
         * threshold tuned to reject walking is missing the quiet first rep of
         * a heavy set.
         */
        const val ENTER_THRESHOLD = 1.0

        /** Motion must persist this long before escalating. */
        const val SUSTAINED_MS = 800L

        /**
         * Quiet must persist this long before dropping back to the low rate.
         *
         * Longer than the pause a grinding rep can produce at the sticking
         * point, so a hard set is not cut in half mid-rep. De-escalating early
         * loses samples; de-escalating late costs a little battery.
         */
        const val QUIET_MS = 8000L

        /** Baseline low-pass coefficient. */
        const val BASELINE_ALPHA = 0.02
    }
}
