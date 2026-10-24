package com.ams.herculex.sync

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Phase 5 of docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md
 * ("manjkajoča nutrition sinhronizacija") — [MacroStore.createCommand] is the
 * new watch -> phone command builder backing `NutritionViewModel.addCalories`/
 * `addWater`/`logFood`, mirroring `FastingStore.createCommand`/
 * `QuickAddStore.createLogCommand`. Doesn't touch `Context`, but still needs
 * `@RunWith(RobolectricTestRunner::class)` — `org.json.JSONObject` itself is
 * only a stub on the plain-JUnit unit-test classpath (throws
 * `RuntimeException` on every real method call unless Robolectric shadows
 * it in), the same reason every other JSON-touching test in this module
 * already runs under Robolectric.
 */
@RunWith(RobolectricTestRunner::class)
class MacroStoreTest {

    @Test
    fun `createCommand carries kind and only the fields relevant to it`() {
        val json = JSONObject(MacroStore.createCommand(kind = "water", waterMl = 500))

        assertEquals("water", json.getString("kind"))
        assertEquals(500, json.getInt("waterMl"))
        assertEquals(0, json.getInt("calories"))
        assertEquals(0, json.getInt("protein"))
        assertEquals(0, json.getInt("carbs"))
        assertEquals(0, json.getInt("fats"))
        assertTrue(json.getString("commandId").isNotBlank())
        assertTrue(json.getLong("createdAtEpochMs") > 0L)
    }

    @Test
    fun `createCommand for a food entry carries all four macros`() {
        val json = JSONObject(
            MacroStore.createCommand(kind = "food", calories = 250, protein = 20, carbs = 30, fats = 8),
        )

        assertEquals("food", json.getString("kind"))
        assertEquals(250, json.getInt("calories"))
        assertEquals(20, json.getInt("protein"))
        assertEquals(30, json.getInt("carbs"))
        assertEquals(8, json.getInt("fats"))
        assertEquals(0, json.getInt("waterMl"))
    }

    @Test
    fun `two calls mint distinct commandIds`() {
        val first = JSONObject(MacroStore.createCommand(kind = "calories", calories = 200))
        val second = JSONObject(MacroStore.createCommand(kind = "calories", calories = 200))

        assertNotEquals(first.getString("commandId"), second.getString("commandId"))
    }

    @Test
    fun `QuickAddStore parses suggested, recent, and recipes sections and builds recipe log command`() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val payload = """
            {
              "mealSlots": [{"key": "lunch", "label": "Lunch"}],
              "suggested": [{"foodId": 10, "name": "Oats", "kcal": 350, "protein": 12, "carbs": 60, "fat": 6, "portionAmount": 100, "portionUnit": "g", "portionLabel": "100 g"}],
              "recent": [{"foodId": 20, "name": "Chicken Breast", "kcal": 165, "protein": 31, "carbs": 0, "fat": 4, "portionAmount": 100, "portionUnit": "g", "portionLabel": "100 g"}],
              "recipes": [{"foodId": 0, "recipeId": 7, "name": "Protein Shake", "kcal": 420, "protein": 45, "carbs": 38, "fat": 9, "portionAmount": 1, "portionUnit": "serving", "portionLabel": "1 serving", "lastMealKey": "lunch"}]
            }
        """.trimIndent()
        QuickAddStore.save(context, payload)

        val suggested = QuickAddStore.suggestedItems(context)
        val recent = QuickAddStore.recentItems(context)
        val recipes = QuickAddStore.recipeItems(context)

        assertEquals(1, suggested.size)
        assertEquals("Oats", suggested[0].name)
        assertEquals(1, recent.size)
        assertEquals("Chicken Breast", recent[0].name)
        assertEquals(1, recipes.size)
        assertEquals("Protein Shake", recipes[0].name)
        assertEquals(7, recipes[0].recipeId)
        assertTrue(recipes[0].isRecipe)

        val recipeCmd = JSONObject(
            QuickAddStore.createLogCommand(
                foodId = recipes[0].foodId,
                mealKey = "lunch",
                portionAmount = 1.5,
                portionUnit = "serving",
                recipeId = recipes[0].recipeId,
            ),
        )
        assertEquals(7, recipeCmd.getInt("recipeId"))
        assertEquals(1.5, recipeCmd.getDouble("portionAmount"), 0.001)
    }

    @Test
    fun `save rejects stale dayKey from yesterday so it cannot overwrite today's intake`() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val cal = java.util.Calendar.getInstance()
        val todayStr = "%04d-%02d-%02d".format(
            cal.get(java.util.Calendar.YEAR),
            cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH),
        )
        val yesterdayCal = java.util.Calendar.getInstance().apply { add(java.util.Calendar.DAY_OF_YEAR, -1) }
        val yesterdayStr = "%04d-%02d-%02d".format(
            yesterdayCal.get(java.util.Calendar.YEAR),
            yesterdayCal.get(java.util.Calendar.MONTH) + 1,
            yesterdayCal.get(java.util.Calendar.DAY_OF_MONTH),
        )

        // Today was already reset or has fresh 100 kcal
        MacroStore.save(context, calories = 100, protein = 10, carbs = 15, fats = 2, fasting = "0h", dayKey = todayStr)
        assertEquals(100, MacroStore.calories(context))

        // Phone pushes stale yesterday packet (e.g. 2500 kcal)
        MacroStore.save(context, calories = 2500, protein = 180, carbs = 250, fats = 70, fasting = "16h", dayKey = yesterdayStr)

        // Must still be 100 kcal, not overwritten by yesterday's 2500!
        assertEquals(100, MacroStore.calories(context))
        assertEquals(10, MacroStore.protein(context))
    }

    @Test
    fun `rolloverIfNeeded resets daily totals when calendar day changes`() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val prefs = context.getSharedPreferences("herculex_macros", android.content.Context.MODE_PRIVATE)

        // Set up leftover macros from yesterday
        prefs.edit()
            .putInt("calories", 2200)
            .putInt("protein", 160)
            .putInt("carbs", 200)
            .putInt("fats", 65)
            .putInt("water", 1800)
            .putString("macro_day", "2020-01-01") // distant past
            .apply()

        MacroStore.rolloverIfNeeded(context)

        assertEquals(0, MacroStore.calories(context))
        assertEquals(0, MacroStore.protein(context))
        assertEquals(0, MacroStore.carbs(context))
        assertEquals(0, MacroStore.fats(context))
        assertEquals(0, MacroStore.water(context))
    }

    @Test
    fun `QuickAddStore parses loggedEntries and supports local delete and update`() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val payload = """
            {
              "mealSlots": [{"key": "breakfast", "label": "Breakfast"}, {"key": "lunch", "label": "Lunch"}],
              "loggedEntries": [
                {
                  "id": 101,
                  "name": "Oatmeal",
                  "mealKey": "breakfast",
                  "portionAmount": 80.0,
                  "portionUnit": "g",
                  "portionText": "80 g",
                  "servings": 1.0,
                  "kcal": 310,
                  "protein": 11,
                  "carbs": 54,
                  "fat": 6,
                  "foodId": 42
                },
                {
                  "id": 102,
                  "name": "Greek Yogurt",
                  "mealKey": "breakfast",
                  "portionAmount": 150.0,
                  "portionUnit": "g",
                  "portionText": "150 g",
                  "servings": 1.0,
                  "kcal": 130,
                  "protein": 15,
                  "carbs": 6,
                  "fat": 0,
                  "foodId": 43
                }
              ]
            }
        """.trimIndent()
        QuickAddStore.save(context, payload)

        val entries = QuickAddStore.loggedEntries(context)
        assertEquals(2, entries.size)
        assertEquals(101, entries[0].id)
        assertEquals("Oatmeal", entries[0].name)
        assertEquals("breakfast", entries[0].mealKey)
        assertEquals(310, entries[0].kcal)

        // Test local update
        QuickAddStore.updateLoggedEntryLocally(
            context = context,
            entryId = 101,
            newMealKey = "lunch",
            newAmount = 100.0,
            newUnit = "g",
            newPortionText = "100 g",
            newKcal = 380,
            newProtein = 14,
            newCarbs = 67,
            newFat = 7,
            newServings = 1.25,
        )
        val updatedEntries = QuickAddStore.loggedEntries(context)
        val updatedItem = updatedEntries.first { it.id == 101 }
        assertEquals("lunch", updatedItem.mealKey)
        assertEquals(100.0, updatedItem.portionAmount, 0.001)
        assertEquals(380, updatedItem.kcal)

        // Test local delete
        QuickAddStore.deleteLoggedEntryLocally(context, 102)
        val remaining = QuickAddStore.loggedEntries(context)
        assertEquals(1, remaining.size)
        assertEquals(101, remaining[0].id)

        // Test command creation
        val deleteCmd = JSONObject(QuickAddStore.createDeleteCommand(101))
        assertEquals("delete", deleteCmd.getString("action"))
        assertEquals(101, deleteCmd.getInt("entryId"))

        val updateCmd = JSONObject(QuickAddStore.createUpdateCommand(101, "lunch", 120.0, "g", 1.5))
        assertEquals("update", updateCmd.getString("action"))
        assertEquals(101, updateCmd.getInt("entryId"))
        assertEquals("lunch", updateCmd.getString("mealKey"))
        assertEquals(120.0, updateCmd.getDouble("portionAmount"), 0.001)
    }

    @Test
    fun `MacroStore adjustFood adjusts totals and clamps to zero`() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val cal = java.util.Calendar.getInstance()
        val todayStr = "%04d-%02d-%02d".format(
            cal.get(java.util.Calendar.YEAR),
            cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH),
        )
        MacroStore.save(context, calories = 500, protein = 40, carbs = 50, fats = 15, fasting = "0h", dayKey = todayStr)

        MacroStore.adjustFood(context, deltaCalories = 150, deltaProtein = 10, deltaCarbs = 20, deltaFats = 5)
        assertEquals(650, MacroStore.calories(context))
        assertEquals(50, MacroStore.protein(context))
        assertEquals(70, MacroStore.carbs(context))
        assertEquals(20, MacroStore.fats(context))

        // Subtract more than total — should clamp to 0
        MacroStore.adjustFood(context, deltaCalories = -1000, deltaProtein = -100, deltaCarbs = -100, deltaFats = -100)
        assertEquals(0, MacroStore.calories(context))
        assertEquals(0, MacroStore.protein(context))
        assertEquals(0, MacroStore.carbs(context))
        assertEquals(0, MacroStore.fats(context))
    }
}

