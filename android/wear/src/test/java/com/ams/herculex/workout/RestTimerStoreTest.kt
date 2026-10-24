package com.ams.herculex.workout

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class RestTimerStoreTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        RestTimerStore.clear(context)
    }

    @Test
    fun testCheckWakeGoTime_withinGracePeriod_triggersEvent() {
        val initialEvents = RestTimerStore.goTimeEvents.value
        RestTimerStore.lastFinishedEpochMs = System.currentTimeMillis() - 3_000L // 3s ago
        RestTimerStore.goTimePresented = false

        val triggered = RestTimerStore.checkWakeGoTime(context)

        assertTrue("Expected checkWakeGoTime to return true within grace period", triggered)
        assertTrue("Expected goTimePresented to be marked true", RestTimerStore.goTimePresented)
        assertEquals("Expected goTimeEvents to increment", initialEvents + 1, RestTimerStore.goTimeEvents.value)
    }

    @Test
    fun testCheckWakeGoTime_afterGracePeriod_doesNotTrigger() {
        val initialEvents = RestTimerStore.goTimeEvents.value
        RestTimerStore.lastFinishedEpochMs = System.currentTimeMillis() - 20_000L // 20s ago (beyond 12s grace)
        RestTimerStore.goTimePresented = false

        val triggered = RestTimerStore.checkWakeGoTime(context)

        assertFalse("Expected checkWakeGoTime to return false after grace period has expired", triggered)
        assertEquals("Expected goTimeEvents to remain unchanged", initialEvents, RestTimerStore.goTimeEvents.value)
    }

    @Test
    fun testCheckWakeGoTime_alreadyPresented_doesNotTriggerAgain() {
        RestTimerStore.lastFinishedEpochMs = System.currentTimeMillis() - 2_000L
        RestTimerStore.goTimePresented = true
        val initialEvents = RestTimerStore.goTimeEvents.value

        val triggered = RestTimerStore.checkWakeGoTime(context)

        assertFalse("Expected already-presented rest finish to not re-trigger", triggered)
        assertEquals(initialEvents, RestTimerStore.goTimeEvents.value)
    }

    @Test
    fun testDismissGoTime_marksPresentedAndSuppressesWake() {
        RestTimerStore.lastFinishedEpochMs = System.currentTimeMillis() - 1_000L
        RestTimerStore.goTimePresented = false

        RestTimerStore.dismissGoTime(context)

        assertTrue(RestTimerStore.goTimePresented)
        val triggered = RestTimerStore.checkWakeGoTime(context)
        assertFalse("Dismissed go-time should not trigger on wake", triggered)
    }

    @Test
    fun testClear_resetsFinishedState() {
        RestTimerStore.lastFinishedEpochMs = System.currentTimeMillis() - 1_000L
        RestTimerStore.goTimePresented = false

        RestTimerStore.clear(context)

        assertEquals(0L, RestTimerStore.lastFinishedEpochMs)
        assertFalse(RestTimerStore.checkWakeGoTime(context))
    }

    @Test
    fun testCheckWakeGoTime_recoversFromPreferencesWhenProcessRestarted() {
        val initialEvents = RestTimerStore.goTimeEvents.value
        val finishTime = System.currentTimeMillis() - 2_000L

        // Simulate background alarm / receiver persisting state, then in-memory static reset
        context.getSharedPreferences("rest_timer_store", Context.MODE_PRIVATE).edit()
            .putLong("last_finished_ms", finishTime)
            .putBoolean("go_time_presented", false)
            .putString("last_label", "Bench Press")
            .apply()

        RestTimerStore.lastFinishedEpochMs = 0L
        RestTimerStore.goTimePresented = false

        val triggered = RestTimerStore.checkWakeGoTime(context)

        assertTrue("Should recover from SharedPreferences and trigger", triggered)
        assertEquals("Bench Press", RestTimerStore.lastGoTimeLabel.value)
        assertEquals(initialEvents + 1, RestTimerStore.goTimeEvents.value)
    }
}
