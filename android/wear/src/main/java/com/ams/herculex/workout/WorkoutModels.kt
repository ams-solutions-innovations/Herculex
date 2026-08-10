package com.ams.herculex.workout

import com.ams.herculex.sync.WearSyncContract

// ── Templates (read-only workout definitions) ────────────────────────────────

data class PlannedSet(
    val wireId: String? = null,
    val setIndex: Int,
    val setType: String = "standard",
    val isWarmup: Boolean = false,
    val targetReps: Int? = null,
    val targetRepsMin: Int? = null,
    val targetRepsMax: Int? = null,
    val targetWeightKg: Double? = null,
    val setTypeMetaJson: String? = null,
)

/// [catalogExerciseId] and [slug] are the phone catalog's identity for this
/// exercise. Both must survive every hop — catalog parse, picker, session
/// persistence, sync payload — or the phone falls back to matching on
/// [name] and mints a junk custom exercise when the two sides disagree.
data class ExerciseTemplate(
    val name: String,
    val targetSets: Int,
    val prevWeight: Double = 0.0,
    val prevReps: Int = 0,
    val catalogExerciseId: Int? = null,
    val slug: String? = null,
    /// Modality ids this exercise can plausibly be performed with, as sent by
    /// the phone. Empty means no equipment prompt.
    val equipmentOptions: List<String> = emptyList(),
    /// Modality chosen for this log entry. Stored as
    /// `workout_exercises.equipment_variant` on the phone — the name is never
    /// rewritten to encode it.
    val equipmentVariant: String? = null,
    val plannedSets: List<PlannedSet> = emptyList(),
)

data class WorkoutTemplate(
    val id: String,
    val name: String,
    val exercises: List<ExerciseTemplate>,
)

// ── Live session state ────────────────────────────────────────────────────────

data class LoggedSet(
    val wireId: String? = null,
    val setIndex: Int? = null,
    val weight: Double,
    val reps: Int,
    val rpe: Double? = null,
    val setType: String = "standard",
    val isWarmup: Boolean = false,
    val accessory: String? = null,
    val completed: Boolean = true,
    val setTypeMetaJson: String? = null,
    val bodyweightKg: Double? = null,
    val chainsKg: Double? = null,
    val completedAtEpochMs: Long? = null,
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
    /// Which device actually started this workout — [WearSyncContract.ORIGIN_WATCH]
    /// or [WearSyncContract.ORIGIN_PHONE]. Fixed at creation and never changed by
    /// a later update, so a session the watch merely adopted from the phone keeps
    /// reporting `phone` on every push back. The phone gates its "Workout Started
    /// on Watch" alert on this; stamping everything `watch` made that alert fire
    /// for phone-started workouts that already had an ongoing surface.
    val origin: String = WearSyncContract.ORIGIN_WATCH,
)
