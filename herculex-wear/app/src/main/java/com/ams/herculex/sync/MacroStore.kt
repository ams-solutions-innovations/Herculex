package com.ams.herculex.sync

import android.content.Context

/// Single source of truth on the watch for the latest macros pushed from the
/// phone. Backed by SharedPreferences so tiles and complications (separate
/// processes/services) all read the same values.
object MacroStore {
    private const val PREFS = "herculex_macros"

    // Tracked values
    private const val KEY_CALORIES = "calories"
    private const val KEY_PROTEIN  = "protein"
    private const val KEY_CARBS    = "carbs"
    private const val KEY_FATS     = "fats"
    private const val KEY_FASTING  = "fasting"
    private const val KEY_WATER    = "water"

    // Daily goals (synced from phone or defaulted)
    private const val KEY_CALORIE_GOAL = "calorie_goal"
    private const val KEY_PROTEIN_GOAL = "protein_goal"
    private const val KEY_CARBS_GOAL   = "carbs_goal"
    private const val KEY_FAT_GOAL     = "fat_goal"
    private const val KEY_WATER_GOAL   = "water_goal"

    // ── Full sync from phone ─────────────────────────────────────────────────

    fun save(
        context: Context,
        calories: Int,
        protein: Int,
        carbs: Int,
        fats: Int,
        fasting: String
    ) {
        prefs(context).edit()
            .putInt(KEY_CALORIES, calories)
            .putInt(KEY_PROTEIN, protein)
            .putInt(KEY_CARBS, carbs)
            .putInt(KEY_FATS, fats)
            .putString(KEY_FASTING, fasting)
            .apply()
    }

    fun saveGoals(
        context: Context,
        calorieGoal: Int,
        proteinGoal: Int,
        carbsGoal: Int,
        fatGoal: Int,
        waterGoal: Int
    ) {
        prefs(context).edit()
            .putInt(KEY_CALORIE_GOAL, calorieGoal)
            .putInt(KEY_PROTEIN_GOAL, proteinGoal)
            .putInt(KEY_CARBS_GOAL, carbsGoal)
            .putInt(KEY_FAT_GOAL, fatGoal)
            .putInt(KEY_WATER_GOAL, waterGoal)
            .apply()
    }

    // ── Watch-side additions ─────────────────────────────────────────────────

    fun addCalories(context: Context, amount: Int) {
        val p = prefs(context)
        p.edit().putInt(KEY_CALORIES, p.getInt(KEY_CALORIES, 0) + amount).apply()
    }

    fun addWater(context: Context, amountMl: Int) {
        val p = prefs(context)
        p.edit().putInt(KEY_WATER, p.getInt(KEY_WATER, 0) + amountMl).apply()
    }

    fun addFood(context: Context, calories: Int, protein: Int, carbs: Int, fats: Int) {
        val p = prefs(context)
        p.edit()
            .putInt(KEY_CALORIES, p.getInt(KEY_CALORIES, 0) + calories)
            .putInt(KEY_PROTEIN,  p.getInt(KEY_PROTEIN,  0) + protein)
            .putInt(KEY_CARBS,    p.getInt(KEY_CARBS,    0) + carbs)
            .putInt(KEY_FATS,     p.getInt(KEY_FATS,     0) + fats)
            .apply()
    }

    // ── Readers ──────────────────────────────────────────────────────────────

    fun calories(context: Context): Int    = prefs(context).getInt(KEY_CALORIES, 0)
    fun protein(context: Context): Int     = prefs(context).getInt(KEY_PROTEIN, 0)
    fun carbs(context: Context): Int       = prefs(context).getInt(KEY_CARBS, 0)
    fun fats(context: Context): Int        = prefs(context).getInt(KEY_FATS, 0)
    fun fasting(context: Context): String  = prefs(context).getString(KEY_FASTING, "0h 0m") ?: "0h 0m"
    fun water(context: Context): Int       = prefs(context).getInt(KEY_WATER, 0)

    fun calorieGoal(context: Context): Int = prefs(context).getInt(KEY_CALORIE_GOAL, 2000)
    fun proteinGoal(context: Context): Int = prefs(context).getInt(KEY_PROTEIN_GOAL, 150)
    fun carbsGoal(context: Context): Int   = prefs(context).getInt(KEY_CARBS_GOAL, 200)
    fun fatGoal(context: Context): Int     = prefs(context).getInt(KEY_FAT_GOAL, 65)
    fun waterGoal(context: Context): Int   = prefs(context).getInt(KEY_WATER_GOAL, 2000)

    // ─────────────────────────────────────────────────────────────────────────

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
