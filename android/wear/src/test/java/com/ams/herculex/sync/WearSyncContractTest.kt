package com.ams.herculex.sync

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Canonical v1 wire fixtures shared (by convention, not by file — Dart and
 * Kotlin can't literally share a file) with the Dart contract test at
 * test/wear_sync_contract_test.dart. Phase 1 of
 * docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md bumps
 * SCHEMA_VERSION to 2; these v1 fixtures pin today's behavior so that change
 * is a visible diff against a known-good baseline. Keep both files'
 * literals byte-for-byte identical when adding new fixtures here.
 */
private const val CANONICAL_V1_WORKOUT_START_JSON =
    "{\"schemaVersion\":1,\"entity\":\"active_workout\",\"entityId\":\"session-1\"," +
        "\"revision\":42,\"origin\":\"phone\",\"updatedAtEpochMs\":1000," +
        "\"payload\":{\"startedAtEpochMs\":900,\"exercises\":[{\"sets\":[{\"rpe\":8.5," +
        "\"setType\":\"standard\",\"isWarmup\":false}]}]}}"

private const val CANONICAL_V1_FASTING_SNAPSHOT_JSON =
    "{\"schemaVersion\":1,\"entity\":\"fasting\",\"entityId\":\"fasting\"," +
        "\"revision\":5,\"origin\":\"watch\",\"updatedAtEpochMs\":2000," +
        "\"payload\":{\"isActive\":true,\"startedAtEpochMs\":1500}}"

private const val CANONICAL_LEGACY_FALLBACK_JSON =
    "{\"currentExerciseIndex\":0,\"exercises\":[]}"

// v2 fixtures added by Phase 1: schemaVersion 2, a UUID-shaped entityId (the
// stable session identity introduced in Phase 1a) and a revision consistent
// with the persisted allocator introduced in Phase 1b. Keep byte-for-byte
// identical with the Dart fixture of the same name.
private const val CANONICAL_V2_WORKOUT_START_JSON =
    "{\"schemaVersion\":2,\"entity\":\"active_workout\"," +
        "\"entityId\":\"3fa85f64-5717-4562-b3fc-2c963f66afa6\"," +
        "\"revision\":1000042,\"origin\":\"phone\",\"updatedAtEpochMs\":1000," +
        "\"payload\":{\"startedAtEpochMs\":900,\"exercises\":[{\"sets\":[{\"rpe\":8.5," +
        "\"setType\":\"standard\",\"isWarmup\":false}]}]}}"

private const val CANONICAL_V2_FASTING_SNAPSHOT_JSON =
    "{\"schemaVersion\":2,\"entity\":\"fasting\",\"entityId\":\"fasting\"," +
        "\"revision\":1000005,\"origin\":\"watch\",\"updatedAtEpochMs\":2000," +
        "\"payload\":{\"isActive\":true,\"startedAtEpochMs\":1500}}"

/**
 * [AppliedRevisionStore] now splits the old combined "check and commit" into
 * [AppliedRevisionStore.wouldAccept] (pure) and [AppliedRevisionStore.commit]
 * (mutation) — see Phase 4 of
 * docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md (deferred
 * from Phase 1/2, mirrors the Dart-side `WearDedupeState` split). Tests below
 * that exercise "accept, then commit" ordering use this helper to keep the
 * same combined-semantics assertions as before the split.
 */
private fun acceptAndCommit(store: AppliedRevisionStore, envelope: SyncEnvelope): Boolean {
    val accepted = store.wouldAccept(envelope)
    if (accepted) store.commit(envelope)
    return accepted
}

@RunWith(RobolectricTestRunner::class)
class WearSyncContractTest {

    @Test
    fun `decodes the canonical workout-start envelope`() {
        val decoded = WearSyncContract.decodeEnvelope(
            CANONICAL_V1_WORKOUT_START_JSON,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "fallback",
            fallbackOrigin = WearSyncContract.ORIGIN_WATCH,
        )

        assertEquals(1, decoded.schemaVersion)
        assertEquals(WearSyncContract.ENTITY_ACTIVE_WORKOUT, decoded.entity)
        assertEquals("session-1", decoded.entityId)
        assertEquals(42L, decoded.revision)
        assertEquals(WearSyncContract.ORIGIN_PHONE, decoded.origin)
        assertEquals(1000L, decoded.updatedAtEpochMs)
        assertEquals(900, decoded.payload.getLong("startedAtEpochMs"))
        val firstSet = decoded.payload.getJSONArray("exercises")
            .getJSONObject(0)
            .getJSONArray("sets")
            .getJSONObject(0)
        assertEquals(8.5, firstSet.getDouble("rpe"), 0.0001)
    }

    @Test
    fun `decodes the canonical fasting snapshot envelope`() {
        val decoded = WearSyncContract.decodeEnvelope(
            CANONICAL_V1_FASTING_SNAPSHOT_JSON,
            fallbackEntity = WearSyncContract.ENTITY_FASTING,
            fallbackEntityId = "fallback",
            fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
        )

        assertEquals(1, decoded.schemaVersion)
        assertEquals(WearSyncContract.ENTITY_FASTING, decoded.entity)
        assertEquals("fasting", decoded.entityId)
        assertEquals(5L, decoded.revision)
        assertEquals(WearSyncContract.ORIGIN_WATCH, decoded.origin)
        assertTrue(decoded.payload.getBoolean("isActive"))
    }

    @Test
    fun `decodes the canonical legacy (unenveloped) payload`() {
        val decoded = WearSyncContract.decodeEnvelope(
            CANONICAL_LEGACY_FALLBACK_JSON,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "legacy",
            fallbackOrigin = WearSyncContract.ORIGIN_WATCH,
        )

        assertEquals(0, decoded.schemaVersion)
        assertEquals("legacy", decoded.entityId)
        assertEquals(0L, decoded.revision)
        assertEquals(0L, decoded.updatedAtEpochMs)
        assertEquals(0, decoded.payload.getJSONArray("exercises").length())
    }

    @Test
    fun `decodes the canonical v2 workout-start envelope`() {
        val decoded = WearSyncContract.decodeEnvelope(
            CANONICAL_V2_WORKOUT_START_JSON,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "fallback",
            fallbackOrigin = WearSyncContract.ORIGIN_WATCH,
        )

        assertEquals(2, decoded.schemaVersion)
        assertEquals(WearSyncContract.ENTITY_ACTIVE_WORKOUT, decoded.entity)
        assertEquals("3fa85f64-5717-4562-b3fc-2c963f66afa6", decoded.entityId)
        assertEquals(1000042L, decoded.revision)
        assertEquals(WearSyncContract.ORIGIN_PHONE, decoded.origin)
        assertEquals(900, decoded.payload.getLong("startedAtEpochMs"))
    }

    @Test
    fun `decodes the canonical v2 fasting snapshot envelope`() {
        val decoded = WearSyncContract.decodeEnvelope(
            CANONICAL_V2_FASTING_SNAPSHOT_JSON,
            fallbackEntity = WearSyncContract.ENTITY_FASTING,
            fallbackEntityId = "fallback",
            fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
        )

        assertEquals(2, decoded.schemaVersion)
        assertEquals("fasting", decoded.entityId)
        assertEquals(1000005L, decoded.revision)
        assertTrue(decoded.payload.getBoolean("isActive"))
    }

    @Test
    fun `encodeEnvelope stamps the live SCHEMA_VERSION`() {
        val json = WearSyncContract.encodeEnvelope(
            entity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            entityId = "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            revision = 7L,
            origin = WearSyncContract.ORIGIN_PHONE,
            payload = org.json.JSONObject(),
        )
        val decoded = WearSyncContract.decodeEnvelope(
            json,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "fallback",
            fallbackOrigin = WearSyncContract.ORIGIN_WATCH,
        )

        assertEquals(2, WearSyncContract.SCHEMA_VERSION)
        assertEquals(2, decoded.schemaVersion)
        assertEquals("3fa85f64-5717-4562-b3fc-2c963f66afa6", decoded.entityId)
    }

    @Test
    fun `decode falls back to caller-supplied entityId and origin when absent`() {
        val json = "{\"schemaVersion\":1,\"entity\":\"active_workout\",\"revision\":7," +
            "\"updatedAtEpochMs\":500,\"payload\":{\"exercises\":[]}}"

        val decoded = WearSyncContract.decodeEnvelope(
            json,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "fallback-entity-id",
            fallbackOrigin = WearSyncContract.ORIGIN_WATCH,
        )

        assertEquals("fallback-entity-id", decoded.entityId)
        assertEquals(WearSyncContract.ORIGIN_WATCH, decoded.origin)
    }

    @Test
    fun `revision dedupe accepts newest and ignores duplicate or stale state`() {
        val store = AppliedRevisionStore(ApplicationProvider.getApplicationContext())
        fun env(revision: Long, updatedAt: Long) = SyncEnvelope(
            schemaVersion = 1,
            entity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            entityId = "session-1",
            revision = revision,
            origin = WearSyncContract.ORIGIN_WATCH,
            updatedAtEpochMs = updatedAt,
            payload = org.json.JSONObject(),
        )

        assertTrue(acceptAndCommit(store, env(10, 100)))
        assertFalse(acceptAndCommit(store, env(10, 100)))
        assertFalse(acceptAndCommit(store, env(9, 101)))
        assertTrue(acceptAndCommit(store, env(10, 101)))
        assertTrue(acceptAndCommit(store, env(11, 90)))
    }

    @Test
    fun `dedupe state is isolated per entity-entityId-origin key`() {
        val store = AppliedRevisionStore(ApplicationProvider.getApplicationContext())
        fun env(entity: String, entityId: String, origin: String) = SyncEnvelope(
            schemaVersion = 1,
            entity = entity,
            entityId = entityId,
            revision = 1,
            origin = origin,
            updatedAtEpochMs = 100,
            payload = org.json.JSONObject(),
        )

        assertTrue(
            acceptAndCommit(
                store,
                env(WearSyncContract.ENTITY_ACTIVE_WORKOUT, "session-1", WearSyncContract.ORIGIN_WATCH),
            ),
        )
        assertTrue(
            "different entityId is a different dedupe key",
            acceptAndCommit(
                store,
                env(WearSyncContract.ENTITY_ACTIVE_WORKOUT, "session-2", WearSyncContract.ORIGIN_WATCH),
            ),
        )
        assertTrue(
            "different entity is a different dedupe key",
            acceptAndCommit(
                store,
                env(WearSyncContract.ENTITY_FASTING, "session-1", WearSyncContract.ORIGIN_WATCH),
            ),
        )
        assertTrue(
            "different origin is a different dedupe key",
            acceptAndCommit(
                store,
                env(WearSyncContract.ENTITY_ACTIVE_WORKOUT, "session-1", WearSyncContract.ORIGIN_PHONE),
            ),
        )
    }

    @Test
    fun `legacy (unenveloped) payloads are rejected — fail closed`() {
        // Phase 1c: this bypass existed for pre-envelope watch builds. Once
        // both APKs move to schemaVersion 2 together there's no legitimate
        // sender left for this shape, so it must now be rejected instead of
        // always-accepted.
        val store = AppliedRevisionStore(ApplicationProvider.getApplicationContext())
        val decoded = WearSyncContract.decodeEnvelope(
            CANONICAL_LEGACY_FALLBACK_JSON,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "legacy",
            fallbackOrigin = WearSyncContract.ORIGIN_WATCH,
        )

        assertEquals(0, decoded.schemaVersion)
        assertFalse(acceptAndCommit(store, decoded))
        assertFalse(acceptAndCommit(store, decoded))
    }

    @Test
    fun `wouldAccept does not mutate state — repeated calls give the same answer`() {
        val store = AppliedRevisionStore(ApplicationProvider.getApplicationContext())
        val first = SyncEnvelope(
            schemaVersion = 2,
            entity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            entityId = "session-1",
            revision = 10,
            origin = WearSyncContract.ORIGIN_WATCH,
            updatedAtEpochMs = 100,
            payload = org.json.JSONObject(),
        )

        assertTrue(store.wouldAccept(first))
        assertTrue(
            "checking again without committing must not change the answer",
            store.wouldAccept(first),
        )
        assertTrue(store.wouldAccept(first))
    }

    @Test
    fun `a failed apply must not commit — retrying the same envelope after wouldAccept still succeeds`() {
        // Regression test for the Phase 4 fix: previously AppliedRevisionStore's
        // combined shouldAccept() mutated state on the check itself, so a
        // caller that checked, then failed to durably apply, then retried the
        // exact same envelope would be told to ignore it forever.
        val store = AppliedRevisionStore(ApplicationProvider.getApplicationContext())
        val envelope = SyncEnvelope(
            schemaVersion = 2,
            entity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            entityId = "session-1",
            revision = 10,
            origin = WearSyncContract.ORIGIN_WATCH,
            updatedAtEpochMs = 100,
            payload = org.json.JSONObject(),
        )

        assertTrue(store.wouldAccept(envelope))
        // Simulate the durable apply failing: commit() is deliberately not
        // called here.

        // Retry of the identical envelope must still be accepted.
        assertTrue(store.wouldAccept(envelope))
        store.commit(envelope)

        // Now that it's committed, the same envelope is correctly rejected.
        assertFalse(store.wouldAccept(envelope))
    }

    @Test
    fun `normalizes warmup and legacy set type labels`() {
        assertEquals("standard", WearSyncContract.normalizeSetType("Normal"))
        assertTrue(WearSyncContract.normalizeIsWarmup(setType = "warmup", isWarmup = false))
        assertEquals("standard", WearSyncContract.normalizeSetType("warmup"))
        assertEquals("forced", WearSyncContract.normalizeSetType("failure"))
    }

    @Test
    fun `WearRevisionAllocator persists across a simulated process restart`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val beforeRestart = WearRevisionAllocator(context, "workout")
        val first = beforeRestart.next()

        // Simulate a restart: a fresh allocator instance sharing the same
        // underlying persisted SharedPreferences.
        val afterRestart = WearRevisionAllocator(context, "workout")
        val second = afterRestart.next()

        assertTrue(second > first)
    }

    @Test
    fun `WearRevisionAllocator with different keys does not collide`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val workout = WearRevisionAllocator(context, "workout")
        val fasting = WearRevisionAllocator(context, "fasting")

        val workoutFirst = workout.next()
        val fastingFirst = fasting.next()
        val workoutSecond = workout.next()

        assertTrue(workoutSecond > workoutFirst)
        assertTrue(fastingFirst != workoutSecond)
    }
}
