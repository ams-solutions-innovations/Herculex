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
}
