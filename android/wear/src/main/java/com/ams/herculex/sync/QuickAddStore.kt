package com.ams.herculex.sync

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class QuickAddMealSlot(
    val key: String,
    val label: String,
)

data class LoggedFoodEntry(
    val id: Int,
    val name: String,
    val mealKey: String,
    val portionAmount: Double,
    val portionUnit: String,
    val portionText: String,
    val servings: Double,
    val kcal: Int,
    val protein: Int,
    val carbs: Int,
    val fat: Int,
    val foodId: Int? = null,
    val recipeId: Int? = null,
    val loggedAtEpochMs: Long = 0L,
)

data class QuickAddFoodItem(
    val foodId: Int,
    val name: String,
    val kcal: Int,
    val protein: Int,
    val carbs: Int,
    val fat: Int,
    val portionAmount: Double,
    val portionUnit: String,
    val portionLabel: String,
    /// Meal key (breakfast/lunch/dinner/snack) this food was most recently
    /// logged to on the phone, if any — lets the "+" quick-add button log
    /// with zero extra taps by reusing it instead of asking again.
    val lastMealKey: String? = null,
    /// Non-null when this item represents a user recipe ("My Recipes") rather
    /// than a catalogue food.
    val recipeId: Int? = null,
    val kcalPer100g: Double? = null,
) {
    val isRecipe: Boolean get() = recipeId != null && recipeId > 0

    val effectiveKcalPer100g: Double?
        get() = kcalPer100g ?: if (portionAmount > 0.0 && (portionUnit.equals("g", ignoreCase = true) || portionUnit.equals("ml", ignoreCase = true))) {
            (kcal.toDouble() / portionAmount) * 100.0
        } else null
}

/// Watch-side cache of the phone's suggested foods, recent foods, user
/// recipes, and meal slots, synced down as a single JSON blob (see
/// `syncQuickAddToWear` on the phone) so the watch can offer a categorized
/// tap-to-log list without its own catalogue.
object QuickAddStore {
    private const val PREFS = "herculex_quickadd"
    private const val KEY_JSON = "quickadd_json"

    fun save(context: Context, json: String) {
        prefs(context).edit().putString(KEY_JSON, json).apply()
    }

    fun mealSlots(context: Context): List<QuickAddMealSlot> {
        val obj = rootObject(context) ?: return emptyList()
        val arr = obj.optJSONArray("mealSlots") ?: JSONArray()
        return buildList(arr.length()) {
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                add(
                    QuickAddMealSlot(
                        key = item.optString("key", "snack"),
                        label = item.optString("label", "Snack"),
                    ),
                )
            }
        }
    }

    fun items(context: Context): List<QuickAddFoodItem> = suggestedItems(context)

    fun suggestedItems(context: Context): List<QuickAddFoodItem> {
        val obj = rootObject(context) ?: return emptyList()
        val arr = obj.optJSONArray("suggested") ?: obj.optJSONArray("items") ?: JSONArray()
        return parseItems(arr)
    }

    fun recentItems(context: Context): List<QuickAddFoodItem> {
        val obj = rootObject(context) ?: return emptyList()
        val arr = obj.optJSONArray("recent") ?: obj.optJSONArray("items") ?: JSONArray()
        return parseItems(arr)
    }

    fun recipeItems(context: Context): List<QuickAddFoodItem> {
        val obj = rootObject(context) ?: return emptyList()
        val arr = obj.optJSONArray("recipes") ?: JSONArray()
        return parseItems(arr)
    }

    private fun parseItems(arr: JSONArray): List<QuickAddFoodItem> {
        return buildList(arr.length()) {
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                add(
                    QuickAddFoodItem(
                        foodId = item.optInt("foodId"),
                        name = item.optString("name", "Food"),
                        kcal = item.optInt("kcal"),
                        protein = item.optInt("protein"),
                        carbs = item.optInt("carbs"),
                        fat = item.optInt("fat"),
                        portionAmount = item.optDouble("portionAmount", 100.0),
                        portionUnit = item.optString("portionUnit", "g"),
                        portionLabel = item.optString("portionLabel", "100 g"),
                        lastMealKey = if (!item.isNull("lastMealKey")) {
                            item.optString("lastMealKey").takeIf { it.isNotBlank() }
                        } else null,
                        recipeId = if (!item.isNull("recipeId")) {
                            item.optInt("recipeId", 0).takeIf { it > 0 }
                        } else null,
                        kcalPer100g = if (!item.isNull("kcalPer100g")) {
                            item.optDouble("kcalPer100g").takeIf { !it.isNaN() && it > 0 }
                        } else null,
                    ),
                )
            }
        }
    }

    fun createLogCommand(
        foodId: Int,
        mealKey: String,
        portionAmount: Double,
        portionUnit: String,
        recipeId: Int? = null,
    ): String {
        return JSONObject()
            .put("commandId", UUID.randomUUID().toString())
            .put("foodId", foodId)
            .apply {
                if (recipeId != null && recipeId > 0) {
                    put("recipeId", recipeId)
                }
            }
            .put("mealKey", mealKey)
            .put("portionAmount", portionAmount)
            .put("portionUnit", portionUnit)
            .put("createdAtEpochMs", System.currentTimeMillis())
            .toString()
    }

    fun loggedEntries(context: Context): List<LoggedFoodEntry> {
        val obj = rootObject(context) ?: return emptyList()
        val arr = obj.optJSONArray("loggedEntries") ?: JSONArray()
        return buildList(arr.length()) {
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                add(
                    LoggedFoodEntry(
                        id = item.optInt("id"),
                        name = item.optString("name", "Food"),
                        mealKey = item.optString("mealKey", "snack"),
                        portionAmount = item.optDouble("portionAmount", 100.0),
                        portionUnit = item.optString("portionUnit", "g"),
                        portionText = item.optString("portionText", ""),
                        servings = item.optDouble("servings", 1.0),
                        kcal = item.optInt("kcal"),
                        protein = item.optInt("protein"),
                        carbs = item.optInt("carbs"),
                        fat = item.optInt("fat"),
                        foodId = if (!item.isNull("foodId")) item.optInt("foodId").takeIf { it > 0 } else null,
                        recipeId = if (!item.isNull("recipeId")) item.optInt("recipeId").takeIf { it > 0 } else null,
                        loggedAtEpochMs = item.optLong("loggedAtEpochMs", 0L),
                    ),
                )
            }
        }
    }

    fun deleteLoggedEntryLocally(context: Context, entryId: Int) {
        val obj = rootObject(context) ?: return
        val arr = obj.optJSONArray("loggedEntries") ?: return
        val newArr = JSONArray()
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            if (item.optInt("id") != entryId) {
                newArr.put(item)
            }
        }
        obj.put("loggedEntries", newArr)
        save(context, obj.toString())
    }

    fun updateLoggedEntryLocally(
        context: Context,
        entryId: Int,
        newMealKey: String,
        newAmount: Double,
        newUnit: String,
        newPortionText: String,
        newKcal: Int,
        newProtein: Int,
        newCarbs: Int,
        newFat: Int,
        newServings: Double,
    ) {
        val obj = rootObject(context) ?: return
        val arr = obj.optJSONArray("loggedEntries") ?: return
        val newArr = JSONArray()
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            if (item.optInt("id") == entryId) {
                item.put("mealKey", newMealKey)
                item.put("portionAmount", newAmount)
                item.put("portionUnit", newUnit)
                item.put("portionText", newPortionText)
                item.put("kcal", newKcal)
                item.put("protein", newProtein)
                item.put("carbs", newCarbs)
                item.put("fat", newFat)
                item.put("servings", newServings)
            }
            newArr.put(item)
        }
        obj.put("loggedEntries", newArr)
        save(context, obj.toString())
    }

    fun createDeleteCommand(entryId: Int): String {
        return JSONObject()
            .put("commandId", UUID.randomUUID().toString())
            .put("action", "delete")
            .put("entryId", entryId)
            .put("createdAtEpochMs", System.currentTimeMillis())
            .toString()
    }

    fun createUpdateCommand(
        entryId: Int,
        mealKey: String,
        portionAmount: Double,
        portionUnit: String,
        servings: Double,
    ): String {
        return JSONObject()
            .put("commandId", UUID.randomUUID().toString())
            .put("action", "update")
            .put("entryId", entryId)
            .put("mealKey", mealKey)
            .put("portionAmount", portionAmount)
            .put("portionUnit", portionUnit)
            .put("servings", servings)
            .put("createdAtEpochMs", System.currentTimeMillis())
            .toString()
    }

    private fun rootObject(context: Context): JSONObject? {
        val json = prefs(context).getString(KEY_JSON, null) ?: return null
        return runCatching { JSONObject(json) }.getOrNull()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
