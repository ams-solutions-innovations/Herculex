package com.ams.herculex.workout

import android.content.Context
import com.ams.herculex.sync.WearSyncContract
import org.json.JSONArray
import org.json.JSONObject

object ExerciseCatalog {
    private const val PREFS = "herculex_catalog"
    private const val KEY_CATALOG = "catalog_json"

    /// Display labels for the phone's modality ids. Kept in lockstep with
    /// `lib/features/workouts/domain/equipment_variants.dart`.
    private val equipmentLabels = mapOf(
        "barbell" to "Barbell",
        "dumbbell" to "Dumbbell",
        "smith" to "Smith Machine",
        "cable" to "Cable",
        "machine_plate" to "Machine (Plate-Loaded)",
        "machine_selectorized" to "Machine (Selectorized)",
        "kettlebell" to "Kettlebell",
        "band" to "Band",
        "bodyweight" to "Bodyweight",
        "other" to "Other",
    )

    fun equipmentLabel(variant: String): String = equipmentLabels[variant] ?: variant

    /// Cold-start fallback shown before the phone has ever pushed its catalog.
    ///
    /// Names and slugs are the phone catalog's own, so an exercise picked from
    /// here still resolves to the real row instead of creating a custom one.
    /// This list is deliberately small — it is insurance, not a catalog.
    val defaultCategories = listOf(
        "Chest" to listOf(
            ExerciseTemplate("Barbell Bench Press", 4, 80.0, 8, slug = "barbell-bench-press"),
            ExerciseTemplate("Incline Dumbbell Press", 3, 24.0, 10, slug = "incline-dumbbell-press"),
            ExerciseTemplate("Dumbbell Fly", 3, 16.0, 12, slug = "dumbbell-fly"),
            ExerciseTemplate("Dip", 3, 0.0, 10, slug = "chest-dips"),
            ExerciseTemplate("Standard Push-Up", 3, 0.0, 15, slug = "standard-push-up"),
            ExerciseTemplate("Cable Fly (High to Low)", 3, 15.0, 12, slug = "cable-fly-high-to-low"),
        ),
        "Back" to listOf(
            ExerciseTemplate("Conventional Deadlift", 4, 120.0, 5, slug = "conventional-deadlift"),
            ExerciseTemplate("Barbell Row", 4, 70.0, 8, slug = "barbell-row"),
            ExerciseTemplate("Lat Pulldown", 3, 60.0, 10, slug = "lat-pulldown"),
            ExerciseTemplate("Pull-Up", 4, 0.0, 8, slug = "pull-up"),
            ExerciseTemplate("Seated Cable Row (V-Bar)", 3, 50.0, 12, slug = "seated-cable-row-v-bar"),
            ExerciseTemplate("Single-Arm Dumbbell Row", 3, 24.0, 10, slug = "single-arm-dumbbell-row"),
            ExerciseTemplate("Face Pull", 3, 20.0, 15, slug = "face-pull"),
        ),
        "Legs" to listOf(
            ExerciseTemplate("Barbell Back Squat", 4, 100.0, 6, slug = "barbell-back-squat"),
            ExerciseTemplate("Romanian Deadlift", 4, 70.0, 8, slug = "romanian-deadlift"),
            ExerciseTemplate("Leg Press", 3, 120.0, 10, slug = "leg-press"),
            ExerciseTemplate("Leg Extension", 3, 40.0, 12, slug = "leg-extension"),
            ExerciseTemplate("Lying Leg Curl", 3, 40.0, 12, slug = "lying-leg-curl"),
            ExerciseTemplate("Good Morning", 4, 20.0, 10, slug = "good-morning"),
            ExerciseTemplate("Bulgarian Split Squat", 3, 20.0, 8, slug = "bulgarian-split-squat"),
            ExerciseTemplate("Standing Calf Raise", 4, 60.0, 15, slug = "standing-calf-raise"),
        ),
        "Shoulders" to listOf(
            ExerciseTemplate("Overhead Press", 4, 50.0, 8, slug = "overhead-press"),
            ExerciseTemplate("Dumbbell Overhead Press", 3, 20.0, 10, slug = "dumbbell-overhead-press"),
            ExerciseTemplate("Dumbbell Lateral Raise", 3, 12.0, 15, slug = "dumbbell-lateral-raise"),
            ExerciseTemplate("Dumbbell Rear Delt Fly", 3, 10.0, 15, slug = "dumbbell-rear-delt-fly"),
            ExerciseTemplate("Barbell Shrug", 4, 80.0, 12, slug = "barbell-shrug"),
        ),
        "Arms" to listOf(
            ExerciseTemplate("Dumbbell Curl", 3, 15.0, 12, slug = "dumbbell-curl"),
            ExerciseTemplate("Hammer Curl", 3, 14.0, 12, slug = "hammer-curl"),
            ExerciseTemplate("EZ Bar Preacher Curl", 3, 12.5, 10, slug = "ez-bar-preacher-curl"),
            ExerciseTemplate("Tricep Pushdown (Rope)", 3, 25.0, 12, slug = "tricep-pushdown-rope"),
            ExerciseTemplate("Skullcrusher", 3, 30.0, 10, slug = "skullcrusher"),
            ExerciseTemplate("Overhead Cable Tricep", 3, 20.0, 12, slug = "overhead-cable-tricep"),
        ),
    )

    val defaultAll: List<ExerciseTemplate> get() = defaultCategories.flatMap { it.second }

    fun getAll(context: Context): List<ExerciseTemplate> {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CATALOG, null)
        if (json.isNullOrBlank()) return defaultAll
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i -> parse(array.getJSONObject(i)) }
        } catch (e: Exception) {
            defaultAll
        }
    }

    /// Shared by the catalog and by [WorkoutStore], so identity fields can only
    /// ever be dropped in one place.
    fun parse(obj: JSONObject): ExerciseTemplate {
        val optionsArr = obj.optJSONArray("equipmentOptions")
        val plannedArr = obj.optJSONArray("plannedSets")
        val plannedSets = if (plannedArr == null) {
            emptyList()
        } else {
            (0 until plannedArr.length()).map { index ->
                val set = plannedArr.getJSONObject(index)
                val rawSetType = set.optString("setType", "standard")
                PlannedSet(
                    wireId = set.optString("wireId").takeIf { it.isNotBlank() },
                    setIndex = set.optInt("setIndex", index),
                    setType = WearSyncContract.normalizeSetType(rawSetType),
                    isWarmup = WearSyncContract.normalizeIsWarmup(rawSetType, set.optBoolean("isWarmup", false)),
                    targetReps = set.optNullableInt("targetReps"),
                    targetRepsMin = set.optNullableInt("targetRepsMin"),
                    targetRepsMax = set.optNullableInt("targetRepsMax"),
                    targetWeightKg = set.optNullableDouble("targetWeightKg"),
                    setTypeMetaJson = set.optString("setTypeMetaJson").takeIf { it.isNotBlank() && it != "null" },
                )
            }
        }
        return ExerciseTemplate(
            name = obj.getString("name"),
            targetSets = obj.optInt("targetSets", 3),
            prevWeight = obj.optDouble("prevWeight", 0.0),
            prevReps = obj.optInt("prevReps", 0),
            catalogExerciseId = if (!obj.isNull("catalogExerciseId")) obj.optInt("catalogExerciseId") else null,
            slug = if (!obj.isNull("slug")) obj.optString("slug").takeIf { it.isNotBlank() } else null,
            equipmentOptions = if (optionsArr == null) emptyList() else {
                (0 until optionsArr.length()).mapNotNull { optionsArr.optString(it).takeIf { s -> s.isNotBlank() } }
            },
            equipmentVariant = if (!obj.isNull("equipmentVariant")) {
                obj.optString("equipmentVariant").takeIf { it.isNotBlank() }
            } else null,
            plannedSets = plannedSets,
        )
    }

    fun toJson(item: ExerciseTemplate): JSONObject {
        val obj = JSONObject()
        obj.put("name", item.name)
        obj.put("targetSets", item.targetSets)
        obj.put("prevWeight", item.prevWeight)
        obj.put("prevReps", item.prevReps)
        item.catalogExerciseId?.let { obj.put("catalogExerciseId", it) }
        item.slug?.let { obj.put("slug", it) }
        item.equipmentVariant?.let { obj.put("equipmentVariant", it) }
        if (item.equipmentOptions.isNotEmpty()) {
            obj.put("equipmentOptions", JSONArray(item.equipmentOptions))
        }
        if (item.plannedSets.isNotEmpty()) {
            val planned = JSONArray()
            item.plannedSets.forEach { set ->
                planned.put(
                    JSONObject()
                        .put("wireId", set.wireId)
                        .put("setIndex", set.setIndex)
                        .put("setType", set.setType)
                        .put("isWarmup", set.isWarmup)
                        .put("targetReps", set.targetReps)
                        .put("targetRepsMin", set.targetRepsMin)
                        .put("targetRepsMax", set.targetRepsMax)
                        .put("targetWeightKg", set.targetWeightKg)
                        .put("setTypeMetaJson", set.setTypeMetaJson)
                )
            }
            obj.put("plannedSets", planned)
        }
        return obj
    }

    fun saveJson(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CATALOG, json)
            .apply()
    }

    private fun JSONObject.optNullableInt(name: String): Int? {
        if (!has(name) || isNull(name)) return null
        return optInt(name)
    }

    private fun JSONObject.optNullableDouble(name: String): Double? {
        if (!has(name) || isNull(name)) return null
        return optDouble(name)
    }
}
