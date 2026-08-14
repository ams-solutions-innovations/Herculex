package com.ams.herculex.reps

import com.ams.herculex.sync.WearSyncPaths
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The automated counterpart to UAT rows 6, 7 and 9 (battery gate, listener
 * balance, 5-minute cap) — those are otherwise hardware-only.
 *
 * Robolectric is needed only for `org.json`, which is a throwing stub in the
 * unit-test `android.jar`. Everything under test is plain Kotlin.
 */
@RunWith(RobolectricTestRunner::class)
class RepCaptureControllerTest {

    /** Counts registrations so the balance can be asserted directly (T-10-08). */
    private class FakeSensorGateway(
        private val availableSensor: String? = RepCaptureController.SENSOR_LINEAR_ACCELERATION,
    ) : RepSensorGateway {
        var registerCount = 0
            private set
        var unregisterCount = 0
            private set
        var onSample: ((Long, Float, Float, Float) -> Unit)? = null

        override fun registerListener(onSample: (Long, Float, Float, Float) -> Unit): String? {
            if (availableSensor == null) return null
            registerCount += 1
            this.onSample = onSample
            return availableSensor
        }

        override fun unregisterListener() {
            unregisterCount += 1
            onSample = null
        }
    }

    private class FakeSender(var deliver: Boolean = true) : RepMessageSender {
        val sent = mutableListOf<Pair<String, String>>()

        override fun send(path: String, payloadJson: String): Boolean {
            if (!deliver) return false
            sent += path to payloadJson
            return true
        }
    }

    private class FakeClock(var nowMs: Long = 0L) {
        fun advance(ms: Long) {
            nowMs += ms
        }
    }

    private fun controller(
        gateway: FakeSensorGateway = FakeSensorGateway(),
        sender: FakeSender = FakeSender(),
        clock: FakeClock = FakeClock(),
        batteryPercent: Int = 90,
    ) = RepCaptureController(
        sensors = gateway,
        sender = sender,
        batteryLevelPercent = { batteryPercent },
        clock = { clock.nowMs },
    )

    /** Feeds `count` samples 20 ms apart, large enough to be real motion. */
    private fun feed(
        gateway: FakeSensorGateway,
        clock: FakeClock,
        count: Int,
        startTMs: Long = 0L,
    ) {
        var t = startTMs
        repeat(count) {
            gateway.onSample?.invoke(t, 0f, 0f, 5f)
            t += 20L
            clock.advance(20L)
        }
    }

    private fun endPayloads(sender: FakeSender) =
        sender.sent.filter { it.first == WearSyncPaths.MESSAGE_REP_CAPTURE_END }

    @Test
    fun `normal stop leaves register and unregister balanced at one`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        assertTrue(subject.start("pull-up") is StartResult.Started)
        feed(gateway, clock, count = 120)
        subject.stop(RepCaptureController.REASON_USER)

        assertEquals(1, gateway.registerCount)
        assertEquals(1, gateway.unregisterCount)
        assertEquals(1, endPayloads(sender).size)
        assertEquals(
            "user",
            JSONObject(endPayloads(sender).first().second).getString("stoppedReason"),
        )
    }

    @Test
    fun `service destroy without a prior stop still balances`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        subject.start("chest-dips")
        feed(gateway, clock, count = 60)
        subject.onServiceDestroyed()

        assertEquals(1, gateway.registerCount)
        assertEquals(1, gateway.unregisterCount)
        assertEquals(
            "destroy",
            JSONObject(endPayloads(sender).single().second).getString("stoppedReason"),
        )
    }

    @Test
    fun `app background mid-capture balances and reports the background reason`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        subject.start("pull-up")
        feed(gateway, clock, count = 60)
        subject.onAppBackgrounded()

        assertEquals(1, gateway.registerCount)
        assertEquals(1, gateway.unregisterCount)
        assertEquals(
            "background",
            JSONObject(endPayloads(sender).single().second).getString("stoppedReason"),
        )
    }

    @Test
    fun `battery below fifteen percent refuses and never registers a listener`() {
        val gateway = FakeSensorGateway()
        val sender = FakeSender()
        val subject = controller(gateway, sender, FakeClock(), batteryPercent = 14)

        val result = subject.start("pull-up")

        assertEquals(StartRefusal.LowBattery, result)
        assertEquals("a refused start must not touch the sensor", 0, gateway.registerCount)
        assertEquals(0, gateway.unregisterCount)
        assertTrue("no capture-start may be announced", sender.sent.isEmpty())
        assertEquals(false, subject.isCapturing)
    }

    @Test
    fun `fifteen percent is the inclusive floor and still starts`() {
        val gateway = FakeSensorGateway()
        val subject = controller(gateway, FakeSender(), FakeClock(), batteryPercent = 15)

        assertTrue(subject.start("pull-up") is StartResult.Started)
        assertEquals(1, gateway.registerCount)
    }

    @Test
    fun `five minute cap stops capture flushes buffered batches and reports cap`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        subject.start("pull-up")
        feed(gateway, clock, count = 150, startTMs = 0L)
        val batchesBeforeCap = sender.sent.count { it.first == WearSyncPaths.MESSAGE_REP_SAMPLES }
        assertTrue("batching must already be flowing", batchesBeforeCap > 0)

        clock.advance(RepCaptureController.MAX_CAPTURE_MS)
        assertTrue("the cap must fire", subject.pollCap())

        assertEquals(false, subject.isCapturing)
        assertEquals(1, gateway.registerCount)
        assertEquals(1, gateway.unregisterCount)

        val end = JSONObject(endPayloads(sender).single().second)
        assertEquals("cap", end.getString("stoppedReason"))
        val flushedBatches = sender.sent.count { it.first == WearSyncPaths.MESSAGE_REP_SAMPLES }
        assertEquals(
            "batchCount must account for every flushed batch",
            flushedBatches,
            end.getInt("batchCount"),
        )
        assertTrue(
            "the partial batch held at cap time must be flushed",
            flushedBatches >= batchesBeforeCap,
        )
    }

    @Test
    fun `stop is idempotent — one unregister and one capture-end`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        subject.start("pull-up")
        feed(gateway, clock, count = 60)
        subject.stop(RepCaptureController.REASON_USER)
        subject.stop(RepCaptureController.REASON_USER)
        subject.onServiceDestroyed()

        assertEquals(1, gateway.registerCount)
        assertEquals(1, gateway.unregisterCount)
        assertEquals(1, endPayloads(sender).size)
    }

    @Test
    fun `samples carry a monotonic seq so the phone can detect a gap`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        subject.start("pull-up")
        feed(gateway, clock, count = 300)
        subject.stop(RepCaptureController.REASON_USER)

        val seqs = sender.sent
            .filter { it.first == WearSyncPaths.MESSAGE_REP_SAMPLES }
            .map { JSONObject(it.second).getInt("seq") }

        assertTrue(seqs.size >= 4)
        assertEquals(List(seqs.size) { it }, seqs)
    }

    @Test
    fun `an undelivered batch is held and replayed in order on reconnect`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender(deliver = false)
        val subject = controller(gateway, sender, clock)

        subject.start("pull-up")
        feed(gateway, clock, count = 150)
        assertTrue("nothing delivered while disconnected", sender.sent.isEmpty())

        sender.deliver = true
        subject.onConnectivityAvailable()

        val seqs = sender.sent
            .filter { it.first == WearSyncPaths.MESSAGE_REP_SAMPLES }
            .map { JSONObject(it.second).getInt("seq") }
        assertTrue("held batches must be replayed", seqs.isNotEmpty())
        assertEquals("held batches are never reordered", seqs.sorted(), seqs)
    }

    @Test
    fun `capture-end carries the provisional count under its own key only`() {
        val gateway = FakeSensorGateway()
        val clock = FakeClock()
        val sender = FakeSender()
        val subject = controller(gateway, sender, clock)

        subject.start("pull-up")
        feed(gateway, clock, count = 60)
        subject.stop(RepCaptureController.REASON_USER)

        val end = JSONObject(endPayloads(sender).single().second)
        assertTrue(end.has("provisionalCount"))
        assertEquals(
            "the watch count must never masquerade as the proposed count",
            false,
            end.has("reps") || end.has("count") || end.has("repCount"),
        )
    }

    @Test
    fun `a missing sensor refuses without registering`() {
        val gateway = FakeSensorGateway(availableSensor = null)
        val subject = controller(gateway, FakeSender(), FakeClock())

        assertEquals(StartRefusal.NoSensor, subject.start("pull-up"))
        assertEquals(0, gateway.registerCount)
        assertEquals(0, gateway.unregisterCount)
    }

    @Test
    fun `a second start while capturing is refused and does not double-register`() {
        val gateway = FakeSensorGateway()
        val subject = controller(gateway, FakeSender(), FakeClock())

        subject.start("pull-up")
        assertEquals(StartRefusal.AlreadyCapturing, subject.start("pull-up"))
        assertEquals(1, gateway.registerCount)
    }
}
