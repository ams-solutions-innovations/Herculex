package com.ams.herculex.sync

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Phase 4 of docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md:
 * `WearRealtimeQueueStore`'s attempt-tracking round trip and the
 * `isExpired` retry-cap policy it feeds. These cover the queue-mechanics
 * half of the "non-blocking, bounded queue" fix; the other half — that
 * `flushPendingRealtimeMessages` no longer `break`s the whole loop on one
 * message's delivery failure — isn't independently unit tested here, since
 * that requires mocking the Wearable `MessageClient`/`NodeClient` Task APIs,
 * which this module has no precedent for (same gap noted for
 * `WorkoutViewModel`/`SyncService` in the Phase 1 progress-log entry).
 */
@RunWith(RobolectricTestRunner::class)
class WearDataLayerSyncManagerTest {

    @Test
    fun `enqueued message starts with zero attempts and a real timestamp`() {
        val store = WearRealtimeQueueStore(ApplicationProvider.getApplicationContext())
        val before = System.currentTimeMillis()

        store.enqueue(path = "/herculex_fasting_command", payloadJson = "{}")

        val message = store.readAll().single()
        assertEquals(0, message.attempts)
        assertTrue(message.enqueuedAtEpochMs >= before)
    }

    @Test
    fun `recordFailedAttempts increments only the named messages`() {
        val store = WearRealtimeQueueStore(ApplicationProvider.getApplicationContext())
        store.enqueue(path = "/a", payloadJson = "{}")
        store.enqueue(path = "/b", payloadJson = "{}")
        val (first, second) = store.readAll()

        store.recordFailedAttempts(listOf(first.id))

        val after = store.readAll().associateBy { it.id }
        assertEquals(1, after.getValue(first.id).attempts)
        assertEquals(0, after.getValue(second.id).attempts)
    }

    @Test
    fun `removeAll drops only the delivered ids, leaving the rest for retry`() {
        val store = WearRealtimeQueueStore(ApplicationProvider.getApplicationContext())
        store.enqueue(path = "/a", payloadJson = "{}")
        store.enqueue(path = "/b", payloadJson = "{}")
        store.enqueue(path = "/c", payloadJson = "{}")
        val (first, second, third) = store.readAll()

        // Regression shape for the Phase 4 fix: message #2 "failed" (stays),
        // #1 and #3 "delivered" (removed) — the old break-on-first-failure
        // loop could never produce this partition, since it always stopped
        // at the first failure and left everything after it untouched too.
        store.removeAll(listOf(first.id, third.id))

        val remaining = store.readAll()
        assertEquals(listOf(second.id), remaining.map { it.id })
    }

    @Test
    fun `isExpired trips on attempt budget regardless of age`() {
        val fresh = PendingWearRealtimeMessage(
            id = "1",
            path = "/a",
            payloadJson = "{}",
            enqueuedAtEpochMs = 1_000L,
            attempts = 20,
        )
        assertTrue(isExpired(fresh, nowEpochMs = 1_000L, maxAttempts = 20, maxAgeMs = Long.MAX_VALUE))
    }

    @Test
    fun `isExpired trips on age regardless of attempt count`() {
        val old = PendingWearRealtimeMessage(
            id = "1",
            path = "/a",
            payloadJson = "{}",
            enqueuedAtEpochMs = 0L,
            attempts = 0,
        )
        assertTrue(isExpired(old, nowEpochMs = 100_000L, maxAttempts = 20, maxAgeMs = 99_999L))
    }

    @Test
    fun `isExpired is false for a fresh, low-attempt message`() {
        val message = PendingWearRealtimeMessage(
            id = "1",
            path = "/a",
            payloadJson = "{}",
            enqueuedAtEpochMs = 1_000L,
            attempts = 1,
        )
        assertFalse(isExpired(message, nowEpochMs = 2_000L, maxAttempts = 20, maxAgeMs = 99_999L))
    }
}
