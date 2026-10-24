package com.ams.herculex.complication

import androidx.test.core.app.ApplicationProvider
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.GoalProgressComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import android.content.Context
import java.time.Instant
import com.ams.herculex.sync.CnsStore
import com.ams.herculex.sync.MacroStore

@RunWith(RobolectricTestRunner::class)
class WearComplicationsTest {

    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `buildProgressComplicationData creates valid RangedValueComplicationData`() {
        val data = WearComplicationHelper.buildProgressComplicationData(
            context = context,
            type = ComplicationType.RANGED_VALUE,
            current = 120f,
            min = 0f,
            max = 150f,
            text = "120g",
            title = "P",
            description = "Protein 120g",
        )

        assertNotNull(data)
        assertTrue(data is RangedValueComplicationData)
        val ranged = data as RangedValueComplicationData
        assertEquals(120f, ranged.value)
        assertEquals(0f, ranged.min)
        assertEquals(150f, ranged.max)
    }

    @Test
    fun `buildProgressComplicationData clamps value within min and max`() {
        // Exceeding max
        val dataOver = WearComplicationHelper.buildProgressComplicationData(
            context = context,
            type = ComplicationType.RANGED_VALUE,
            current = 200f,
            min = 0f,
            max = 150f,
            text = "200g",
            title = "P",
            description = "Protein",
        ) as RangedValueComplicationData

        assertEquals(150f, dataOver.value)

        // Below min
        val dataUnder = WearComplicationHelper.buildProgressComplicationData(
            context = context,
            type = ComplicationType.RANGED_VALUE,
            current = -10f,
            min = 0f,
            max = 150f,
            text = "0g",
            title = "P",
            description = "Protein",
        ) as RangedValueComplicationData

        assertEquals(0f, dataUnder.value)
    }

    @Test
    fun `buildProgressComplicationData creates valid GoalProgressComplicationData`() {
        val data = WearComplicationHelper.buildProgressComplicationData(
            context = context,
            type = ComplicationType.GOAL_PROGRESS,
            current = 175f,
            min = 0f,
            max = 150f,
            text = "175g",
            title = "P",
            description = "Protein",
        )

        assertNotNull(data)
        assertTrue(data is GoalProgressComplicationData)
        val goal = data as GoalProgressComplicationData
        assertEquals(175f, goal.value)
        assertEquals(150f, goal.targetValue)
    }

    @Test
    fun `buildProgressComplicationData creates valid ShortTextComplicationData`() {
        val data = WearComplicationHelper.buildProgressComplicationData(
            context = context,
            type = ComplicationType.SHORT_TEXT,
            current = 120f,
            min = 0f,
            max = 150f,
            text = "120g",
            title = "P",
            description = "Protein",
        )

        assertNotNull(data)
        assertTrue(data is ShortTextComplicationData)
    }

    @Test
    fun `buildProgressComplicationData returns null for unsupported type`() {
        val data = WearComplicationHelper.buildProgressComplicationData(
            context = context,
            type = ComplicationType.LONG_TEXT,
            current = 120f,
            min = 0f,
            max = 150f,
            text = "120g",
            title = "P",
            description = "Protein",
        )

        assertNull(data)
    }

    @Test
    fun `CnsStore persists and reads readiness and status`() {
        CnsStore.save(context, 85, "FRESH")
        assertEquals(85, CnsStore.readinessPct(context))
        assertEquals("FRESH", CnsStore.status(context))

        CnsStore.save(context, 120, "OVER") // Should clamp to 100
        assertEquals(100, CnsStore.readinessPct(context))
    }

    @Test
    fun `formatCalories formats whole numbers with thousands separator and never with k suffix`() {
        val locale = java.util.Locale.US
        assertEquals("0", WearComplicationHelper.formatCalories(0f, locale))
        assertEquals("850", WearComplicationHelper.formatCalories(850f, locale))
        assertEquals("999", WearComplicationHelper.formatCalories(999f, locale))
        assertEquals("1,000", WearComplicationHelper.formatCalories(1000f, locale))
        assertEquals("1,234", WearComplicationHelper.formatCalories(1234f, locale))
        assertEquals("1,435", WearComplicationHelper.formatCalories(1435f, locale))
        assertEquals("1,850", WearComplicationHelper.formatCalories(1850f, locale))
        assertEquals("2,073", WearComplicationHelper.formatCalories(2073f, locale))
        assertEquals("2,400", WearComplicationHelper.formatCalories(2400f, locale))

        // European / Slovenian locale with dot thousands separator
        val deLocale = java.util.Locale.GERMANY
        assertEquals("1.435", WearComplicationHelper.formatCalories(1435f, deLocale))
    }

    @Test
    fun `CaloriesComplicationService preview shows formatted calories and omits title on progress complications`() {
        val service = CaloriesComplicationService()
        val expectedNumber = WearComplicationHelper.formatCalories(1850f)

        val ranged = service.getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals(1850f, ranged.value)
        assertEquals(2400f, ranged.max)
        assertEquals(expectedNumber, ranged.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(ranged.title) // Title omitted to avoid curved bezel truncation

        val goal = service.getPreviewData(ComplicationType.GOAL_PROGRESS) as GoalProgressComplicationData
        assertEquals(1850f, goal.value)
        assertEquals(2400f, goal.targetValue)
        assertEquals(expectedNumber, goal.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(goal.title) // Title omitted to avoid curved bezel truncation

        val shortText = service.getPreviewData(ComplicationType.SHORT_TEXT) as ShortTextComplicationData
        assertEquals(expectedNumber, shortText.text.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals("kcal", shortText.title?.getTextAt(context.resources, Instant.EPOCH).toString())
    }

    @Test
    fun `ProteinComplicationService preview shows 120g and omits title on progress complications`() {
        val service = ProteinComplicationService()
        val ranged = service.getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals("120g", ranged.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(ranged.title)

        val goal = service.getPreviewData(ComplicationType.GOAL_PROGRESS) as GoalProgressComplicationData
        assertEquals("120g", goal.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(goal.title)

        val text = service.getPreviewData(ComplicationType.SHORT_TEXT) as ShortTextComplicationData
        assertEquals("120g", text.text.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals("P", text.title?.getTextAt(context.resources, Instant.EPOCH).toString())

        assertNull(service.getPreviewData(ComplicationType.LONG_TEXT))
    }

    @Test
    fun `Carbs and Fats complication services preview show formatted grams and omit title on progress complications`() {
        val carbs = CarbsComplicationService().getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals("180g", carbs.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(carbs.title)

        val fats = FatsComplicationService().getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals("45g", fats.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(fats.title)
    }

    @Test
    fun `CnsComplicationService preview shows 85 percent and omits title on progress complications`() {
        val service = CnsComplicationService()
        val ranged = service.getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals(85f, ranged.value)
        assertEquals(100f, ranged.max)
        assertEquals("85%", ranged.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(ranged.title)

        val goal = service.getPreviewData(ComplicationType.GOAL_PROGRESS) as GoalProgressComplicationData
        assertEquals("85%", goal.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(goal.title)

        val text = service.getPreviewData(ComplicationType.SHORT_TEXT) as ShortTextComplicationData
        assertEquals("85%", text.text.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals("CNS", text.title?.getTextAt(context.resources, Instant.EPOCH).toString())
    }

    @Test
    fun `FastingComplicationService preview shows 14h and omits title on progress complications`() {
        val service = FastingComplicationService()
        val ranged = service.getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertTrue(ranged.value > 0f)
        assertTrue(ranged.max > 0f)
        assertEquals("14h", ranged.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(ranged.title)

        val text = service.getPreviewData(ComplicationType.SHORT_TEXT) as ShortTextComplicationData
        assertEquals("14h", text.text.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals("Fast", text.title?.getTextAt(context.resources, Instant.EPOCH).toString())
    }

    @Test
    fun `WaterComplicationService preview shows 1dot5L and omits title on progress complications`() {
        val service = WaterComplicationService()
        val ranged = service.getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals(1500f, ranged.value)
        assertEquals(2000f, ranged.max)
        assertEquals("1.5L", ranged.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(ranged.title)

        val text = service.getPreviewData(ComplicationType.SHORT_TEXT) as ShortTextComplicationData
        assertEquals("1.5L", text.text.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals("Water", text.title?.getTextAt(context.resources, Instant.EPOCH).toString())
    }

    @Test
    fun `WeeklySets and WeeklyVolume preview show numbers and omit title on progress complications`() {
        val sets = WeeklySetsComplicationService().getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals("35", sets.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(sets.title)

        val volume = WeeklyVolumeComplicationService().getPreviewData(ComplicationType.RANGED_VALUE) as RangedValueComplicationData
        assertEquals("12t", volume.text?.getTextAt(context.resources, Instant.EPOCH).toString())
        assertNull(volume.title)
    }
}
