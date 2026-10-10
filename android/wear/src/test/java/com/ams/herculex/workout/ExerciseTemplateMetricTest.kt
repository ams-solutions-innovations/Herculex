package com.ams.herculex.workout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The watch must score an exercise exactly as the phone does, which means the
 * chosen equipment variant has to be able to override the catalog metric. The
 * phone's rule lives in `effectiveLoggingMetric`
 * (lib/features/workouts/domain/equipment_variants.dart); each case here is
 * one of its branches.
 */
class ExerciseTemplateMetricTest {

    private fun dip(variant: String? = null) = ExerciseTemplate(
        name = "Dip",
        targetSets = 3,
        slug = "chest-dips",
        loggingMetric = "reps", // how the catalog stores every bodyweight dip
        equipmentVariant = variant,
    )

    @Test
    fun `a dip with no variant is bodyweight`() {
        assertTrue(dip().isBodyweightOnly())
    }

    @Test
    fun `switching a dip to weighted shows the weight field`() {
        // The reported bug: the phone sent equipmentVariant=weighted, but the
        // catalog metric "reps" short-circuited and the watch stayed on
        // bodyweight.
        val weighted = dip("weighted")

        assertFalse(weighted.isBodyweightOnly())
        assertFalse(weighted.isTimeBased())
    }

    @Test
    fun `switching back from weighted to bodyweight hides the weight field again`() {
        assertTrue(dip("bodyweight").isBodyweightOnly())
        assertTrue(dip("band").isBodyweightOnly())
    }

    @Test
    fun `variant matching is case and whitespace tolerant`() {
        assertFalse(dip(" Weighted ").isBodyweightOnly())
    }

    @Test
    fun `a weighted exercise forced to bodyweight logs reps only`() {
        val pullUpOnWeightedCatalogRow = ExerciseTemplate(
            name = "Pull-Up",
            targetSets = 3,
            loggingMetric = "weight_reps",
            equipmentVariant = "bodyweight",
        )

        assertTrue(pullUpOnWeightedCatalogRow.isBodyweightOnly())
    }

    @Test
    fun `a barbell lift without a bodyweight variant keeps its weight field`() {
        val bench = ExerciseTemplate(
            name = "Barbell Bench Press",
            targetSets = 4,
            loggingMetric = "weight_reps",
            equipmentVariant = "barbell",
        )

        assertFalse(bench.isBodyweightOnly())
    }

    @Test
    fun `weighted overrides a timed catalog metric the way the phone does`() {
        // Mirrors effectiveLoggingMetric: any weighted variant is weight x reps.
        val weightedPlank = ExerciseTemplate(
            name = "Plank",
            targetSets = 3,
            loggingMetric = "time",
            equipmentVariant = "weighted",
        )

        assertFalse(weightedPlank.isTimeBased())
        assertFalse(weightedPlank.isBodyweightOnly())
    }

    @Test
    fun `distance metrics are unaffected when no variant overrides them`() {
        val sledPush = ExerciseTemplate(
            name = "Sled Push",
            targetSets = 3,
            loggingMetric = "weight_distance",
        )

        assertTrue(sledPush.isDistanceBased())
        assertTrue(sledPush.showsDistanceInValueSlot())
        assertEquals(true, sledPush.hasRealWeightSlot())
    }
}
