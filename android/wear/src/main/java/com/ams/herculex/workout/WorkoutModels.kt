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
    val durationSeconds: Int? = null,
    val targetDistanceMeters: Double? = null,
    val setTypeMetaJson: String? = null,
    val supersetGroup: Int? = null,
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
    val loggingMetric: String? = null,
    val plannedSets: List<PlannedSet> = emptyList(),
    val supersetGroup: Int? = null,
) {
    fun isBodyweightOnly(): Boolean {
        val metric = loggingMetric?.lowercase()?.trim()
        if (metric == "reps") return true
        if (metric == "weight_reps" || metric == "weight_time" || metric == "weight_distance") return false

        val variant = equipmentVariant?.lowercase()?.trim()
        if (variant == "bodyweight" || variant == "band") return true
        return false
    }

    fun isTimeBased(): Boolean {
        val metric = loggingMetric?.lowercase()?.trim()
        // 1. Explicit rep-based / non-timed metrics are NEVER time-based
        if (metric == "weight_reps" || metric == "reps" || metric == "weight_distance" || metric == "distance" || metric == "calories") {
            return false
        }
        // 2. Explicit time-based metrics
        if (metric == "time" || metric == "time_distance" || metric == "time_calories" || metric == "weight_time" || metric == "reps_time") {
            return true
        }

        // 3. Robust fallback heuristics when loggingMetric is unknown/null
        val lowerName = name.lowercase().trim()
        val lowerSlug = slug?.lowercase()?.trim() ?: ""

        // Distinct strength row patterns that MUST NEVER be timed
        val isStrengthRow = lowerName.contains("barbell row") ||
                lowerName.contains("dumbbell row") ||
                lowerName.contains("cable row") ||
                lowerName.contains("seated row") ||
                lowerName.contains("t-bar row") ||
                lowerName.contains("t bar row") ||
                lowerName.contains("pendlay row") ||
                lowerName.contains("seal row") ||
                lowerName.contains("inverted row") ||
                lowerName.contains("upright row") ||
                lowerName.contains("chest supported row") ||
                lowerName.contains("chest-supported row") ||
                lowerName.contains("single arm row") ||
                lowerName.contains("single-arm row") ||
                lowerName.contains("machine row") ||
                lowerName.contains("meadows row") ||
                lowerName.contains("kroc row") ||
                lowerName.endsWith(" row") ||
                lowerSlug.contains("barbell-row") ||
                lowerSlug.contains("dumbbell-row") ||
                lowerSlug.contains("cable-row") ||
                lowerSlug.contains("seated-row") ||
                lowerSlug.contains("t-bar-row") ||
                lowerSlug.contains("pendlay-row")

        if (isStrengthRow) return false

        // Strength exercise keywords that are never timed
        val isStandardLift = lowerName.contains("press") ||
                lowerName.contains("bench") ||
                lowerName.contains("squat") ||
                lowerName.contains("deadlift") ||
                lowerName.contains("curl") ||
                lowerName.contains("pulldown") ||
                lowerName.contains("pushdown") ||
                lowerName.contains("pull-up") ||
                lowerName.contains("pull up") ||
                lowerName.contains("chin-up") ||
                lowerName.contains("chin up") ||
                lowerName.contains("dip") ||
                lowerName.contains("push-up") ||
                lowerName.contains("push up") ||
                lowerName.contains("extension") ||
                lowerName.contains("raise") ||
                lowerName.contains("fly") ||
                lowerName.contains("shrug") ||
                lowerName.contains("crunch") ||
                lowerName.contains("sit-up") ||
                lowerName.contains("sit up") ||
                lowerName.contains("leg raise")

        if (isStandardLift) return false

        // Only true cardio / HIIT / isometric timed holds
        val isCardioOrTimed = lowerName.contains("plank") ||
                lowerName.contains("wall sit") ||
                lowerName.contains("dead hang") ||
                lowerName.contains("hollow body") ||
                lowerName.contains("l-sit") ||
                lowerName.contains("treadmill") ||
                lowerName.contains("stationary bike") ||
                lowerName.contains("assault bike") ||
                lowerName.contains("air bike") ||
                lowerName.contains("spin bike") ||
                lowerName.contains("rowing machine") ||
                lowerName.contains("rowing erg") ||
                lowerName.contains("row erg") ||
                lowerName.contains("indoor rower") ||
                lowerName.contains("concept2") ||
                lowerName.contains("skierg") ||
                lowerName.contains("ski erg") ||
                lowerName.contains("battle rope") ||
                lowerName.contains("jump rope") ||
                lowerName.contains("skipping rope") ||
                lowerName.contains("stairmaster") ||
                lowerName.contains("stair climber") ||
                lowerName.contains("elliptical") ||
                lowerName.contains("sprint") ||
                lowerName == "running" ||
                lowerName == "jogging" ||
                lowerName.startsWith("running ") ||
                lowerName.startsWith("jogging ") ||
                lowerName.contains("hiit") ||
                lowerSlug.contains("plank") ||
                lowerSlug.contains("wall-sit") ||
                lowerSlug.contains("dead-hang") ||
                lowerSlug.contains("treadmill") ||
                lowerSlug.contains("rowing-erg") ||
                lowerSlug.contains("rowing-machine") ||
                lowerSlug.contains("row-erg") ||
                lowerSlug.contains("skierg") ||
                lowerSlug.contains("ski-erg") ||
                lowerSlug.contains("air-bike") ||
                lowerSlug.contains("assault-bike")

        return isCardioOrTimed
    }

    /// True for loggingMetrics that carry a distance component (`distance`,
    /// `time_distance`, `weight_distance`) — mirrors the phone's
    /// `LoggingMetric.has(SetField.distance)` (lib/features/workouts/domain/
    /// logging_metric.dart). Unlike [isTimeBased]/[isBodyweightOnly] this has
    /// no name-based fallback: distance logging is new watch-side behavior,
    /// so an unset/legacy loggingMetric simply isn't distance-based.
    fun isDistanceBased(): Boolean {
        val metric = loggingMetric?.lowercase()?.trim()
        return metric == "distance" || metric == "time_distance" || metric == "weight_distance"
    }

    /// True only for `time_distance` (e.g. Rowing Erg) — the metric with no
    /// weight field where the slot that would otherwise show "Kg" on the set
    /// logger is really the distance in metres, alongside the Time slot. The
    /// other two distance metrics don't use this slot: plain `distance` has
    /// no second field to pair it with, so it hides this slot entirely (like
    /// `reps` does) and shows distance in the value slot instead; and
    /// `weight_distance` (e.g. Sled Push) keeps its real weight here — see
    /// [showsDistanceInValueSlot].
    fun showsDistanceInWeightSlot(): Boolean {
        val metric = loggingMetric?.lowercase()?.trim()
        return metric == "time_distance"
    }

    /// False only for `distance`/`time_distance` — every other metric
    /// (including unset/legacy ones) keeps the set logger's weight slot
    /// showing real weight when it's shown at all, exactly as before this
    /// distance support existed. Combined with [showsDistanceInWeightSlot],
    /// this is what tells the set logger whether to hide the weight slot
    /// entirely (`distance` — nothing belongs there) or repurpose it for
    /// distance (`time_distance`) instead of leaving every non-`weight_*`
    /// metric's Kg picker in place unexamined.
    fun hasRealWeightSlot(): Boolean {
        val metric = loggingMetric?.lowercase()?.trim()
        return metric != "distance" && metric != "time_distance"
    }

    /// True for `distance` (no time field to hold it) and `weight_distance`
    /// (no reps field) — the two metrics where the set logger's Reps slot
    /// should show distance instead. `time_distance` doesn't need this: its
    /// distance already goes in the weight slot via [showsDistanceInWeightSlot],
    /// leaving the value slot free for [isTimeBased]'s Time picker.
    fun showsDistanceInValueSlot(): Boolean {
        val metric = loggingMetric?.lowercase()?.trim()
        return metric == "distance" || metric == "weight_distance"
    }
}

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
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val rpe: Double? = null,
    val setType: String = "standard",
    val isWarmup: Boolean = false,
    val accessory: String? = null,
    val completed: Boolean = true,
    val setTypeMetaJson: String? = null,
    val bodyweightKg: Double? = null,
    val chainsKg: Double? = null,
    val completedAtEpochMs: Long? = null,
) {
    fun getMiniSets(): List<Int> {
        if (setTypeMetaJson.isNullOrBlank()) return emptyList()
        return try {
            val obj = org.json.JSONObject(setTypeMetaJson)
            val arr = obj.optJSONArray("miniSets") ?: return emptyList()
            (0 until arr.length()).map { arr.getInt(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun withMiniSets(miniSets: List<Int>): LoggedSet {
        val obj = if (!setTypeMetaJson.isNullOrBlank()) {
            try { org.json.JSONObject(setTypeMetaJson) } catch (_: Exception) { org.json.JSONObject() }
        } else {
            org.json.JSONObject()
        }
        val arr = org.json.JSONArray()
        miniSets.forEach { arr.put(it) }
        obj.put("miniSets", arr)
        return this.copy(setTypeMetaJson = obj.toString())
    }

    fun getExtraReps(): List<Int> {
        if (setTypeMetaJson.isNullOrBlank()) return emptyList()
        return try {
            val obj = org.json.JSONObject(setTypeMetaJson)
            val arr = obj.optJSONArray("extraReps")
                ?: obj.optJSONArray("forcedReps")
                ?: obj.optJSONArray("cheatReps")
                ?: return emptyList()
            (0 until arr.length()).map { arr.getInt(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun withExtraReps(extraReps: List<Int>): LoggedSet {
        val obj = if (!setTypeMetaJson.isNullOrBlank()) {
            try { org.json.JSONObject(setTypeMetaJson) } catch (_: Exception) { org.json.JSONObject() }
        } else {
            org.json.JSONObject()
        }
        val arr = org.json.JSONArray()
        extraReps.forEach { arr.put(it) }
        obj.put("extraReps", arr)
        return this.copy(setTypeMetaJson = obj.toString())
    }
}

data class ActiveExercise(
    val template: ExerciseTemplate,
    val sets: List<LoggedSet> = emptyList(),
    val wireId: String = "watch_exercise_${java.util.UUID.randomUUID()}",
    val supersetGroup: Int? = null,
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
    /// Stable identity for this session on the phone<->watch wire protocol
    /// (Phase 1 of wear-sync remediation) — used as `entityId` on every
    /// message about it, including its end, and compared against on apply so
    /// an update/end for a different session can't touch this one. Fixed at
    /// creation just like [origin]: a session the watch adopted from the
    /// phone keeps the phone's UUID rather than minting its own.
    val sessionId: String = java.util.UUID.randomUUID().toString(),
)
