package com.ams.herculex.workout

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AssistanceInputTest {
    @Test
    fun `legacy machine catalog still exposes an assistance weight field`() {
        val template = ExerciseTemplate(
            name = "Assisted Pull-Up Machine", targetSets = 3,
            slug = "assisted-pull-up-machine-wide-grip",
            equipmentVariant = "bodyweight", loggingMetric = "reps",
        )
        assertTrue(template.isAssistanceLoad())
        assertTrue(template.hasRealWeightSlot())
        assertFalse(template.isBodyweightOnly())
    }

    @Test
    fun `strict and weighted pullups retain their own load semantics`() {
        val strict = ExerciseTemplate(name = "Pull-Up", targetSets = 3,
            slug = "pull-up-wide-grip", equipmentVariant = "bodyweight", loggingMetric = "reps")
        assertFalse(strict.isAssistanceLoad())
        assertTrue(strict.isBodyweightOnly())
        assertFalse(strict.copy(equipmentVariant = "weighted", loggingMetric = "weight_reps").isBodyweightOnly())
    }
}
