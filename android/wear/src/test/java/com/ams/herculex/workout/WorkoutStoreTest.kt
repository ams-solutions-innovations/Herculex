package com.ams.herculex.workout

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ams.herculex.sync.WearSyncContract
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Phase 3 of wear-sync-race-conditions-remediation-plan-2026-08-11.md needs a
 * stable per-exercise wireId, round-tripped from the phone (or minted by the
 * watch for its own new exercises), so the phone's ID-based reconciliation
 * can tell "substituted exercise in the same slot" apart from "deleted +
 * inserted exercise" instead of relying on list position. This was a real
 * gap found during implementation: only [LoggedSet.wireId] round-tripped
 * before this phase — [ActiveExercise] had no equivalent at all, so the
 * plan's "explicit slot id, not positional coincidence" requirement (Faza 3
 * pristop, zadnja alineja) couldn't be met for exercises without this
 * addition, even though the plan doc's own file list scoped Phase 3 as
 * Dart-only.
 *
 * These cover the Kotlin half of the round trip: [WorkoutStore.sessionToJson]
 * (encode) and [resolveExerciseWireId] (the decision logic
 * [WorkoutStore.parseAndUpdateSession] uses on decode). Not covered:
 * `parseAndUpdateSession`'s own exercise list, which is only observable via
 * a live [WorkoutViewModel] — this module has no Robolectric shadow
 * precedent for constructing one under test (`Wearable.getDataClient`
 * mocking, `viewModelScope` dispatcher control), the same gap the Phase 1
 * log entry already flagged for entityId-gating tests. [resolveExerciseWireId]
 * was pulled out to top-level specifically so the one piece of real decision
 * logic in that parse path is still testable without it.
 */
@RunWith(RobolectricTestRunner::class)
class WorkoutStoreTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun sessionWith(exercises: List<ActiveExercise>): WorkoutSession {
        return WorkoutSession(
            template = WorkoutTemplate(
                id = "t",
                name = "Test",
                exercises = exercises.map { it.template },
            ),
            exercises = exercises,
        )
    }

    private fun exercisesJsonFrom(sessionJson: String): JSONArray {
        val envelope = WearSyncContract.decodeEnvelope(
            json = sessionJson,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "active_workout",
            fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
        )
        return envelope.payload.getJSONArray("exercises")
    }

    @Test
    fun `sessionToJson writes each exercise's own wireId, not the template's`() {
        val phoneOriginated = ActiveExercise(
            template = ExerciseTemplate("Bench Press", targetSets = 3),
            wireId = "exercise_5",
        )
        val watchOriginated = ActiveExercise(
            template = ExerciseTemplate("Squat", targetSets = 3),
            wireId = "watch_exercise_abc-123",
        )
        val json = WorkoutStore.sessionToJson(
            context,
            sessionWith(listOf(phoneOriginated, watchOriginated)),
        )

        val exArr = exercisesJsonFrom(json)
        assertEquals("exercise_5", exArr.getJSONObject(0).getString("wireId"))
        assertEquals("watch_exercise_abc-123", exArr.getJSONObject(1).getString("wireId"))
    }

    @Test
    fun `a session round trip through sessionToJson feeds resolveExerciseWireId the same id it started with`() {
        // sessionToJson is the encode half; resolveExerciseWireId (extracted
        // from parseAndUpdateSession) is exactly what the decode half calls
        // on each exercise's "wireId" field. Chaining the real encode output
        // into the real decode-side function proves the two halves agree on
        // the wire format without needing a WorkoutViewModel to observe
        // parseAndUpdateSession's own output.
        val original = ActiveExercise(
            template = ExerciseTemplate("Deadlift", targetSets = 4),
            wireId = "exercise_42",
        )
        val json = WorkoutStore.sessionToJson(context, sessionWith(listOf(original)))
        val exObj = exercisesJsonFrom(json).getJSONObject(0)

        assertEquals("exercise_42", resolveExerciseWireId(exObj.optString("wireId")))
    }

    @Test
    fun `resolveExerciseWireId returns a non-blank id unchanged`() {
        assertEquals("exercise_7", resolveExerciseWireId("exercise_7"))
        assertEquals("watch_exercise_xyz", resolveExerciseWireId("watch_exercise_xyz"))
    }

    @Test
    fun `resolveExerciseWireId mints a fresh watch-prefixed id when blank or missing`() {
        val minted = resolveExerciseWireId("")
        assertTrue(
            "expected a watch-minted id, got '$minted'",
            minted.startsWith("watch_exercise_"),
        )
        assertTrue(minted.length > "watch_exercise_".length)
    }

    @Test
    fun `resolveExerciseWireId mints distinct ids on repeated calls`() {
        val first = resolveExerciseWireId("")
        val second = resolveExerciseWireId("")
        assertNotEquals(
            "two genuinely new exercises must not collide on the same minted slot id",
            first,
            second,
        )
    }

    @Test
    fun `parsing an exercise with no wireId field at all also mints a fresh id`() {
        // optString("wireId") on a JSONObject that never had the key returns
        // "" (org.json's documented behavior for a missing key), which must
        // resolve the same way as an explicitly blank one.
        val exObjWithoutWireId = JSONObject().apply {
            put("template", JSONObject().put("name", "Bench Press"))
            put("sets", JSONArray())
        }
        val minted = resolveExerciseWireId(exObjWithoutWireId.optString("wireId"))
        assertTrue(minted.startsWith("watch_exercise_"))
    }
}
