package com.ams.herculex.workout

/**
 * Model representing an in-app PR celebration event on Wear OS.
 */
data class WatchPrEvent(
    val id: String = java.util.UUID.randomUUID().toString(),
    val exerciseName: String,
    val prType: String, // "1RM PR", "REP PR", "WEIGHT PR", "VOLUME PR"
    val headline: String, // e.g. "NEW 1RM PR" or "NOVI PR!"
    val valueText: String, // e.g. "100.0 kg × 8"
    val diffText: String? = null, // e.g. "+5.0 kg" or "+2 reps"
    val subDetail: String? = null, // e.g. "Est. 1RM: 120 kg"
    val durationMs: Long = 3000L,
)

/**
 * Summary recap of a completed workout on Wear OS.
 */
data class WorkoutSummaryData(
    val workoutName: String,
    val durationSeconds: Long,
    val totalVolumeKg: Double,
    val completedSets: Int,
    val totalExercises: Int,
    val prCount: Int = 0,
    val prList: List<WatchPrEvent> = emptyList(),
    val avgHeartRate: Int = -1,
)
