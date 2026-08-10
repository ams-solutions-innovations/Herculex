package com.ams.herculex.sync

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class QuickAddMealSlot(
    val key: String,
    val label: String,
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
)

/// Watch-side cache of the phone's recent/most-common foods and meal slots,
/// synced down as a single JSON blob (see `syncQuickAddFoodsToWear` on the
/// phone) so the watch can offer a tap-to-log list without its own catalogue.
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

    fun items(context: Context): List<QuickAddFoodItem> {
        val obj = rootObject(context) ?: return emptyList()
        val arr = obj.optJSONArray("items") ?: JSONArray()
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
    ): String {
        return JSONObject()
            .put("commandId", UUID.randomUUID().toString())
            .put("foodId", foodId)
            .put("mealKey", mealKey)
            .put("portionAmount", portionAmount)
            .put("portionUnit", portionUnit)
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
