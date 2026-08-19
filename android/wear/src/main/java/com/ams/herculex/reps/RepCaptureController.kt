package com.ams.herculex.reps

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import com.ams.herculex.sync.WearSyncPaths
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * One synchronised inertial sample. Held in memory only; never persisted.
 *
 * [x], [y], [z] are linear acceleration in m/s² and are always present — they
 * are the stream's clock, and every other channel is attached to whichever
 * linear-acceleration event it arrived nearest to.
 *
 * The gravity ([gx], [gy], [gz]) and gyroscope ([rx], [ry], [rz]) channels are
 * nullable because not every watch has all three sensors, and because a
 * capture may begin before the slower sensors have delivered their first
 * event. Null means "not measured", which the phone's detector treats as an
 * absent channel — never as a zero reading, since zero is a legitimate value
 * meaning "perfectly level" or "not rotating".
 *
 * Gravity is what makes a slow rep countable at all: linear acceleration
 * amplitude falls with the square of cadence, so a 3-second curl is
 * indistinguishable from noise in [x]/[y]/[z] while still rotating the forearm
 * through 60°+, which the gravity direction tracks at any tempo.
 */
data class RepSample(
    val tMs: Long,
    val x: Float,
    val y: Float,
    val z: Float,
    val gx: Float? = null,
    val gy: Float? = null,
    val gz: Float? = null,
    val rx: Float? = null,
    val ry: Float? = null,
    val rz: Float? = null,
)

/** Outcome of [RepCaptureController.start]. */
sealed class StartResult {
    data class Started(val captureId: String, val sensorType: String) : StartResult()
}

/**
 * A typed refusal. `start()` returns one of these *instead of* registering a
 * listener, so a refusal can never leave the sensor running (T-10-10).
 */
sealed class StartRefusal : StartResult() {
    /** Battery below [RepCaptureController.MIN_BATTERY_PERCENT]. */
    object LowBattery : StartRefusal()

    /** Neither linear acceleration nor a plain accelerometer exists on this device. */
    object NoSensor : StartRefusal()

    /** A capture is already running; the caller must stop it first. */
    object AlreadyCapturing : StartRefusal()
}

/**
 * The sensor seam. [SensorManager] is an abstract framework class whose
 * `registerListenerImpl` is not implemented in the unit-test `android.jar`,
 * so it cannot be subclassed or stubbed in a JVM test. Injecting this
 * narrower gateway instead keeps the register/unregister balance — the whole
 * point of [RepCaptureControllerTest] — provably testable.
 */
/**
 * How hard the sensors are being driven.
 *
 * Running three sensors at 50 Hz with no batching for a whole workout is what
 * a continuous, tap-free tracker would cost if it had one mode. Most of a
 * workout is rest, so most of that is wasted — this is the axis that makes
 * always-on affordable.
 */
enum class CaptureRate {
    /**
     * Rest. One sensor, ~12.5 Hz, with a multi-second hardware FIFO latency so
     * the application processor stays asleep between bursts and only wakes to
     * drain the queue. Enough to notice that work has started, and nothing
     * more — the samples are still kept, because the first reps of a set
     * happen before escalation completes.
     */
    WATCHING,

    /**
     * Working. All three sensors at `SENSOR_DELAY_GAME` (~50 Hz) with zero
     * report latency, because the on-wrist provisional count has to tick
     * during the set rather than arrive in a burst afterwards.
     */
    CAPTURING,
}

interface RepSensorGateway {
    /**
     * Emits one fused [RepSample] per primary-sensor event.
     *
     * [rate] selects both the sampling rate and which sensors are attached:
     * the secondary channels are registered only in [CaptureRate.CAPTURING],
     * because the gyroscope in particular draws several times the
     * accelerometer's current and carries nothing the escalation decision
     * needs.
     *
     * @return the sensor label actually registered (`"linear_acceleration"`
     *         or `"accelerometer"`), or null when neither sensor exists. The
     *         label describes the *primary* channel only; whether gravity and
     *         gyroscope were also available is carried per sample, because a
     *         watch can lose one mid-capture.
     */
    fun registerListener(
        rate: CaptureRate = CaptureRate.CAPTURING,
        onSample: (RepSample) -> Unit,
    ): String?

    fun unregisterListener()
}

/** The MessageClient seam. @return true when delivered to at least one node. */
interface RepMessageSender {
    fun send(path: String, payloadJson: String): Boolean
}

/**
 * Owns the accelerometer for the duration of one set: sensor lifecycle, a
 * 300-second ring buffer that survives a watch↔phone dropout, ~1 s batching
 * onto the Data Layer, a battery gate, a 5-minute hard cap, and balanced
 * teardown across every exit path.
 *
 * Hosted by the existing `WorkoutOngoingService`, which is already declared
 * as a health foreground service — this class starts **no** foreground
 * service of its own and needs no new manifest permission: the accelerometer
 * is not a `BODY_SENSORS` sensor and `HIGH_SAMPLING_RATE_SENSORS` only
 * applies above 200 Hz.
 *
 * All five teardown paths unregister exactly once:
 * set end ([stop] with `"user"`), the 5-minute cap (`"cap"`), app background
 * ([onAppBackgrounded]), service destroy ([onServiceDestroyed]) and the
 * battery refusal (which never registers, so the count trivially balances).
 * [stop] is idempotent.
 */
class RepCaptureController(
    private val sensors: RepSensorGateway,
    private val sender: RepMessageSender,
    private val batteryLevelPercent: () -> Int,
    private val clock: () -> Long,
    private val counter: ProvisionalRepCounter = ProvisionalRepCounter(),
    private val onProvisionalRep: (Int) -> Unit = {},
) {

    private var captureId: String? = null
    private var sensorType: String = ""
    private var startedAtMs: Long = 0L
    private var seq: Int = 0
    private var batchCount: Int = 0

    /** Reentrancy guard: makes [stop] idempotent even if teardown re-enters. */
    private var stopping: Boolean = false

    /** 300 s of raw samples, in memory only, oldest evicted first. */
    private val ringBuffer = ArrayDeque<RepSample>()
    private val currentBatch = mutableListOf<RepSample>()
    private var batchOpenedAtMs: Long = 0L

    /** Batches whose send failed; retried on the next connectivity callback. */
    private val undelivered = ArrayDeque<Pair<String, String>>()

    /** Non-null while watching: the exercise a gate-driven set would open on. */
    private var watchingSlug: String? = null

    /**
     * Low-rate samples seen since the last quiet period, carried into a
     * gate-opened capture so its first reps are not lost.
     *
     * A set opens [MotionGate.SUSTAINED_MS] after motion began, and a rep can
     * easily complete inside that. Without a pre-roll the phone would receive
     * a trace whose first rep is half missing, count one fewer, and be right
     * to — the samples genuinely were not there.
     */
    private val preRoll = ArrayDeque<RepSample>()

    private val gate = MotionGate(clock)

    val isCapturing: Boolean get() = captureId != null

    /** True while the low-rate gate is armed and no set is open. */
    val isWatching: Boolean get() = watchingSlug != null && captureId == null

    /** Non-authoritative. Drives the watch display and the haptic tick only. */
    val provisionalCount: Int get() = counter.count

    /**
     * Arms the low-rate gate for [exerciseSlug]. Sets then open and close on
     * their own as the user works.
     *
     * This is the tap-free path, and it is layered *on top of* [start]/[stop]
     * rather than replacing them: an escalation calls [start] and a
     * de-escalation calls [stop], so the phone receives exactly the same
     * `capture_start` / `samples` / `capture_end` sequence it receives from a
     * manual tap. Nothing on the wire, in the phone's capture service, or in
     * its detector had to learn about automatic mode.
     */
    fun startWatching(exerciseSlug: String): StartResult {
        if (isCapturing) return StartRefusal.AlreadyCapturing
        if (batteryLevelPercent() < MIN_BATTERY_PERCENT) return StartRefusal.LowBattery

        stopWatching()
        val registeredType = sensors.registerListener(CaptureRate.WATCHING, ::onWatchingSample)
            ?: return StartRefusal.NoSensor

        watchingSlug = exerciseSlug
        sensorType = registeredType
        gate.reset()
        preRoll.clear()
        return StartResult.Started(WATCHING_CAPTURE_ID, registeredType)
    }

    /** Disarms the gate. Does not end a set that is currently open. */
    fun stopWatching() {
        if (watchingSlug == null) return
        watchingSlug = null
        gate.reset()
        preRoll.clear()
        if (!isCapturing) sensors.unregisterListener()
    }

    /**
     * The exercise a gate-opened set will be attributed to. Set as the user
     * moves through the workout so an automatic capture lands on the right row.
     */
    fun onExerciseChanged(exerciseSlug: String) {
        if (isCapturing) stop(REASON_EXERCISE_CHANGED)
        if (watchingSlug != null) watchingSlug = exerciseSlug
    }

    /**
     * Low-rate sample handler. Feeds the gate, keeps a pre-roll, and
     * escalates on a state change.
     */
    private fun onWatchingSample(sample: RepSample) {
        val slug = watchingSlug ?: return
        if (isCapturing) return

        preRoll.addLast(sample)
        while (preRoll.isNotEmpty() && sample.tMs - preRoll.first().tMs > PRE_ROLL_MS) {
            preRoll.removeFirst()
        }

        if (!gate.onSample(sample.tMs, sample.x, sample.y, sample.z)) return
        if (!gate.isActive) return

        // Escalate. start() re-registers at the full rate, which replaces this
        // listener — the gateway's unregister detaches every sensor at once,
        // so the register/unregister balance stays one-to-one.
        val carried = preRoll.toList()
        preRoll.clear()
        if (start(slug) is StartResult.Started) {
            // Seed the new capture with what the low rate already saw.
            for (earlier in carried) {
                ringBuffer.addLast(earlier)
                currentBatch += earlier
            }
            if (carried.isNotEmpty()) batchOpenedAtMs = carried.first().tMs
        }
    }

    fun start(
        exerciseSlug: String,
        captureId: String = UUID.randomUUID().toString(),
    ): StartResult {
        if (isCapturing) return StartRefusal.AlreadyCapturing
        if (batteryLevelPercent() < MIN_BATTERY_PERCENT) return StartRefusal.LowBattery

        val registeredType = sensors.registerListener(CaptureRate.CAPTURING, ::onSensorSample)
            ?: return StartRefusal.NoSensor

        this.captureId = captureId
        sensorType = registeredType
        startedAtMs = clock()
        seq = 0
        batchCount = 0
        batchOpenedAtMs = Long.MIN_VALUE
        ringBuffer.clear()
        currentBatch.clear()
        undelivered.clear()
        counter.reset()

        sender.send(
            WearSyncPaths.MESSAGE_REP_CAPTURE_START,
            JSONObject()
                .put("captureId", captureId)
                .put("exerciseSlug", exerciseSlug)
                .put("sensorType", sensorType)
                .put("startedAtMs", startedAtMs)
                .toString(),
        )

        return StartResult.Started(captureId, sensorType)
    }

    /**
     * Stops capture, flushes everything still buffered and emits
     * `MESSAGE_REP_CAPTURE_END`. Idempotent — a second call unregisters
     * nothing and does not send a second end message.
     */
    fun stop(reason: String) {
        val activeCaptureId = captureId ?: return
        if (stopping) return
        stopping = true

        // Unregister first, so no further sample can arrive while we flush.
        sensors.unregisterListener()
        captureId = null

        flushBatch(activeCaptureId)
        retryUndelivered()
        stopping = false

        sender.send(
            WearSyncPaths.MESSAGE_REP_CAPTURE_END,
            JSONObject()
                .put("captureId", activeCaptureId)
                .put("endedAtMs", clock())
                .put("batchCount", batchCount)
                .put("stoppedReason", reason)
                // NON-AUTHORITATIVE by contract — the phone's Dart detector
                // owns the proposed count (T-10-09). Present only so the
                // phone can spot a >1-rep disagreement and drop the
                // confidence band one step.
                .put("provisionalCount", counter.count)
                .toString(),
        )

        // Raw samples are discarded at set end — they are never written
        // anywhere (REP-04).
        ringBuffer.clear()
        currentBatch.clear()
        undelivered.clear()

        // De-escalate. A set that ended while the gate is still armed drops
        // back to the low rate rather than leaving three sensors running at
        // 50 Hz through the rest period — which is the entire point of having
        // two rates. Teardown reasons that mean "the workout is over"
        // (background, destroy) disarm instead.
        if (watchingSlug != null && reason != REASON_BACKGROUND && reason != REASON_DESTROY) {
            gate.reset()
            preRoll.clear()
            sensors.registerListener(CaptureRate.WATCHING, ::onWatchingSample)
        } else {
            watchingSlug = null
        }
    }

    /** App went to background. */
    fun onAppBackgrounded() = stop(REASON_BACKGROUND)

    /** Hosting service is being destroyed. */
    fun onServiceDestroyed() = stop(REASON_DESTROY)

    /**
     * Checks the 5-minute hard cap against the injected clock. Called on
     * every sample, and exposed so the host can poll it even if the sensor
     * has gone quiet.
     *
     * @return true if this call stopped the capture.
     */
    fun pollCap(): Boolean {
        if (!isCapturing) return false
        if (clock() - startedAtMs < MAX_CAPTURE_MS) return false
        stop(REASON_CAP)
        return true
    }

    /** Retries batches held back by a failed send (watch↔phone dropout). */
    fun onConnectivityAvailable() {
        retryUndelivered()
    }

    private fun onSensorSample(sample: RepSample) {
        val activeCaptureId = captureId ?: return
        if (pollCap()) return

        // The provisional wrist counter stays on linear acceleration alone. It
        // is display-and-haptic only and deliberately dumb; giving it the
        // gravity channel would make it a second detector to keep correct,
        // and correctness lives in the phone's Dart engine.
        if (counter.onSample(sample.tMs, sample.x, sample.y, sample.z)) {
            onProvisionalRep(counter.count)
        }

        val tMs = sample.tMs
        ringBuffer.addLast(sample)
        while (ringBuffer.isNotEmpty() && tMs - ringBuffer.first().tMs > RING_BUFFER_MS) {
            ringBuffer.removeFirst()
        }

        if (currentBatch.isEmpty()) {
            batchOpenedAtMs = tMs
        }
        currentBatch += sample

        if (tMs - batchOpenedAtMs >= BATCH_MS) {
            flushBatch(activeCaptureId)
        }
    }

    private fun flushBatch(activeCaptureId: String) {
        if (currentBatch.isEmpty()) return

        val samples = JSONArray()
        for (sample in currentBatch) {
            val json = JSONObject()
                .put("tMs", sample.tMs)
                .put("x", sample.x.toDouble())
                .put("y", sample.y.toDouble())
                .put("z", sample.z.toDouble())
            // Absent channels are omitted rather than sent as null or zero:
            // org.json turns a null value into JSONObject.NULL, and the phone
            // must be able to tell "not measured" from "measured as zero".
            sample.gx?.let { json.put("gx", it.toDouble()) }
            sample.gy?.let { json.put("gy", it.toDouble()) }
            sample.gz?.let { json.put("gz", it.toDouble()) }
            sample.rx?.let { json.put("rx", it.toDouble()) }
            sample.ry?.let { json.put("ry", it.toDouble()) }
            sample.rz?.let { json.put("rz", it.toDouble()) }
            samples.put(json)
        }
        currentBatch.clear()

        val payload = JSONObject()
            .put("captureId", activeCaptureId)
            // Monotonic per capture, preserved end to end so the phone can
            // report a gap rather than silently concatenating across a
            // dropout.
            .put("seq", seq)
            .put("sensorType", sensorType)
            .put("samples", samples)
            .toString()
        seq += 1
        batchCount += 1

        if (!sender.send(WearSyncPaths.MESSAGE_REP_SAMPLES, payload)) {
            undelivered.addLast(WearSyncPaths.MESSAGE_REP_SAMPLES to payload)
            while (undelivered.size > MAX_UNDELIVERED_BATCHES) {
                undelivered.removeFirst()
            }
        }
    }

    private fun retryUndelivered() {
        if (undelivered.isEmpty()) return
        val pending = undelivered.toList()
        undelivered.clear()
        for ((path, payload) in pending) {
            if (!sender.send(path, payload)) {
                // Order is preserved — held batches are never reordered or
                // coalesced, so `seq` stays meaningful.
                undelivered.addLast(path to payload)
            }
        }
    }

    companion object {
        /** Capture is refused below this battery level (10-CONTEXT:96). */
        const val MIN_BATTERY_PERCENT = 15

        /** Hard cap per set (10-CONTEXT:97). */
        const val MAX_CAPTURE_MS = 5L * 60L * 1000L

        /** Ring buffer depth — survives a watch↔phone dropout (10-CONTEXT:46). */
        const val RING_BUFFER_MS = 300L * 1000L

        /** Roughly one second of samples per MESSAGE_REP_SAMPLES. */
        const val BATCH_MS = 1000L

        /** 300 s at ~1 s per batch — matches the ring buffer depth. */
        const val MAX_UNDELIVERED_BATCHES = 300

        /**
         * How much low-rate history is carried into a gate-opened capture.
         * Comfortably longer than [MotionGate.SUSTAINED_MS] plus one slow rep.
         */
        const val PRE_ROLL_MS = 6000L

        /** Reported by [startWatching]; no capture exists yet. */
        const val WATCHING_CAPTURE_ID = "watching"

        const val REASON_USER = "user"
        const val REASON_AUTO = "auto"
        const val REASON_EXERCISE_CHANGED = "exercise_changed"
        const val REASON_CAP = "cap"
        const val REASON_BATTERY = "battery"
        const val REASON_BACKGROUND = "background"
        const val REASON_DESTROY = "destroy"

        const val SENSOR_LINEAR_ACCELERATION = "linear_acceleration"
        const val SENSOR_ACCELEROMETER = "accelerometer"
    }
}

/**
 * The real [RepSensorGateway]. Registers up to three sensors at
 * `SENSOR_DELAY_GAME` (~50 Hz) and fuses them into one sample stream:
 *
 *  * **`TYPE_LINEAR_ACCELERATION`** (falling back to `TYPE_ACCELEROMETER`) —
 *    the primary channel and the stream's clock. Which one was used is
 *    reported in the `MESSAGE_REP_CAPTURE_START` payload, because the two are
 *    not interchangeable for calibration.
 *  * **`TYPE_GRAVITY`** — the channel that makes slow, heavy reps countable.
 *    Optional: absent on a few low-end watches, in which case the phone
 *    derives a worse tilt estimate by low-passing a raw accelerometer trace,
 *    or has no tilt channel at all on a linear-acceleration trace.
 *  * **`TYPE_GYROSCOPE`** — separates rotation from translation and sees
 *    rotation about the gravity axis, which gravity alone cannot.
 *
 * ## Fusion
 *
 * The three sensors deliver independently and are not sample-aligned. Rather
 * than interpolating on the watch — which would mean buffering, and a second
 * place where resampling logic could disagree with the phone's — the gateway
 * holds the latest reading from each secondary sensor and attaches it to the
 * next primary event. At 50 Hz the worst-case staleness is one sensor period,
 * roughly 20 ms, which is two orders of magnitude below the shortest rep this
 * detector will accept. All real resampling happens once, on the phone, on a
 * fixed grid.
 *
 * No new manifest permission is needed for any of the three: none is a
 * `BODY_SENSORS` sensor, and `HIGH_SAMPLING_RATE_SENSORS` only applies above
 * 200 Hz.
 */
class AndroidRepSensorGateway(
    private val sensorManager: SensorManager,
) : RepSensorGateway {

    private var listener: SensorEventListener? = null

    /**
     * Samples are delivered on a dedicated thread rather than the main
     * looper: the batch send is a blocking Data Layer call, and the watch UI
     * is rendering a live set logger while it runs.
     */
    private var sensorThread: HandlerThread? = null

    // Latest secondary readings, written and read only on the sensor thread.
    @Volatile private var gravity: FloatArray? = null
    @Volatile private var gyro: FloatArray? = null

    override fun registerListener(
        rate: CaptureRate,
        onSample: (RepSample) -> Unit,
    ): String? {
        unregisterListener()

        val linear = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        val primary = linear ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return null
        val label = if (linear != null) {
            RepCaptureController.SENSOR_LINEAR_ACCELERATION
        } else {
            RepCaptureController.SENSOR_ACCELEROMETER
        }

        gravity = null
        gyro = null

        val samplingUs = when (rate) {
            CaptureRate.WATCHING -> WATCHING_SAMPLING_US
            CaptureRate.CAPTURING -> SensorManager.SENSOR_DELAY_GAME
        }
        val latencyUs = when (rate) {
            CaptureRate.WATCHING -> WATCHING_LATENCY_US
            CaptureRate.CAPTURING -> 0
        }

        val eventListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                when (event.sensor?.type) {
                    Sensor.TYPE_GRAVITY -> {
                        gravity = floatArrayOf(event.values[0], event.values[1], event.values[2])
                    }
                    Sensor.TYPE_GYROSCOPE -> {
                        gyro = floatArrayOf(event.values[0], event.values[1], event.values[2])
                    }
                    else -> {
                        // The primary sensor drives the stream.
                        val g = gravity
                        val r = gyro
                        onSample(
                            RepSample(
                                tMs = event.timestamp / 1_000_000L,
                                x = event.values[0],
                                y = event.values[1],
                                z = event.values[2],
                                gx = g?.get(0), gy = g?.get(1), gz = g?.get(2),
                                rx = r?.get(0), ry = r?.get(1), rz = r?.get(2),
                            ),
                        )
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        val thread = HandlerThread("rep-capture-sensor").apply { start() }
        val handler = Handler(thread.looper)

        // The five-argument overload is what enables the hardware FIFO. A
        // non-zero maxReportLatencyUs lets the sensor hub buffer on-chip and
        // deliver in bursts, which is the whole battery saving — the
        // application processor stays asleep between them. Event timestamps
        // are stamped by the hub, so batching delays delivery without
        // distorting the timebase the phone resamples on.
        val registered = sensorManager.registerListener(
            eventListener,
            primary,
            samplingUs,
            latencyUs,
            handler,
        )
        if (!registered) {
            thread.quitSafely()
            return null
        }

        // Secondary sensors are best-effort. A failure to register either one
        // leaves that channel null for the whole capture and costs the phone a
        // detection channel — it must never fail the capture, because the
        // primary channel alone still counts every hands-anchored movement.
        //
        // Both are unregistered by the single unregisterListener(eventListener)
        // call below, which removes the listener from *all* sensors it is
        // registered for — so the register/unregister balance the teardown
        // tests assert stays one-to-one however many sensors were attached.
        // Only while working. Gravity and gyroscope contribute nothing to the
        // escalation decision, and the gyroscope is the most expensive of the
        // three by a wide margin — attaching it during rest would undo most of
        // what the low rate buys.
        if (rate == CaptureRate.CAPTURING) {
            sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY)?.let {
                sensorManager.registerListener(eventListener, it, samplingUs, 0, handler)
            }
            sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let {
                sensorManager.registerListener(eventListener, it, samplingUs, 0, handler)
            }
        }

        sensorThread = thread
        listener = eventListener
        return label
    }

    companion object {
        /** ~12.5 Hz, in microseconds between samples. */
        const val WATCHING_SAMPLING_US = 80_000

        /**
         * ~5 s of on-chip buffering while resting. Bounded by the hub's FIFO
         * depth — a hub that cannot hold this much silently delivers sooner,
         * which costs battery but breaks nothing.
         */
        const val WATCHING_LATENCY_US = 5_000_000
    }

    override fun unregisterListener() {
        // Unregisters from every sensor this listener was attached to.
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null
        gravity = null
        gyro = null
        sensorThread?.quitSafely()
        sensorThread = null
    }
}
