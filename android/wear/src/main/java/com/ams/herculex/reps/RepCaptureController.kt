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

/** One raw accelerometer sample. Held in memory only; never persisted. */
data class RepSample(val tMs: Long, val x: Float, val y: Float, val z: Float)

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
interface RepSensorGateway {
    /**
     * @return the sensor label actually registered (`"linear_acceleration"`
     *         or `"accelerometer"`), or null when neither sensor exists.
     */
    fun registerListener(onSample: (Long, Float, Float, Float) -> Unit): String?

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

    val isCapturing: Boolean get() = captureId != null

    /** Non-authoritative. Drives the watch display and the haptic tick only. */
    val provisionalCount: Int get() = counter.count

    fun start(
        exerciseSlug: String,
        captureId: String = UUID.randomUUID().toString(),
    ): StartResult {
        if (isCapturing) return StartRefusal.AlreadyCapturing
        if (batteryLevelPercent() < MIN_BATTERY_PERCENT) return StartRefusal.LowBattery

        val registeredType = sensors.registerListener(::onSensorSample) ?: return StartRefusal.NoSensor

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

    private fun onSensorSample(tMs: Long, x: Float, y: Float, z: Float) {
        val activeCaptureId = captureId ?: return
        if (pollCap()) return

        if (counter.onSample(tMs, x, y, z)) {
            onProvisionalRep(counter.count)
        }

        val sample = RepSample(tMs, x, y, z)
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
            samples.put(
                JSONObject()
                    .put("tMs", sample.tMs)
                    .put("x", sample.x.toDouble())
                    .put("y", sample.y.toDouble())
                    .put("z", sample.z.toDouble()),
            )
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

        const val REASON_USER = "user"
        const val REASON_CAP = "cap"
        const val REASON_BATTERY = "battery"
        const val REASON_BACKGROUND = "background"
        const val REASON_DESTROY = "destroy"

        const val SENSOR_LINEAR_ACCELERATION = "linear_acceleration"
        const val SENSOR_ACCELEROMETER = "accelerometer"
    }
}

/**
 * The real [RepSensorGateway]: `TYPE_LINEAR_ACCELERATION` at
 * `SENSOR_DELAY_GAME` (~50 Hz), falling back to `TYPE_ACCELEROMETER` when the
 * linear sensor is absent. Which one was used is reported in the
 * `MESSAGE_REP_CAPTURE_START` payload, because the two are not
 * interchangeable for calibration.
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

    override fun registerListener(onSample: (Long, Float, Float, Float) -> Unit): String? {
        unregisterListener()

        val linear = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        val sensor = linear ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return null
        val label = if (linear != null) {
            RepCaptureController.SENSOR_LINEAR_ACCELERATION
        } else {
            RepCaptureController.SENSOR_ACCELEROMETER
        }

        val eventListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                onSample(
                    event.timestamp / 1_000_000L,
                    event.values[0],
                    event.values[1],
                    event.values[2],
                )
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        val thread = HandlerThread("rep-capture-sensor").apply { start() }
        val registered = sensorManager.registerListener(
            eventListener,
            sensor,
            SensorManager.SENSOR_DELAY_GAME,
            Handler(thread.looper),
        )
        if (!registered) {
            thread.quitSafely()
            return null
        }

        sensorThread = thread
        listener = eventListener
        return label
    }

    override fun unregisterListener() {
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null
        sensorThread?.quitSafely()
        sensorThread = null
    }
}
