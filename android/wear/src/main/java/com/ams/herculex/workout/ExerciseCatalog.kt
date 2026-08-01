package com.ams.herculex.workout

import android.content.Context
import org.json.JSONArray

object ExerciseCatalog {
    private const val PREFS = "herculex_catalog"
    private const val KEY_CATALOG = "catalog_json"

    val defaultCategories = listOf(
        "Chest" to listOf(
            ExerciseTemplate("Bench Press", 4, 80.0, 8),
            ExerciseTemplate("Incline DB Press", 3, 24.0, 10),
            ExerciseTemplate("Dumbbell Fly", 3, 16.0, 12),
            ExerciseTemplate("Dips", 3, 0.0, 10),
            ExerciseTemplate("Push-Up", 3, 0.0, 15),
            ExerciseTemplate("Cable Fly", 3, 15.0, 12),
        ),
        "Back" to listOf(
            ExerciseTemplate("Deadlift", 4, 120.0, 5),
            ExerciseTemplate("Barbell Row", 4, 70.0, 8),
            ExerciseTemplate("Lat Pulldown", 3, 60.0, 10),
            ExerciseTemplate("Pull-Up", 4, 0.0, 8),
            ExerciseTemplate("Cable Row", 3, 50.0, 12),
            ExerciseTemplate("Dumbbell Row", 3, 24.0, 10),
            ExerciseTemplate("Face Pull", 3, 20.0, 15),
        ),
        "Legs" to listOf(
            ExerciseTemplate("Squat", 4, 100.0, 6),
            ExerciseTemplate("Romanian Deadlift", 4, 70.0, 8),
            ExerciseTemplate("Leg Press", 3, 120.0, 10),
            ExerciseTemplate("Leg Extension", 3, 40.0, 12),
            ExerciseTemplate("Leg Curl", 3, 40.0, 12),
            ExerciseTemplate("Good Morning", 4, 20.0, 10),
            ExerciseTemplate("Bulgarian Split Squat", 3, 20.0, 8),
            ExerciseTemplate("Calf Raise", 4, 60.0, 15),
        ),
        "Shoulders" to listOf(
            ExerciseTemplate("Overhead Press", 4, 50.0, 8),
            ExerciseTemplate("DB Shoulder Press", 3, 20.0, 10),
            ExerciseTemplate("Lateral Raise", 3, 12.0, 15),
            ExerciseTemplate("Rear Delt Fly", 3, 10.0, 15),
            ExerciseTemplate("Barbell Shrug", 4, 80.0, 12),
        ),
        "Arms" to listOf(
            ExerciseTemplate("Bicep Curl", 3, 15.0, 12),
            ExerciseTemplate("Hammer Curl", 3, 14.0, 12),
            ExerciseTemplate("Preacher Curl", 3, 12.5, 10),
            ExerciseTemplate("Tricep Pushdown", 3, 25.0, 12),
            ExerciseTemplate("Skullcrusher", 3, 30.0, 10),
            ExerciseTemplate("Overhead Tricep Ext", 3, 20.0, 12),
        ),
    )

    val defaultAll: List<ExerciseTemplate> get() = defaultCategories.flatMap { it.second }

    fun getAll(context: Context): List<ExerciseTemplate> {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CATALOG, null)
        if (json.isNullOrBlank()) return defaultAll
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                ExerciseTemplate(
                    name = obj.getString("name"),
                    targetSets = obj.optInt("targetSets", 3),
                    prevWeight = obj.optDouble("prevWeight", 0.0),
                    prevReps = obj.optInt("prevReps", 0)
                )
            }
        } catch (e: Exception) {
            defaultAll
        }
    }

    fun saveJson(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CATALOG, json)
            .apply()
    }
}
