package com.ams.herculex.workout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SetNavigationTest {

    private fun dummyExercise(name: String, setCount: Int): ActiveExercise {
        return ActiveExercise(
            template = ExerciseTemplate(
                name = name,
                targetSets = setCount,
            ),
            sets = (0 until setCount).map { idx ->
                LoggedSet(
                    wireId = "${name}_set_$idx",
                    setIndex = idx,
                    weight = 50.0,
                    reps = 10,
                    completed = false,
                )
            },
        )
    }

    @Test
    fun testNavigationBetweenSetsAndExercises() {
        val exercises = listOf(
            dummyExercise("Bench Press", 3),
            dummyExercise("Incline Dumbbell Press", 2),
        )

        var exerciseIndex = 0
        var setIndex = 0

        fun canGoNext(): Boolean {
            val ex = exercises[exerciseIndex]
            val lastSetIdx = maxOf(ex.sets.size - 1, 0)
            val isLastSet = setIndex >= lastSetIdx
            val isLastEx = exerciseIndex >= exercises.size - 1
            return !isLastSet || !isLastEx
        }

        fun goNext() {
            val ex = exercises[exerciseIndex]
            val lastSetIdx = maxOf(ex.sets.size - 1, 0)
            if (setIndex < lastSetIdx) {
                setIndex += 1
            } else if (exerciseIndex < exercises.size - 1) {
                exerciseIndex += 1
                setIndex = 0
            }
        }

        fun goPrev(): Boolean {
            if (setIndex > 0) {
                setIndex -= 1
                return true
            } else if (exerciseIndex > 0) {
                exerciseIndex -= 1
                val prevEx = exercises[exerciseIndex]
                setIndex = maxOf(prevEx.sets.size - 1, 0)
                return true
            } else {
                return false // Pop backstack
            }
        }

        // Initially at Exercise 0, Set 0
        assertEquals(0, exerciseIndex)
        assertEquals(0, setIndex)
        assertTrue(canGoNext())

        // Moving through sets of Exercise 0
        goNext()
        assertEquals(0, exerciseIndex)
        assertEquals(1, setIndex)
        assertTrue(canGoNext())

        goNext()
        assertEquals(0, exerciseIndex)
        assertEquals(2, setIndex) // Last set of Exercise 0
        assertTrue(canGoNext())

        // Moving right from last set transitions to Exercise 1, Set 0
        goNext()
        assertEquals(1, exerciseIndex)
        assertEquals(0, setIndex)
        assertTrue(canGoNext())

        // Move to Exercise 1, Set 1 (Last set of Exercise 1)
        goNext()
        assertEquals(1, exerciseIndex)
        assertEquals(1, setIndex)
        assertFalse(canGoNext()) // Last set of last exercise cannot go next

        // Now move backwards:
        assertTrue(goPrev())
        assertEquals(1, exerciseIndex)
        assertEquals(0, setIndex)

        // Moving left from Exercise 1, Set 0 transitions to Exercise 0, Last Set (2)
        assertTrue(goPrev())
        assertEquals(0, exerciseIndex)
        assertEquals(2, setIndex)

        assertTrue(goPrev())
        assertEquals(0, exerciseIndex)
        assertEquals(1, setIndex)

        assertTrue(goPrev())
        assertEquals(0, exerciseIndex)
        assertEquals(0, setIndex)

        // Moving left from Exercise 0, Set 0 pops backstack
        assertFalse(goPrev())
    }

    @Test
    fun testAddAndRemoveSetNavigation() {
        val exercises = mutableListOf(
            dummyExercise("Bench Press", 3),
            dummyExercise("Incline Dumbbell Press", 2),
        )

        var exerciseIndex = 0
        var setIndex = 1
        var poppedBackStack = false

        fun onAddSet() {
            val ex = exercises[exerciseIndex]
            val newSetIdx = ex.sets.size
            val updatedSets = ex.sets + LoggedSet(
                wireId = "new_set_$newSetIdx",
                setIndex = newSetIdx,
                weight = 50.0,
                reps = 10,
                completed = false,
            )
            exercises[exerciseIndex] = ex.copy(sets = updatedSets)
            setIndex = newSetIdx
        }

        fun onRemoveSet() {
            val ex = exercises[exerciseIndex]
            if (ex.sets.isEmpty()) return
            val targetRemoveIdx = setIndex.coerceIn(0, ex.sets.lastIndex)
            val wasLastSet = (targetRemoveIdx == ex.sets.lastIndex)
            val isLastExercise = (exerciseIndex >= exercises.size - 1)

            val updatedSets = ex.sets.toMutableList().also { it.removeAt(targetRemoveIdx) }
            exercises[exerciseIndex] = ex.copy(sets = updatedSets)

            if (wasLastSet) {
                if (!isLastExercise) {
                    exerciseIndex += 1
                    setIndex = 0
                } else {
                    poppedBackStack = true
                }
            } else {
                setIndex = targetRemoveIdx.coerceIn(0, maxOf(ex.sets.size - 2, 0))
            }
        }

        // Test 1: Adding a set immediately points to the newly added set
        exerciseIndex = 0
        setIndex = 1
        onAddSet()
        assertEquals(0, exerciseIndex)
        assertEquals(3, setIndex) // was 3 sets (0, 1, 2), new one is at index 3 (4th set)
        assertEquals(4, exercises[0].sets.size)

        // Test 2: Removing a non-last set stays on that position
        setIndex = 1
        onRemoveSet()
        assertEquals(0, exerciseIndex)
        assertEquals(1, setIndex) // stayed at index 1
        assertEquals(3, exercises[0].sets.size)

        // Test 3: Removing the last set of an exercise routes to the next exercise's first set
        setIndex = 2 // last set of Exercise 0 (size 3)
        onRemoveSet()
        assertEquals(1, exerciseIndex) // moved to Exercise 1
        assertEquals(0, setIndex) // at Set 0
        assertEquals(2, exercises[0].sets.size)
        assertFalse(poppedBackStack)

        // Test 4: Removing the last set of the last exercise routes to the workout overview (popBackStack)
        setIndex = 1 // last set of Exercise 1 (size 2)
        onRemoveSet()
        assertTrue(poppedBackStack) // popped to list of all exercises
    }
}
