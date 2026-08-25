package com.ams.herculex.sync

import android.content.Context
import org.json.JSONObject
import java.util.UUID

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
    private const val KEY_WEEKLY_TONNAGE = "weekly_tonnage"
    private const val KEY_WEEKLY_SETS    = "weekly_sets"
    private const val KEY_WEEKLY_VOLUME_JSON = "weekly_volume_json"
    private const val KEY_NUTRIENT_TRENDS_JSON = "nutrient_trends_json"
    private const val KEY_DAY = "macro_day"

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
            // The phone is the source of truth for "today", so a full push
            // also stamps the day key — this is what lets a watch-side
            // addFood/addCalories/addWater made right after this push detect
            // it's still the same day and add on top rather than reset.
            .putString(KEY_DAY, todayKey())
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
        rolloverIfNeeded(context)
        val p = prefs(context)
        p.edit().putInt(KEY_CALORIES, p.getInt(KEY_CALORIES, 0) + amount).apply()
    }

    fun addWater(context: Context, amountMl: Int) {
        rolloverIfNeeded(context)
        val p = prefs(context)
        p.edit().putInt(KEY_WATER, p.getInt(KEY_WATER, 0) + amountMl).apply()
    }

    fun addFood(context: Context, calories: Int, protein: Int, carbs: Int, fats: Int) {
        rolloverIfNeeded(context)
        val p = prefs(context)
        p.edit()
            .putInt(KEY_CALORIES, p.getInt(KEY_CALORIES, 0) + calories)
            .putInt(KEY_PROTEIN,  p.getInt(KEY_PROTEIN,  0) + protein)
            .putInt(KEY_CARBS,    p.getInt(KEY_CARBS,    0) + carbs)
            .putInt(KEY_FATS,     p.getInt(KEY_FATS,     0) + fats)
            .apply()
    }

    /// Watch -> phone command for a local macro/water quick add (Phase 5,
    /// ENG-16 "missing nutrition sync") — mirrors [FastingStore.createCommand]/
    /// `QuickAddStore.createLogCommand`'s shape. [kind] is one of
    /// "calories"/"water"/"food"; only the fields relevant to that kind are
    /// non-zero, but all are always present so the phone-side decoder doesn't
    /// need per-kind optional handling.
    fun createCommand(
        kind: String,
        calories: Int = 0,
        protein: Int = 0,
        carbs: Int = 0,
        fats: Int = 0,
        waterMl: Int = 0,
    ): String {
        return JSONObject()
            .put("commandId", UUID.randomUUID().toString())
            .put("kind", kind)
            .put("calories", calories)
            .put("protein", protein)
            .put("carbs", carbs)
            .put("fats", fats)
            .put("waterMl", waterMl)
            .put("createdAtEpochMs", System.currentTimeMillis())
            .toString()
    }

    // ── Readers ──────────────────────────────────────────────────────────────

    fun calories(context: Context): Int    { rolloverIfNeeded(context); return prefs(context).getInt(KEY_CALORIES, 0) }
    fun protein(context: Context): Int     { rolloverIfNeeded(context); return prefs(context).getInt(KEY_PROTEIN, 0) }
    fun carbs(context: Context): Int       { rolloverIfNeeded(context); return prefs(context).getInt(KEY_CARBS, 0) }
    fun fats(context: Context): Int        { rolloverIfNeeded(context); return prefs(context).getInt(KEY_FATS, 0) }
    fun fasting(context: Context): String  = prefs(context).getString(KEY_FASTING, "0h 0m") ?: "0h 0m"
    fun water(context: Context): Int       { rolloverIfNeeded(context); return prefs(context).getInt(KEY_WATER, 0) }

    fun calorieGoal(context: Context): Int = prefs(context).getInt(KEY_CALORIE_GOAL, 2000)
    fun proteinGoal(context: Context): Int = prefs(context).getInt(KEY_PROTEIN_GOAL, 150)
    fun carbsGoal(context: Context): Int   = prefs(context).getInt(KEY_CARBS_GOAL, 200)
    fun fatGoal(context: Context): Int     = prefs(context).getInt(KEY_FAT_GOAL, 65)
    fun waterGoal(context: Context): Int   = prefs(context).getInt(KEY_WATER_GOAL, 2000)

    fun weeklyTonnage(context: Context): Float = prefs(context).getFloat(KEY_WEEKLY_TONNAGE, 0f)
    fun weeklySets(context: Context): Int      = prefs(context).getInt(KEY_WEEKLY_SETS, 0)
    fun weeklyVolumeJson(context: Context): String = prefs(context).getString(KEY_WEEKLY_VOLUME_JSON, "[]") ?: "[]"
    fun nutrientTrendsJson(context: Context): String = prefs(context).getString(KEY_NUTRIENT_TRENDS_JSON, "[]") ?: "[]"

    fun saveWeeklyVolume(context: Context, tonnage: Double, sets: Int, json: String) {
        prefs(context).edit()
            .putFloat(KEY_WEEKLY_TONNAGE, tonnage.toFloat())
            .putInt(KEY_WEEKLY_SETS, sets)
            .putString(KEY_WEEKLY_VOLUME_JSON, json)
            .apply()
    }

    fun saveNutrientTrends(context: Context, json: String) {
        prefs(context).edit()
            .putString(KEY_NUTRIENT_TRENDS_JSON, json)
            .apply()
    }

    // ── Day rollover ─────────────────────────────────────────────────────────

    private fun todayKey(): String {
        val cal = java.util.Calendar.getInstance()
        return "%04d-%02d-%02d".format(
            cal.get(java.util.Calendar.YEAR),
            cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH),
        )
    }

    /// `addCalories`/`addWater`/`addFood` only ever add to whatever is already
    /// persisted, and the readers just return whatever's persisted — neither
    /// knows the stored totals are from a previous day. Without this, a
    /// watch-side quick-add (or a screen opened) after midnight but before
    /// the phone's next full [save] push piles the new entry on top of
    /// yesterday's leftover numbers instead of starting the new day at zero.
    /// [fasting]/weekly-tonnage/nutrient-trends are intentionally untouched —
    /// fasting spans midnight by design, and the weekly stats aren't daily.
    private fun rolloverIfNeeded(context: Context) {
        val p = prefs(context)
        val today = todayKey()
        if (p.getString(KEY_DAY, null) != today) {
            p.edit()
                .putInt(KEY_CALORIES, 0)
                .putInt(KEY_PROTEIN, 0)
                .putInt(KEY_CARBS, 0)
                .putInt(KEY_FATS, 0)
                .putInt(KEY_WATER, 0)
                .putString(KEY_DAY, today)
                .apply()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
