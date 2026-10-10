package com.ams.herculex.workout

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

/**
 * What the watch does with a rest timer from the phone, and what it tells the
 * phone about it. The phone keeps its own end-of-rest notification until it
 * hears `armed=true`, so `armed` must be true exactly when this watch will
 * alert on time — and never otherwise.
 *
 * Pinned to SDK 34: without a manifest Robolectric falls back to a very old
 * SDK, which has neither `getSystemService(Class)` nor exact-alarm access.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RestTimerStoreTest {

    private val now = 1_000_000_000L
    private val endsAt = now + 60_000
    private lateinit var context: Context
    private lateinit var alarms: AlarmManager
    private lateinit var notifications: NotificationManager

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        alarms = context.getSystemService(AlarmManager::class.java)
        notifications = context.getSystemService(NotificationManager::class.java)
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        shadowOf(notifications).setNotificationsEnabled(true)
        RestTimerStore.clear(context)
        RestTimerStore.appInForeground = false
    }

    private fun payload(
        rev: Long? = 1,
        endsAtMs: Long = endsAt,
        alert: Boolean = true,
    ): String = JSONObject().apply {
        put("endsAtEpochMs", endsAtMs)
        put("totalSeconds", 60)
        put("label", "Plank")
        put("showOnWatch", true)
        put("alert", alert)
        if (rev != null) put("rev", rev)
    }.toString()

    private fun apply(json: String, at: Long = now) =
        RestTimerStore.applyFromPhone(context, json, nowMs = at)

    private fun scheduledAlarmCount() = shadowOf(alarms).scheduledAlarms.size

    // ── armed: the only thing the phone relies on ────────────────────────────

    @Test
    fun `an exact alarm with notifications allowed is armed`() {
        val result = apply(payload())

        assertTrue(result.armed)
        assertEquals(RestTimerStore.REASON_EXACT, result.reason)
        assertTrue(result.shouldAck)
        assertEquals(1, scheduledAlarmCount())
        assertEquals(endsAt, shadowOf(alarms).nextScheduledAlarm!!.triggerAtTime)
        assertEquals(endsAt, RestTimerStore.timer.value!!.endsAtEpochMs)
    }

    @Test
    fun `an inexact alarm is not armed, because it can fire far too late`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)

        val result = apply(payload())

        assertFalse(result.armed)
        assertEquals(RestTimerStore.REASON_INEXACT, result.reason)
        // Still scheduled — a late buzz beats none — but the phone must keep
        // its own on-time notification.
        assertEquals(1, scheduledAlarmCount())
        assertTrue(result.shouldAck)
    }

    @Test
    fun `notifications switched off are not armed`() {
        shadowOf(notifications).setNotificationsEnabled(false)

        val result = apply(payload())

        assertFalse(result.armed)
        assertEquals(RestTimerStore.REASON_NOTIFICATIONS_DENIED, result.reason)
        assertTrue(result.shouldAck)
    }

    @Test
    fun `alerts switched off arm nothing and send no ack`() {
        val result = apply(payload(alert = false))

        assertFalse(result.armed)
        assertEquals(RestTimerStore.REASON_ALERT_OFF, result.reason)
        assertFalse(result.shouldAck)
        assertEquals(0, scheduledAlarmCount())
        // The countdown is still shown.
        assertNotNull(RestTimerStore.timer.value)
    }

    @Test
    fun `a rest that already ended is cleared without an alert`() {
        val result = apply(payload(endsAtMs = now - 1))

        assertEquals(RestTimerStore.REASON_CLEARED, result.reason)
        assertFalse(result.shouldAck)
        assertEquals(0, scheduledAlarmCount())
        assertNull(RestTimerStore.timer.value)
    }

    @Test
    fun `the ack names the revision and end time it answers`() {
        val ack = JSONObject(apply(payload(rev = 42)).toAckJson())

        assertEquals(42L, ack.getLong("rev"))
        assertEquals(endsAt, ack.getLong("endsAtEpochMs"))
        assertTrue(ack.getBoolean("armed"))
        assertEquals("exact", ack.getString("reason"))
    }

    // ── revisions: duplicates, ordering, old phones ──────────────────────────

    @Test
    fun `the same revision from message and data item is applied once`() {
        val first = apply(payload(rev = 5))
        val second = apply(payload(rev = 5))

        assertTrue(first.shouldAck)
        assertEquals(RestTimerStore.REASON_DUPLICATE, second.reason)
        assertFalse(second.shouldAck)
        assertEquals(1, scheduledAlarmCount())
    }

    @Test
    fun `a late start cannot undo a newer skip`() {
        apply(payload(rev = 5))
        val skip = apply(payload(rev = 6, endsAtMs = 0), at = now + 1_000)
        val lateStart = apply(payload(rev = 5), at = now + 2_000)

        assertEquals(RestTimerStore.REASON_CLEARED, skip.reason)
        assertEquals(RestTimerStore.REASON_STALE, lateStart.reason)
        assertNull(RestTimerStore.timer.value)
        assertEquals(0, scheduledAlarmCount())
    }

    @Test
    fun `an extension with a newer revision replaces the alarm`() {
        apply(payload(rev = 5))
        val extended = apply(payload(rev = 6, endsAtMs = endsAt + 30_000), at = now + 1_000)

        assertTrue(extended.armed)
        assertEquals(1, scheduledAlarmCount())
        assertEquals(endsAt + 30_000, shadowOf(alarms).nextScheduledAlarm!!.triggerAtTime)
    }

    @Test
    fun `a lower revision long after the last one is a restarted phone, not stale`() {
        apply(payload(rev = 900))

        val afterRestart = apply(
            payload(rev = 3, endsAtMs = now + 3_600_000 + 60_000),
            at = now + 3_600_000,
        )

        assertTrue(afterRestart.armed)
    }

    @Test
    fun `a phone build without revisions always applies`() {
        val first = apply(payload(rev = null))
        val second = apply(payload(rev = null))

        assertTrue(first.armed)
        assertTrue(second.armed)
        assertEquals(0L, first.rev)
    }

    @Test
    fun `garbage is ignored quietly`() {
        val result = apply("not json")

        assertEquals(RestTimerStore.REASON_UNPARSEABLE, result.reason)
        assertFalse(result.shouldAck)
        assertEquals(0, scheduledAlarmCount())
    }

    // ── ending the workout ───────────────────────────────────────────────────

    @Test
    fun `clearing cancels the alarm so a finished workout cannot buzz later`() {
        apply(payload())
        assertEquals(1, scheduledAlarmCount())

        RestTimerStore.clear(context)

        assertEquals(0, scheduledAlarmCount())
        assertNull(RestTimerStore.timer.value)
    }

    // ── the alert itself ─────────────────────────────────────────────────────

    @Test
    fun `off screen the alert is a vibrating notification that stays for 30 s`() {
        apply(payload())

        RestTimerStore.onRestFinished(context)

        val posted = shadowOf(notifications).allNotifications
        assertEquals(1, posted.size)
        assertEquals("IT'S GO TIME", posted.single().extras.getString("android.title"))
        assertEquals(30_000L, posted.single().timeoutAfter)

        val channel = notifications.getNotificationChannel("rest_timer_go_time_v2")!!
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
        assertTrue(channel.shouldVibrate())
        assertEquals(listOf(0L, 140L, 110L, 140L), channel.vibrationPattern.toList())
    }

    @Test
    fun `the silent channel of the first version is removed`() {
        notifications.createNotificationChannel(
            android.app.NotificationChannel(
                "rest_timer_go_time",
                "Rest finished",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )

        apply(payload())

        assertNull(notifications.getNotificationChannel("rest_timer_go_time"))
        assertNotNull(notifications.getNotificationChannel("rest_timer_go_time_v2"))
    }

    @Test
    fun `on screen the alert is the overlay and no notification is posted`() {
        apply(payload())
        RestTimerStore.appInForeground = true
        val before = RestTimerStore.goTimeEvents.value

        RestTimerStore.onRestFinished(context)

        assertEquals(before + 1, RestTimerStore.goTimeEvents.value)
        assertEquals(0, shadowOf(notifications).allNotifications.size)
    }

    @Test
    fun `with alerts off the end of the rest is silent`() {
        apply(payload(alert = false))

        RestTimerStore.onRestFinished(context)

        assertEquals(0, shadowOf(notifications).allNotifications.size)
    }

    @Test
    fun `an alarm that fires after the process restarted still alerts`() {
        // No timer in memory: the process was killed and only the alarm
        // survived. The old behaviour was already to alert in that case.
        RestTimerStore.clear(context)

        RestTimerStore.onRestFinished(context)

        assertEquals(1, shadowOf(notifications).allNotifications.size)
    }
}
