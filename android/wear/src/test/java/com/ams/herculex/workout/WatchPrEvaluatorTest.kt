package com.ams.herculex.workout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchPrEvaluatorTest {

    @Test
    fun `estimate1Rm calculates standard 1RM accurately`() {
        // 1 rep of 100 kg is exactly 100 kg
        assertEquals(100.0, WatchPrEvaluator.estimate1Rm(100.0, 1), 0.01)

        // 8 reps of 100 kg is approx 125 kg
        val e1rm = WatchPrEvaluator.estimate1Rm(100.0, 8)
        assertTrue("Expected 1RM around 125 kg but got $e1rm", e1rm in 123.0..127.0)

        // Invalid reps or weight returns 0.0
        assertEquals(0.0, WatchPrEvaluator.estimate1Rm(0.0, 10), 0.01)
        assertEquals(0.0, WatchPrEvaluator.estimate1Rm(100.0, 0), 0.01)
    }

    @Test
    fun `evaluateCompletedSet detects 1RM PR`() {
        val template = ExerciseTemplate(
            name = "Barbell Bench Press",
            targetSets = 3,
            prevWeight = 80.0,
            prevReps = 8, // e1RM ~ 100 kg
        )
        val exercise = ActiveExercise(template = template)

        // User lifts 95 kg x 8 (e1RM ~ 119 kg > 100 kg)
        val set = LoggedSet(
            weight = 95.0,
            reps = 8,
            completed = true,
        )

        val prEvent = WatchPrEvaluator.evaluateCompletedSet(exercise, set)
        assertNotNull("Expected PR event but got null", prEvent)
        assertEquals("Barbell Bench Press", prEvent?.exerciseName)
        assertEquals("1RM PR", prEvent?.prType)
        assertTrue(prEvent?.headline?.contains("1RM PR") == true)
        assertTrue(prEvent?.diffText?.startsWith("+") == true)
    }

    @Test
    fun `evaluateCompletedSet detects Rep PR at same weight`() {
        val template = ExerciseTemplate(
            name = "Overhead Press",
            targetSets = 3,
            prevWeight = 50.0,
            prevReps = 8,
        )
        val exercise = ActiveExercise(template = template)

        // User does 11 reps at 50 kg
        val set = LoggedSet(
            weight = 50.0,
            reps = 11,
            completed = true,
        )

        val prEvent = WatchPrEvaluator.evaluateCompletedSet(exercise, set)
        assertNotNull(prEvent)
        assertTrue("Expected REP PR or 1RM PR", prEvent?.prType == "REP PR" || prEvent?.prType == "1RM PR")
    }

    @Test
    fun `evaluateCompletedSet ignores warmup sets`() {
        val template = ExerciseTemplate(
            name = "Deadlift",
            targetSets = 3,
            prevWeight = 100.0,
            prevReps = 5,
        )
        val exercise = ActiveExercise(template = template)

        val warmupSet = LoggedSet(
            weight = 150.0,
            reps = 10,
            isWarmup = true,
            setType = "warmup",
            completed = true,
        )

        val prEvent = WatchPrEvaluator.evaluateCompletedSet(exercise, warmupSet)
        assertNull("Warmup sets must never trigger a PR", prEvent)
    }

    @Test
    fun `computeSummary accurately sums volume, sets, and duration`() {
        val template = WorkoutTemplate(
            id = "test_workout",
            name = "Push Day",
            exercises = emptyList(),
        )
        val exercise1 = ActiveExercise(
            template = ExerciseTemplate("Bench Press", 2),
            sets = listOf(
                LoggedSet(weight = 100.0, reps = 10, completed = true),
                LoggedSet(weight = 100.0, reps = 8, completed = true),
            ),
        )
        val exercise2 = ActiveExercise(
            template = ExerciseTemplate("Incline Press", 1),
            sets = listOf(
                LoggedSet(weight = 60.0, reps = 10, completed = true),
                LoggedSet(weight = 40.0, reps = 10, isWarmup = true, completed = true), // Warmup excluded from volume
            ),
        )
        val session = WorkoutSession(
            template = template,
            exercises = listOf(exercise1, exercise2),
        )

        val prEvent = WatchPrEvent(
            exerciseName = "Bench Press",
            prType = "1RM PR",
            headline = "🏆 NOVI 1RM PR!",
            valueText = "100 kg × 10",
        )

        val summary = WatchPrEvaluator.computeSummary(
            session = session,
            elapsedSeconds = 2450L,
            heartRate = 145,
            sessionPrs = listOf(prEvent),
        )

        assertEquals("Push Day", summary.workoutName)
        assertEquals(2450L, summary.durationSeconds)
        // Volume = (100*10) + (100*8) + (60*10) = 1000 + 800 + 600 = 2400 kg
        assertEquals(2400.0, summary.totalVolumeKg, 0.01)
        assertEquals(3, summary.completedSets)
        assertEquals(2, summary.totalExercises)
        assertEquals(1, summary.prCount)
        assertEquals(145, summary.avgHeartRate)
    }
}
