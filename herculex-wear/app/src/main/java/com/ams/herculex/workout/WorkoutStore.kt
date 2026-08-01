package com.ams.herculex.workout

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/// Persists workout definitions in SharedPreferences (JSON).
/// Syncs with phone and falls back to built-in defaults if un-synced.
object WorkoutStore {

    private const val PREFS       = "herculex_workouts"
    private const val KEY_WORKOUTS = "workouts_json"

    val defaults: List<WorkoutTemplate> = listOf(
        WorkoutTemplate(
            id = "push_1", name = "Push Day",
            exercises = listOf(
                ExerciseTemplate("Bench Press",       4, 80.0,  8),
                ExerciseTemplate("Overhead Press",    4, 50.0,  8),
                ExerciseTemplate("Incline DB Press",  3, 24.0, 10),
                ExerciseTemplate("Lateral Raise",     3, 12.0, 15),
                ExerciseTemplate("Tricep Pushdown",   3, 25.0, 12),
            )
        ),
        WorkoutTemplate(
            id = "pull_1", name = "Pull Day",
            exercises = listOf(
                ExerciseTemplate("Deadlift",          4, 120.0, 5),
                ExerciseTemplate("Barbell Row",       4,  70.0, 8),
                ExerciseTemplate("Lat Pulldown",      3,  60.0, 10),
                ExerciseTemplate("Bicep Curl",        3,  15.0, 12),
                ExerciseTemplate("Face Pull",         3,  20.0, 15),
            )
        ),
        WorkoutTemplate(
            id = "lbw_1", name = "LBW I.",
            exercises = listOf(
                ExerciseTemplate("Squat",               4, 100.0, 6),
                ExerciseTemplate("Romanian Deadlift",   4,  70.0, 8),
                ExerciseTemplate("Leg Press",           3, 120.0, 10),
                ExerciseTemplate("Leg Curl",            3,  40.0, 12),
                ExerciseTemplate("Calf Raise",          4,  60.0, 15),
            )
        ),
        WorkoutTemplate(
            id = "lbw_2", name = "LBW II.",
            exercises = listOf(
                ExerciseTemplate("Good Morning (Barbell)", 4, 20.0, 10),
                ExerciseTemplate("SSB Squat",              4, 60.0,  6),
                ExerciseTemplate("Bulgarian Split Squat",  3, 20.0,  8),
                ExerciseTemplate("Nordic Hamstring",       3,  0.0,  6),
                ExerciseTemplate("Leg Extension",          3, 40.0, 12),
            )
        ),
        WorkoutTemplate(
            id = "upper_1", name = "Upper Body",
            exercises = listOf(
                ExerciseTemplate("Pull-Up",             4,  0.0, 8),
                ExerciseTemplate("DB Shoulder Press",   3, 20.0, 10),
                ExerciseTemplate("Cable Row",           3, 50.0, 12),
                ExerciseTemplate("DB Fly",              3, 16.0, 12),
                ExerciseTemplate("Hammer Curl",         3, 14.0, 12),
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

    fun parseAndStartSession(context: Context, json: String, viewModel: WorkoutViewModel?) {
        try {
            val obj = JSONObject(json)
            val template = parseTemplate(obj.getJSONObject("template"))
            viewModel?.startWorkout(template)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun parseAndUpdateSession(json: String, viewModel: WorkoutViewModel?) {
        try {
            val obj = JSONObject(json)
            val templateObj = obj.optJSONObject("template")
            val templateName = templateObj?.optString("name", "Active Workout") ?: "Active Workout"
            val currentExIdx = obj.optInt("currentExerciseIndex", 0)
            val currentSetIdx = obj.optInt("currentSetIndex", 0)
            val exArr = obj.optJSONArray("exercises") ?: JSONArray()
            val exercises = (0 until exArr.length()).map { i ->
                val exObj = exArr.getJSONObject(i)
                val templateObjItem = exObj.optJSONObject("template")
                val templateItem = if (templateObjItem != null) parseTemplateItem(templateObjItem) else ExerciseTemplate("Exercise", 3, 0.0, 0)
                val setsArr = exObj.optJSONArray("sets") ?: JSONArray()
                val sets = (0 until setsArr.length()).map { j ->
                    val sObj = setsArr.getJSONObject(j)
                    LoggedSet(
                        weight = sObj.optDouble("weight", 0.0),
                        reps = sObj.optInt("reps", 0),
                        rpe = if (sObj.has("rpe")) sObj.getInt("rpe") else null,
                        setType = sObj.optString("setType", "Normal"),
                        accessory = if (sObj.has("accessory")) sObj.getString("accessory") else null,
                        completed = sObj.optBoolean("completed", true),
                    )
                }
                ActiveExercise(template = templateItem, sets = sets)
            }
            viewModel?.updateSessionFromRemote(exercises, currentExIdx, currentSetIdx, templateName)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun sessionToJson(session: WorkoutSession): String {
        val obj = JSONObject()
        obj.put("template", templateToJson(session.template))
        obj.put("currentExerciseIndex", session.currentExerciseIndex)
        obj.put("currentSetIndex", session.currentSetIndex)
        val exArr = JSONArray()
        session.exercises.forEach { ex ->
            val exObj = JSONObject()
            exObj.put("template", templateItemToJson(ex.template))
            val setsArr = JSONArray()
            ex.sets.forEach { set ->
                val sObj = JSONObject()
                sObj.put("weight", set.weight)
                sObj.put("reps", set.reps)
                set.rpe?.let { sObj.put("rpe", it) }
                sObj.put("setType", set.setType)
                set.accessory?.let { sObj.put("accessory", it) }
                sObj.put("completed", set.completed)
                setsArr.put(sObj)
            }
            exObj.put("sets", setsArr)
            exArr.put(exObj)
        }
        obj.put("exercises", exArr)
        return obj.toString()
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

    private fun templateItemToJson(item: ExerciseTemplate): JSONObject {
        val obj = JSONObject()
        obj.put("name", item.name)
        obj.put("targetSets", item.targetSets)
        obj.put("prevWeight", item.prevWeight)
        obj.put("prevReps", item.prevReps)
        return obj
    }

    private fun parseTemplate(obj: JSONObject): WorkoutTemplate {
        val exArr = obj.getJSONArray("exercises")
        return WorkoutTemplate(
            id = obj.getString("id"),
            name = obj.getString("name"),
            exercises = (0 until exArr.length()).map { parseTemplateItem(exArr.getJSONObject(it)) }
        )
    }

    private fun parseTemplateItem(obj: JSONObject): ExerciseTemplate {
        return ExerciseTemplate(
            name = obj.getString("name"),
            targetSets = obj.getInt("targetSets"),
            prevWeight = obj.optDouble("prevWeight", 0.0),
            prevReps = obj.optInt("prevReps", 0),
        )
    }

    private fun parse(json: String): List<WorkoutTemplate> {
        val arr = JSONArray(json)
        return (0 until arr.length()).map { i ->
            parseTemplate(arr.getJSONObject(i))
        }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
