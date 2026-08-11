package com.ams.herculex

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Phase 4 of docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md:
 * `shouldReplacePendingWorkout` is the collision-resolution policy behind
 * `PhoneWearListenerService.savePendingWorkout`'s single unconfirmed-session
 * slot. It's a pure, top-level function specifically so it's unit-testable
 * without standing up the full `WearableListenerService` (which needs an
 * Android runtime this module has no Robolectric-shadow precedent for — see
 * the Phase 1 log entry's equivalent note for `SyncService`).
 */
class PendingWorkoutCollisionTest {

    @Test
    fun `higher-revision incoming session replaces the pending slot`() {
        val existing = PendingWorkoutSlot(entityId = "session-a", revision = 10L)
        val incoming = PendingWorkoutSlot(entityId = "session-b", revision = 11L)

        assertTrue(shouldReplacePendingWorkout(existing, incoming))
    }

    @Test
    fun `lower-revision incoming session does not replace the pending slot`() {
        // The core collision fix: previously the single SharedPreferences
        // slot was overwritten unconditionally ("last write wins"), which
        // could let a stale/reordered delivery clobber a newer unconfirmed
        // session.
        val existing = PendingWorkoutSlot(entityId = "session-a", revision = 10L)
        val incoming = PendingWorkoutSlot(entityId = "session-b", revision = 9L)

        assertFalse(shouldReplacePendingWorkout(existing, incoming))
    }

    @Test
    fun `equal revision incoming session replaces the pending slot`() {
        val existing = PendingWorkoutSlot(entityId = "session-a", revision = 10L)
        val incoming = PendingWorkoutSlot(entityId = "session-b", revision = 10L)

        assertTrue(shouldReplacePendingWorkout(existing, incoming))
    }

    @Test
    fun `unknown revisions fall back to last-write-wins`() {
        val existing = PendingWorkoutSlot(entityId = "session-a", revision = null)
        val incoming = PendingWorkoutSlot(entityId = "session-b", revision = 20L)

        assertTrue(shouldReplacePendingWorkout(existing, incoming))
    }
}
