package com.ams.herculex.workout

import kotlin.math.abs
import kotlin.math.max

object WatchPrEvaluator {

    /**
     * Estimates 1RM from weight and reps matching the phone's OneRepMax algorithm.
     */
    fun estimate1Rm(weightKg: Double, reps: Int): Double {
        if (reps < 1 || weightKg <= 0.0) return 0.0
        if (reps == 1) return weightKg
        return if (reps <= 12) {
            val epley = weightKg * (1.0 + reps / 30.0)
            val brzycki = weightKg * 36.0 / (37.0 - reps)
            (epley + brzycki) / 2.0
        } else {
            weightKg * (1.0 + reps / 30.0)
        }
    }

    /**
     * Formats weight without trailing decimal if integer.
     */
    fun formatWeight(v: Double): String =
        if (v % 1.0 == 0.0) "${v.toInt()}" else "%.1f".format(v)

    /**
     * Evaluates a completed set for an exercise to check if any PR was achieved.
     */
    fun evaluateCompletedSet(
        exercise: ActiveExercise,
        completedSet: LoggedSet,
    ): WatchPrEvent? {
        if (completedSet.isWarmup || completedSet.setType == "warmup") return null
        val weight = completedSet.weight
        val reps = completedSet.reps
        if (reps <= 0 || weight <= 0.0) return null

        val current1Rm = estimate1Rm(weight, reps)

        // Prior template performance
        val prevWeight = exercise.template.prevWeight
        val prevReps = exercise.template.prevReps
        val prevTemplate1Rm = if (prevWeight > 0.0 && prevReps > 0) estimate1Rm(prevWeight, prevReps) else if (prevWeight > 0.0) prevWeight else 0.0

        // Other completed non-warmup sets in this exercise during this session
        val otherSets = exercise.sets.filter {
            it.completed && !it.isWarmup && it.setType != "warmup" && it != completedSet && it.reps > 0 && it.weight > 0.0
        }

        var prevBest1Rm = prevTemplate1Rm
        var prevMaxWeight = prevWeight
        var prevMaxRepsAtWeight = if (prevWeight > 0.0 && abs(prevWeight - weight) < 0.6) prevReps else 0

        for (s in otherSets) {
            val est = estimate1Rm(s.weight, s.reps)
            if (est > prevBest1Rm) prevBest1Rm = est
            if (s.weight > prevMaxWeight) prevMaxWeight = s.weight
            if (abs(s.weight - weight) < 0.6 && s.reps > prevMaxRepsAtWeight) {
                prevMaxRepsAtWeight = s.reps
            }
        }

        val exerciseName = exercise.template.name

        // 1. Estimated 1RM PR
        if (prevBest1Rm > 0.0 && current1Rm > prevBest1Rm + 0.4) {
            val diff = current1Rm - prevBest1Rm
            return WatchPrEvent(
                exerciseName = exerciseName,
                prType = "1RM PR",
                headline = "🏆 NOVI 1RM PR!",
                valueText = "${formatWeight(weight)} kg × $reps",
                diffText = "+${formatWeight(diff)} kg",
                subDetail = "Ocena 1RM: ${formatWeight(current1Rm)} kg",
            )
        }

        // 2. Rep PR at this specific weight
        if (prevMaxRepsAtWeight > 0 && reps > prevMaxRepsAtWeight) {
            val diffReps = reps - prevMaxRepsAtWeight
            return WatchPrEvent(
                exerciseName = exerciseName,
                prType = "REP PR",
                headline = "🏆 REKORD PONOVITEV!",
                valueText = "$reps ponovitev @ ${formatWeight(weight)} kg",
                diffText = "+$diffReps reps",
                subDetail = "Prejšnji rekord: $prevMaxRepsAtWeight reps",
            )
        }

        // 3. Absolute Weight PR
        if (prevMaxWeight > 0.0 && weight > prevMaxWeight + 0.1 && reps >= 1) {
            val diffWeight = weight - prevMaxWeight
            return WatchPrEvent(
                exerciseName = exerciseName,
                prType = "WEIGHT PR",
                headline = "🏆 TEŽNOSTNI REKORD!",
                valueText = "${formatWeight(weight)} kg × $reps",
                diffText = "+${formatWeight(diffWeight)} kg",
                subDetail = "Prejšnja max teža: ${formatWeight(prevMaxWeight)} kg",
            )
        }

        return null
    }

    /**
     * Computes workout summary recap metrics from a session.
     */
    fun computeSummary(
        session: WorkoutSession,
        elapsedSeconds: Long,
        heartRate: Int = -1,
        sessionPrs: List<WatchPrEvent> = emptyList(),
    ): WorkoutSummaryData {
        var totalVolume = 0.0
        var totalCompletedSets = 0
        var totalCompletedExercises = 0

        for (ex in session.exercises) {
            var exCompleted = false
            for (set in ex.sets) {
                if (set.completed && !set.isWarmup && set.setType != "warmup") {
                    totalVolume += set.weight * set.reps
                    totalCompletedSets++
                    exCompleted = true
                }
            }
            if (exCompleted) {
                totalCompletedExercises++
            }
        }

        return WorkoutSummaryData(
            workoutName = session.template.name.ifBlank { "Workout" },
            durationSeconds = max(elapsedSeconds, 1L),
            totalVolumeKg = totalVolume,
            completedSets = totalCompletedSets,
            totalExercises = totalCompletedExercises,
            prCount = sessionPrs.size,
            prList = sessionPrs,
            avgHeartRate = heartRate,
        )
    }
}
