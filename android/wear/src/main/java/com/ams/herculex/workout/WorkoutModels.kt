package com.ams.herculex.workout

// ── Templates (read-only workout definitions) ────────────────────────────────

data class ExerciseTemplate(
    val name: String,
    val targetSets: Int,
    val prevWeight: Double = 0.0,
    val prevReps: Int = 0,
)

data class WorkoutTemplate(
    val id: String,
    val name: String,
    val exercises: List<ExerciseTemplate>,
)

// ── Live session state ────────────────────────────────────────────────────────

data class LoggedSet(
    val weight: Double,
    val reps: Int,
    val rpe: Int? = null,
    val setType: String = "Normal",
    val accessory: String? = null,
    val completed: Boolean = true,
)

data class ActiveExercise(
    val template: ExerciseTemplate,
    val sets: List<LoggedSet> = emptyList(),
) {
    val completedSets: Int get() = sets.count { it.completed }
}

data class WorkoutSession(
    val template: WorkoutTemplate,
    val exercises: List<ActiveExercise>,
    val startTimeMs: Long = System.currentTimeMillis(),
    val currentExerciseIndex: Int = 0,
    val currentSetIndex: Int = 0,
)
