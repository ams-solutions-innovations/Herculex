package com.ams.herculex.workout

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Tracks exercise usage frequency and recency on Wear OS so that
 * the exercise picker prioritizes Most Frequent -> Recent -> All Catalog.
 */
object ExerciseUsageTracker {
    private const val PREFS = "herculex_exercise_usage"
    private const val KEY_USAGE_COUNTS = "usage_counts"
    private const val KEY_RECENT_LIST = "recent_exercises"

    /**
     * Resolves a stable identifier key for an exercise template.
     */
    fun exerciseKey(exercise: ExerciseTemplate): String {
        return exercise.slug?.takeIf { it.isNotBlank() }
            ?: exercise.catalogExerciseId?.let { "id_$it" }
            ?: exercise.name.lowercase().trim()
    }

    /**
     * Records an exercise as being used (added, substituted, or performed).
     */
    fun recordUsed(context: Context, exercise: ExerciseTemplate) {
        try {
            val key = exerciseKey(exercise)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            // 1. Increment frequency count
            val countsJson = prefs.getString(KEY_USAGE_COUNTS, "{}") ?: "{}"
            val counts = JSONObject(countsJson)
            val currentCount = counts.optInt(key, 0)
            counts.put(key, currentCount + 1)

            // 2. Update recency list (MRU, max 20)
            val recentsJson = prefs.getString(KEY_RECENT_LIST, "[]") ?: "[]"
            val recents = JSONArray(recentsJson)
            val list = (0 until recents.length())
                .map { recents.getString(it) }
                .filter { it != key }
                .toMutableList()
            list.add(0, key)
            val trimmed = list.take(20)

            prefs.edit()
                .putString(KEY_USAGE_COUNTS, counts.toString())
                .putString(KEY_RECENT_LIST, JSONArray(trimmed).toString())
                .apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Returns the recorded usage count for a given exercise.
     */
    fun getUsageCount(context: Context, exercise: ExerciseTemplate): Int {
        return try {
            val key = exerciseKey(exercise)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val countsJson = prefs.getString(KEY_USAGE_COUNTS, "{}") ?: "{}"
            val counts = JSONObject(countsJson)
            counts.optInt(key, 0)
        } catch (e: Exception) {
            0
        }
    }

    /**
     * Returns the ordered list of recently used exercise keys.
     */
    fun getRecentKeys(context: Context): List<String> {
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val recentsJson = prefs.getString(KEY_RECENT_LIST, "[]") ?: "[]"
            val recents = JSONArray(recentsJson)
            (0 until recents.length()).map { recents.getString(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Calculates a combined frequency score for a catalog exercise
     * based on:
     * - Occurrences in saved/synced workout routines (e.g. Push, Pull, Legs, active program)
     * - Recorded logged usage counts
     */
    fun calculateScore(
        context: Context,
        exercise: ExerciseTemplate,
        templateOccurrences: Map<String, Int>
    ): Int {
        val key = exerciseKey(exercise)
        val routineWeight = (templateOccurrences[key] ?: 0) * 10
        val usageWeight = getUsageCount(context, exercise) * 3
        return routineWeight + usageWeight
    }
}
