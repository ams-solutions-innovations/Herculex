package com.ams.herculex.workout

import android.content.Context
import com.ams.herculex.sync.SyncEnvelope
import com.ams.herculex.sync.WearRevisionAllocator
import com.ams.herculex.sync.WearSyncContract
import org.json.JSONArray
import org.json.JSONObject

/// Resolves the wireId for an incoming exercise entry: the phone's
/// round-tripped `exercise_<id>` if present, otherwise a fresh watch-minted
/// one for a genuinely new exercise (Phase 3 of wear-sync remediation).
/// Top-level and `internal` (rather than inlined in
/// [WorkoutStore.parseAndUpdateSession]) so this — the only part of that
/// function with real decision logic — is unit-testable without needing a
/// live [WorkoutViewModel], which this module has no Robolectric shadow
/// precedent for constructing (see the Phase 1 log entry in
/// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md's progress
/// doc).
internal fun resolveExerciseWireId(rawWireId: String): String =
    rawWireId.takeIf { it.isNotBlank() } ?: "watch_exercise_${java.util.UUID.randomUUID()}"

/// Persists workout definitions in SharedPreferences (JSON).
/// Syncs with phone and falls back to built-in defaults if un-synced.
object WorkoutStore {

    private const val PREFS       = "herculex_workouts"
    private const val KEY_WORKOUTS = "workouts_json"
    private const val KEY_ACTIVE_SESSION = "active_session_json"
    private const val KEY_ACTIVE_SESSION_START_EPOCH = "active_session_start_epoch_ms"

    /// Persists the in-progress session so a fresh WorkoutViewModel (e.g.
    /// after the watch app's process/Activity gets recreated while a workout
    /// is running) can restore it instead of silently losing it.
    fun saveActiveSession(context: Context, json: String, startEpochMs: Long) {
        prefs(context).edit()
            .putString(KEY_ACTIVE_SESSION, json)
            .putLong(KEY_ACTIVE_SESSION_START_EPOCH, startEpochMs)
            .apply()
    }

    fun getActiveSessionJson(context: Context): String? =
        prefs(context).getString(KEY_ACTIVE_SESSION, null)

    fun getActiveSessionStartEpoch(context: Context): Long? {
        val value = prefs(context).getLong(KEY_ACTIVE_SESSION_START_EPOCH, -1L)
        return value.takeIf { it >= 0 }
    }

    fun clearActiveSession(context: Context) {
        prefs(context).edit()
            .remove(KEY_ACTIVE_SESSION)
            .remove(KEY_ACTIVE_SESSION_START_EPOCH)
            .apply()
    }

    /// Cold-start workouts, used only until the phone pushes the user's own.
    /// Names and slugs match the phone catalog so an exercise logged off one
    /// of these still lands on the real row — see [ExerciseCatalog.defaultCategories].
    val defaults: List<WorkoutTemplate> = listOf(
        WorkoutTemplate(
            id = "push_1", name = "Push Day",
            exercises = listOf(
                ExerciseTemplate("Barbell Bench Press",    4, 80.0,  8, slug = "barbell-bench-press", loggingMetric = "weight_reps"),
                ExerciseTemplate("Overhead Press",         4, 50.0,  8, slug = "overhead-press", loggingMetric = "weight_reps"),
                ExerciseTemplate("Incline Dumbbell Press", 3, 24.0, 10, slug = "incline-dumbbell-press", loggingMetric = "weight_reps"),
                ExerciseTemplate("Dumbbell Lateral Raise", 3, 12.0, 15, slug = "dumbbell-lateral-raise", loggingMetric = "weight_reps"),
                ExerciseTemplate("Tricep Pushdown (Rope)", 3, 25.0, 12, slug = "tricep-pushdown-rope", loggingMetric = "weight_reps"),
            )
        ),
        WorkoutTemplate(
            id = "pull_1", name = "Pull Day",
            exercises = listOf(
                ExerciseTemplate("Conventional Deadlift", 4, 120.0, 5, slug = "conventional-deadlift", loggingMetric = "weight_reps"),
                ExerciseTemplate("Barbell Row",           4,  70.0, 8, slug = "barbell-row", loggingMetric = "weight_reps"),
                ExerciseTemplate("Lat Pulldown",          3,  60.0, 10, slug = "lat-pulldown", loggingMetric = "weight_reps"),
                ExerciseTemplate("Dumbbell Curl",         3,  15.0, 12, slug = "dumbbell-curl", loggingMetric = "weight_reps"),
                ExerciseTemplate("Face Pull",             3,  20.0, 15, slug = "face-pull", loggingMetric = "weight_reps"),
            )
        ),
        WorkoutTemplate(
            id = "lbw_1", name = "LBW I.",
            exercises = listOf(
                ExerciseTemplate("Barbell Back Squat",   4, 100.0, 6, slug = "barbell-back-squat", loggingMetric = "weight_reps"),
                ExerciseTemplate("Romanian Deadlift",    4,  70.0, 8, slug = "romanian-deadlift", loggingMetric = "weight_reps"),
                ExerciseTemplate("Leg Press",            3, 120.0, 10, slug = "leg-press", loggingMetric = "weight_reps"),
                ExerciseTemplate("Lying Leg Curl",       3,  40.0, 12, slug = "lying-leg-curl", loggingMetric = "weight_reps"),
                ExerciseTemplate("Standing Calf Raise",  4,  60.0, 15, slug = "standing-calf-raise", loggingMetric = "weight_reps"),
            )
        ),
        WorkoutTemplate(
            id = "lbw_2", name = "LBW II.",
            exercises = listOf(
                ExerciseTemplate("Good Morning",           4, 20.0, 10, slug = "good-morning", loggingMetric = "weight_reps"),
                ExerciseTemplate("Safety Bar Squat",       4, 60.0,  6, slug = "safety-bar-squat", loggingMetric = "weight_reps"),
                ExerciseTemplate("Bulgarian Split Squat",  3, 20.0,  8, slug = "bulgarian-split-squat", loggingMetric = "weight_reps"),
                ExerciseTemplate("Nordic Hamstring Curl",  3,  0.0,  6, slug = "nordic-hamstring-curl", loggingMetric = "reps"),
                ExerciseTemplate("Leg Extension",          3, 40.0, 12, slug = "leg-extension", loggingMetric = "weight_reps"),
            )
        ),
        WorkoutTemplate(
            id = "upper_1", name = "Upper Body",
            exercises = listOf(
                ExerciseTemplate("Pull-Up",                 4,  0.0, 8, slug = "pull-up", loggingMetric = "reps"),
                ExerciseTemplate("Dumbbell Overhead Press", 3, 20.0, 10, slug = "dumbbell-overhead-press", loggingMetric = "weight_reps"),
                ExerciseTemplate("Seated Cable Row (V-Bar)",3, 50.0, 12, slug = "seated-cable-row-v-bar", loggingMetric = "weight_reps"),
                ExerciseTemplate("Dumbbell Fly",            3, 16.0, 12, slug = "dumbbell-fly", loggingMetric = "weight_reps"),
                ExerciseTemplate("Hammer Curl",             3, 14.0, 12, slug = "hammer-curl", loggingMetric = "weight_reps"),
            )
        ),
    )

    fun getWorkouts(context: Context): List<WorkoutTemplate> {
        val json = prefs(context).getString(KEY_WORKOUTS, null) ?: return defaults
        return try { parse(json) } catch (e: Exception) { defaults }
    }

    fun saveJson(context: Context, json: String) {
        prefs(context).edit().putString(KEY_WORKOUTS, json).apply()
    }

    fun getById(context: Context, id: String): WorkoutTemplate? =
        getWorkouts(context).firstOrNull { it.id == id }

    // No callers anywhere in android/ as of Phase 1 — confirmed dead code,
    // left as-is (not threaded with sessionId/entityId identity).
    fun parseAndStartSession(context: Context, json: String, viewModel: WorkoutViewModel?) {
        try {
            val obj = sessionPayloadObject(json)
            val template = parseTemplate(obj.getJSONObject("template"))
            val startedAtEpochMs = obj.optStartedAtEpochMs()
            // This session was started on the phone — don't echo a "started"
            // broadcast back to it, which would make the phone spawn a
            // second, duplicate session for what it already has.
            viewModel?.startWorkout(
                template,
                broadcastToPhone = false,
                startEpochMs = startedAtEpochMs ?: System.currentTimeMillis(),
                origin = sessionEnvelope(json).origin,
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun startedAtEpochMsFromSessionJson(json: String): Long? {
        return try {
            sessionPayloadObject(json).optStartedAtEpochMs()
        } catch (_: Exception) {
            null
        }
    }

    fun parseAndUpdateSession(json: String, viewModel: WorkoutViewModel?) {
        try {
            val envelope = sessionEnvelope(json)
            val obj = envelope.payload
            val templateObj = obj.optJSONObject("template")
            val templateName = templateObj?.optString("name", "Active Workout") ?: "Active Workout"
            val currentExIdx = obj.optInt("currentExerciseIndex", 0)
            val currentSetIdx = obj.optInt("currentSetIndex", 0)
            val startedAtEpochMs = obj.optStartedAtEpochMs()
            val fallbackSetStamp = SetSyncStamp(envelope.revision, envelope.origin)
            val exArr = obj.optJSONArray("exercises") ?: JSONArray()
            val exercises = (0 until exArr.length()).map { i ->
                val exObj = exArr.getJSONObject(i)
                val templateObjItem = exObj.optJSONObject("template")
                val templateItem = if (templateObjItem != null) parseTemplateItem(templateObjItem) else ExerciseTemplate("Exercise", 3, 0.0, 0)
                val setsArr = exObj.optJSONArray("sets") ?: JSONArray()
                val sets = (0 until setsArr.length()).map { j ->
                    val sObj = setsArr.getJSONObject(j)
                    val rawSetType = sObj.optString("setType", "standard")
                    LoggedSet(
                        wireId = sObj.optString("wireId").takeIf { it.isNotBlank() },
                        setIndex = if (!sObj.isNull("setIndex")) sObj.optInt("setIndex") else j,
                        weight = sObj.optDouble("weight", 0.0),
                        reps = sObj.optInt("reps", 0),
                        distanceMeters = sObj.optNullableDouble("distanceM"),
                        rpe = if (!sObj.isNull("rpe")) sObj.optDouble("rpe") else null,
                        setType = WearSyncContract.normalizeSetType(rawSetType),
                        isWarmup = WearSyncContract.normalizeIsWarmup(rawSetType, sObj.optBoolean("isWarmup", false)),
                        accessory = if (sObj.has("accessory")) sObj.getString("accessory") else null,
                        durationSeconds = sObj.optNullableInt("durationSeconds"),
                        completed = sObj.optBoolean("completed", true),
                        setTypeMetaJson = sObj.optString("setTypeMetaJson").takeIf { it.isNotBlank() && it != "null" },
                        bodyweightKg = sObj.optNullableDouble("bodyweightKg"),
                        chainsKg = sObj.optNullableDouble("chainsKg"),
                        completedAtEpochMs = sObj.optNullableLong("completedAtEpochMs"),
                        syncVersions = sObj.optSetSyncVersions(fallbackSetStamp),
                    )
                }
                val wireId = resolveExerciseWireId(exObj.optString("wireId"))
                val supersetGroup = if (!exObj.isNull("supersetGroup")) exObj.optInt("supersetGroup") else templateItem.supersetGroup
                ActiveExercise(template = templateItem, sets = sets, wireId = wireId, supersetGroup = supersetGroup)
            }
            viewModel?.updateSessionFromRemote(
                exercises,
                currentExIdx,
                currentSetIdx,
                templateName,
                startedAtEpochMs,
                origin = envelope.origin,
                sessionId = envelope.entityId,
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /** What the next set to log looks like — for tiles that cannot see the view model. */
    data class ActiveSetSummary(
        val exerciseIndex: Int,
        val exerciseName: String,
        val setNumber: Int,
        val setTotal: Int,
        val targetSeconds: Int?,
        val targetMeters: Int?,
    )

    fun activeSetSummary(context: Context): ActiveSetSummary? {
        val json = getActiveSessionJson(context) ?: return null
        return try {
            val obj = sessionPayloadObject(json)
            val exArr = obj.optJSONArray("exercises") ?: return null
            val idx = obj.optInt("currentExerciseIndex", 0)
            val exObj = exArr.optJSONObject(idx) ?: return null
            val template = exObj.optJSONObject("template")?.let { parseTemplateItem(it) } ?: return null
            val sets = exObj.optJSONArray("sets") ?: JSONArray()
            var done = 0
            for (j in 0 until sets.length()) {
                val sObj = sets.getJSONObject(j)
                if (sObj.optBoolean("completed", true) && !sObj.optBoolean("isWarmup", false)) done++
            }
            val planned = template.plannedSets.getOrNull(done) ?: template.plannedSets.firstOrNull()
            ActiveSetSummary(
                exerciseIndex = idx,
                exerciseName = template.name.substringBefore("(").trim(),
                setNumber = done + 1,
                setTotal = maxOf(template.targetSets, done + 1),
                targetSeconds = planned?.durationSeconds?.takeIf { it > 0 },
                targetMeters = planned?.targetDistanceMeters?.takeIf { it > 0 }?.toInt(),
            )
        } catch (e: Exception) {
            null
        }
    }

    fun sessionToJson(context: Context, session: WorkoutSession): String {
        val obj = JSONObject()
        obj.put("template", templateToJson(session.template))
        obj.put("currentExerciseIndex", session.currentExerciseIndex)
        obj.put("currentSetIndex", session.currentSetIndex)
        obj.put("startedAtEpochMs", session.startTimeMs)
        val exArr = JSONArray()
        session.exercises.forEach { ex ->
            val exObj = JSONObject()
            exObj.put("wireId", ex.wireId)
            ex.supersetGroup?.let { exObj.put("supersetGroup", it) }
            exObj.put("template", templateItemToJson(ex.template))
            val setsArr = JSONArray()
            ex.sets.forEach { set ->
                val sObj = JSONObject()
                set.wireId?.let { sObj.put("wireId", it) }
                set.setIndex?.let { sObj.put("setIndex", it) }
                sObj.put("weight", set.weight)
                sObj.put("reps", set.reps)
                set.durationSeconds?.let { sObj.put("durationSeconds", it) }
                set.distanceMeters?.let { sObj.put("distanceM", it) }
                set.rpe?.let { sObj.put("rpe", it) }
                sObj.put("setType", set.setType)
                sObj.put("isWarmup", set.isWarmup)
                set.accessory?.let { sObj.put("accessory", it) }
                set.setTypeMetaJson?.let { sObj.put("setTypeMetaJson", it) }
                set.bodyweightKg?.let { sObj.put("bodyweightKg", it) }
                set.chainsKg?.let { sObj.put("chainsKg", it) }
                set.completedAtEpochMs?.let { sObj.put("completedAtEpochMs", it) }
                set.syncVersions?.let { sObj.put("syncVersions", it.toJson()) }
                sObj.put("completed", set.completed)
                setsArr.put(sObj)
            }
            exObj.put("sets", setsArr)
            exArr.put(exObj)
        }
        obj.put("exercises", exArr)
        // Report the session's real origin rather than hardcoding "watch". A
        // workout the watch adopted from the phone is still phone-origin, and
        // the phone uses this field to decide whether to raise its "Workout
        // Started on Watch" alert.
        return WearSyncContract.encodeEnvelope(
            entity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            entityId = session.sessionId,
            revision = WearRevisionAllocator(context, "workout").next(),
            origin = session.origin,
            payload = obj,
        )
    }

    /// The active session's wire identity, for callers (e.g. [SyncService])
    /// that need to gate an incoming envelope without a live ViewModel to
    /// compare against.
    fun activeSessionEntityId(context: Context): String? {
        val json = getActiveSessionJson(context) ?: return null
        return try {
            sessionEnvelope(json).entityId
        } catch (_: Exception) {
            null
        }
    }

    private fun templateToJson(template: WorkoutTemplate): JSONObject {
        val obj = JSONObject()
        obj.put("id", template.id)
        obj.put("name", template.name)
        val arr = JSONArray()
        template.exercises.forEach { arr.put(templateItemToJson(it)) }
        obj.put("exercises", arr)
        return obj
    }

    private fun templateItemToJson(item: ExerciseTemplate): JSONObject =
        ExerciseCatalog.toJson(item)

    private fun parseTemplate(obj: JSONObject): WorkoutTemplate {
        val exArr = obj.getJSONArray("exercises")
        return WorkoutTemplate(
            id = obj.getString("id"),
            name = obj.getString("name"),
            exercises = (0 until exArr.length()).map { parseTemplateItem(exArr.getJSONObject(it)) }
        )
    }

    private fun parseTemplateItem(obj: JSONObject): ExerciseTemplate =
        ExerciseCatalog.parse(obj)

    private fun parse(json: String): List<WorkoutTemplate> {
        val arr = JSONArray(json)
        return (0 until arr.length()).map { i ->
            parseTemplate(arr.getJSONObject(i))
        }
    }

    private fun JSONObject.optStartedAtEpochMs(): Long? {
        return if (!isNull("startedAtEpochMs")) {
            optLong("startedAtEpochMs").takeIf { it > 0L }
        } else {
            null
        }
    }

    /// Every session JSON the watch decodes arrives either straight from the
    /// phone or from our own persisted copy of a session, so a legacy payload
    /// with no envelope is phone-authored — hence the [ORIGIN_PHONE] fallback.
    private fun sessionEnvelope(json: String): SyncEnvelope {
        return WearSyncContract.decodeEnvelope(
            json = json,
            fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            fallbackEntityId = "active_workout",
            fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
        )
    }

    private fun sessionPayloadObject(json: String): JSONObject = sessionEnvelope(json).payload

    private fun JSONObject.optNullableDouble(name: String): Double? {
        if (!has(name) || isNull(name)) return null
        return optDouble(name)
    }

    private fun JSONObject.optNullableInt(name: String): Int? {
        if (!has(name) || isNull(name)) return null
        return optInt(name)
    }

    private fun JSONObject.optNullableLong(name: String): Long? {
        if (!has(name) || isNull(name)) return null
        return optLong(name).takeIf { it > 0L }
    }

    private fun JSONObject.optSetSyncVersions(fallback: SetSyncStamp): SetSyncVersions {
        val versions = optJSONObject("syncVersions") ?: return SetSyncVersions.uniform(fallback)
        return SetSyncVersions(
            weight = versions.optSetSyncStamp("weight", fallback),
            reps = versions.optSetSyncStamp("reps", fallback),
            completion = versions.optSetSyncStamp("completion", fallback),
        )
    }

    private fun JSONObject.optSetSyncStamp(name: String, fallback: SetSyncStamp): SetSyncStamp {
        val obj = optJSONObject(name) ?: return fallback
        val origin = obj.optString("origin").takeIf { it.isNotBlank() } ?: return fallback
        if (!obj.has("revision")) return fallback
        return SetSyncStamp(obj.optLong("revision"), origin)
    }

    private fun SetSyncVersions.toJson(): JSONObject = JSONObject()
        .put("weight", weight.toJson())
        .put("reps", reps.toJson())
        .put("completion", completion.toJson())

    private fun SetSyncStamp.toJson(): JSONObject = JSONObject()
        .put("revision", revision)
        .put("origin", origin)

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
