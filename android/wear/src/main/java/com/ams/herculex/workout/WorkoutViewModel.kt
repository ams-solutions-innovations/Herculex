package com.ams.herculex.workout

import android.app.Application
import android.content.Intent
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ams.herculex.sync.WearDataLayerSyncManager
import com.ams.herculex.sync.WearRevisionAllocator
import com.ams.herculex.sync.WearSyncContract
import com.ams.herculex.sync.WearSyncPaths
import com.ams.herculex.sync.SyncService
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class WorkoutViewModel(application: Application) : AndroidViewModel(application) {

    private val syncManager = WearDataLayerSyncManager(application)

    private val _workouts = MutableStateFlow<List<WorkoutTemplate>>(emptyList())
    val workouts: StateFlow<List<WorkoutTemplate>> = _workouts.asStateFlow()

    private val _session = MutableStateFlow<WorkoutSession?>(null)
    val session: StateFlow<WorkoutSession?> = _session.asStateFlow()

    private val _elapsedSeconds = MutableStateFlow(0L)
    val elapsedSeconds: StateFlow<Long> = _elapsedSeconds.asStateFlow()

    private val _heartRate = MutableStateFlow(-1)
    val heartRate: StateFlow<Int> = _heartRate.asStateFlow()

    private val _prCelebration = MutableStateFlow<WatchPrEvent?>(null)
    val prCelebration: StateFlow<WatchPrEvent?> = _prCelebration.asStateFlow()

    private val _sessionPrs = MutableStateFlow<List<WatchPrEvent>>(emptyList())
    val sessionPrs: StateFlow<List<WatchPrEvent>> = _sessionPrs.asStateFlow()

    private val _finishedWorkoutSummary = MutableStateFlow<WorkoutSummaryData?>(null)
    val finishedWorkoutSummary: StateFlow<WorkoutSummaryData?> = _finishedWorkoutSummary.asStateFlow()

    private var timerJob: Job? = null
    private var sessionStartEpochMs: Long = System.currentTimeMillis()

    init {
        SyncService.activeViewModel = this
        loadWorkouts()
        restoreSessionIfNeeded()

        // Persist the active session on every change so a fresh
        // WorkoutViewModel (e.g. after the Activity/process gets recreated
        // while a workout is running — Wear OS is aggressive about
        // reclaiming backgrounded activities) can restore it instead of
        // silently losing it.
        viewModelScope.launch {
            _session.collect { session ->
                if (session != null) {
                    WorkoutStore.saveActiveSession(
                        getApplication(),
                        WorkoutStore.sessionToJson(getApplication(), session),
                        sessionStartEpochMs,
                    )
                } else {
                    WorkoutStore.clearActiveSession(getApplication())
                }
            }
        }
    }

    private fun restoreSessionIfNeeded() {
        if (_session.value != null) return
        val persistedJson = WorkoutStore.getActiveSessionJson(getApplication()) ?: return
        val persistedEpoch = WorkoutStore.getActiveSessionStartEpoch(getApplication()) ?: System.currentTimeMillis()
        WorkoutStore.parseAndUpdateSession(persistedJson, this)
        sessionStartEpochMs = persistedEpoch
        _elapsedSeconds.value = ((System.currentTimeMillis() - persistedEpoch) / 1000).coerceAtLeast(0)
        startServiceIfNeeded(persistedEpoch)
    }

    fun loadWorkouts() {
        _workouts.value = WorkoutStore.getWorkouts(getApplication())
    }

    fun startWorkout(
        template: WorkoutTemplate,
        broadcastToPhone: Boolean = true,
        startEpochMs: Long = System.currentTimeMillis(),
        origin: String = WearSyncContract.ORIGIN_WATCH,
        sessionId: String = java.util.UUID.randomUUID().toString(),
    ) {
        val newSession = WorkoutSession(
            template  = template,
            exercises = template.exercises.map { exerciseTemplate ->
                ActiveExercise(
                    template = exerciseTemplate,
                    sets = plannedSetsForTemplate(exerciseTemplate),
                )
            },
            startTimeMs = startEpochMs,
            origin = origin,
            sessionId = sessionId,
        )
        _session.value = newSession
        _sessionPrs.value = emptyList()
        _finishedWorkoutSummary.value = null
        _elapsedSeconds.value = 0L
        sessionStartEpochMs = startEpochMs
        _elapsedSeconds.value = ((System.currentTimeMillis() - startEpochMs) / 1000).coerceAtLeast(0)
        startTimer()
        startServiceIfNeeded(sessionStartEpochMs)

        template.exercises.forEach { ExerciseUsageTracker.recordUsed(getApplication(), it) }

        if (broadcastToPhone) {
            broadcastSessionToPhone("/herculex_watch_workout_started", newSession)
        }
    }

    fun startEmptyWorkout() {
        val template = WorkoutTemplate(
            id = "empty_${System.currentTimeMillis()}",
            name = "Empty Workout",
            exercises = emptyList()
        )
        startWorkout(template, broadcastToPhone = true)
    }

    fun updateSessionFromRemote(
        exercises: List<ActiveExercise>,
        currentExIndex: Int,
        currentSetIndex: Int,
        templateName: String = "Active Workout",
        startedAtEpochMs: Long? = null,
        origin: String = WearSyncContract.ORIGIN_PHONE,
        sessionId: String = java.util.UUID.randomUUID().toString(),
    ) {
        val effectiveStartEpochMs = startedAtEpochMs ?: sessionStartEpochMs
        val current = _session.value
        if (current != null) {
            // `origin` is deliberately NOT taken from the incoming envelope
            // here: it records who *started* the session, and an update from
            // the other device never changes that. Letting a phone-sent update
            // rewrite a watch-started session to phone-origin would suppress
            // the phone's legitimate "started on watch" alert on reconnect.
            // Same reasoning applies to `sessionId` — apply-time gating
            // against a mismatched id happens one layer up (SyncService), so
            // by the time we're here the id is already confirmed to match.
            sessionStartEpochMs = effectiveStartEpochMs
            _elapsedSeconds.value = ((System.currentTimeMillis() - effectiveStartEpochMs) / 1000).coerceAtLeast(0)
            _session.value = current.copy(
                template = current.template.copy(
                    name = templateName,
                    exercises = exercises.map { it.template }
                ),
                exercises = exercises,
                startTimeMs = effectiveStartEpochMs,
                currentExerciseIndex = currentExIndex,
                currentSetIndex = currentSetIndex,
            )
            startServiceIfNeeded(sessionStartEpochMs, isUpdate = true)
        } else {
            val template = WorkoutTemplate(
                id = "remote_session",
                name = templateName,
                exercises = exercises.map { it.template },
            )
            val newSession = WorkoutSession(
                template = template,
                exercises = exercises,
                startTimeMs = effectiveStartEpochMs,
                currentExerciseIndex = currentExIndex,
                currentSetIndex = currentSetIndex,
                origin = origin,
                sessionId = sessionId,
            )
            _session.value = newSession
            sessionStartEpochMs = effectiveStartEpochMs
            _elapsedSeconds.value = ((System.currentTimeMillis() - effectiveStartEpochMs) / 1000).coerceAtLeast(0)
            startTimer()
            startServiceIfNeeded(sessionStartEpochMs)
        }
    }

    fun addExerciseToSession(exerciseTemplate: ExerciseTemplate) {
        ExerciseUsageTracker.recordUsed(getApplication(), exerciseTemplate)
        val current = _session.value ?: return
        val exercises = current.exercises + ActiveExercise(template = exerciseTemplate)
        val updated = current.copy(exercises = exercises)
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun selectExerciseInSession(exerciseIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val updated = current.copy(
            currentExerciseIndex = exerciseIndex,
            currentSetIndex = current.exercises[exerciseIndex].sets
                .indexOfFirst { !it.completed }
                .takeIf { it >= 0 }
                ?: current.exercises[exerciseIndex].sets.size
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun removeExerciseFromSession(exerciseIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        exercises.removeAt(exerciseIndex)
        val newExIndex = current.currentExerciseIndex.coerceIn(0, (exercises.size - 1).coerceAtLeast(0))
        val updated = current.copy(
            exercises = exercises,
            currentExerciseIndex = newExIndex
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun substituteExerciseInSession(exerciseIndex: Int, newTemplate: ExerciseTemplate) {
        ExerciseUsageTracker.recordUsed(getApplication(), newTemplate)
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        // Same slot, different exercise — keep the slot's wireId so the
        // phone's Phase 3 wireId-based reconciliation recognizes this as a
        // substitution rather than a delete+insert.
        exercises[exerciseIndex] = ActiveExercise(
            template = newTemplate,
            wireId = exercises[exerciseIndex].wireId,
        )
        val updated = current.copy(exercises = exercises)
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun addSetToExercise(exerciseIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val ex = exercises[exerciseIndex]
        val updatedTemplate = ex.template.copy(targetSets = ex.template.targetSets + 1)
        val nextIndex = ex.sets.size
        val updatedSets = ex.sets + LoggedSet(
            wireId = "watch_planned_${System.currentTimeMillis()}",
            setIndex = nextIndex,
            weight = ex.sets.lastOrNull()?.weight ?: ex.template.prevWeight,
            reps = ex.sets.lastOrNull()?.reps ?: ex.template.prevReps.coerceAtLeast(1),
            setType = "standard",
            completed = false,
        )
        exercises[exerciseIndex] = ex.copy(template = updatedTemplate, sets = updatedSets)
        val updated = current.copy(exercises = exercises)
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun removeSetFromExercise(exerciseIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val ex = exercises[exerciseIndex]
        if (ex.template.targetSets > 1) {
            val updatedTargetSets = ex.template.targetSets - 1
            val updatedSets = if (ex.sets.size > updatedTargetSets) ex.sets.dropLast(1) else ex.sets
            val updatedTemplate = ex.template.copy(targetSets = updatedTargetSets)
            exercises[exerciseIndex] = ex.copy(template = updatedTemplate, sets = updatedSets)
            val updated = current.copy(exercises = exercises)
            _session.value = updated
            broadcastSessionToPhone("/herculex_watch_session_update", updated)
        }
    }

    fun logSet(
        exerciseIndex: Int,
        weight: Double,
        reps: Int,
        rpe: Double? = null,
        setType: String = "standard",
        accessory: String? = null,
        durationSeconds: Int? = null,
        distanceMeters: Double? = null,
    ) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val exercise  = exercises[exerciseIndex]
        val openIndex = exercise.sets.indexOfFirst { !it.completed }
        val normalizedType = com.ams.herculex.sync.WearSyncContract.normalizeSetType(setType)
        val isWarmup = com.ams.herculex.sync.WearSyncContract.normalizeIsWarmup(setType, false)
        val isMyo = normalizedType == "myo_reps"

        val completedSet = if (openIndex >= 0) {
            exercise.sets[openIndex].copy(
                weight = weight,
                reps = reps,
                durationSeconds = durationSeconds,
                distanceMeters = distanceMeters,
                rpe = rpe,
                setType = normalizedType,
                isWarmup = isWarmup,
                accessory = accessory,
                completed = true,
                completedAtEpochMs = System.currentTimeMillis(),
            )
        } else {
            LoggedSet(
                wireId = "watch_set_${System.currentTimeMillis()}",
                setIndex = exercise.sets.size,
                weight = weight,
                reps = reps,
                durationSeconds = durationSeconds,
                distanceMeters = distanceMeters,
                rpe = rpe,
                setType = normalizedType,
                isWarmup = isWarmup,
                accessory = accessory,
                completed = true,
                completedAtEpochMs = System.currentTimeMillis(),
            )
        }
        val targetSetIdx = if (openIndex >= 0) openIndex else exercise.sets.size
        val newSets = if (openIndex >= 0) {
            exercise.sets.toMutableList().also { it[openIndex] = completedSet }
        } else {
            exercise.sets + completedSet
        }
        exercises[exerciseIndex] = exercise.copy(sets = newSets)
        ExerciseUsageTracker.recordUsed(getApplication(), exercise.template)

        // Evaluate for personal record (1RM, Reps, Weight PR)
        val prEvent = WatchPrEvaluator.evaluateCompletedSet(exercise, completedSet)
        if (prEvent != null) {
            _sessionPrs.value = _sessionPrs.value + prEvent
            showPrCelebration(prEvent)
        }

        val nextOpenIndex = newSets.indexOfFirst { !it.completed }
        val allDone       = nextOpenIndex < 0 && newSets.count { it.completed } >= exercise.template.targetSets
        val isExtraMode   = isMyo || normalizedType == "forced" || normalizedType == "cheat"

        val sGroup = exercise.supersetGroup ?: exercise.template.supersetGroup
        val groupIndices = if (sGroup != null) {
            exercises.indices.filter {
                (exercises[it].supersetGroup ?: exercises[it].template.supersetGroup) == sGroup
            }
        } else emptyList()

        val newExIndex: Int
        val newSetIndex: Int

        if (isExtraMode) {
            // Keep user focused on this set so extra reps (forced, cheat, mini) can be logged immediately.
            newExIndex = exerciseIndex
            newSetIndex = targetSetIdx
        } else if (groupIndices.size > 1) {
            val currentPos = groupIndices.indexOf(exerciseIndex)
            var targetExIdx = exerciseIndex
            var targetSet = 0
            var found = false
            for (step in 1..groupIndices.size) {
                val candidateIdx = groupIndices[(currentPos + step) % groupIndices.size]
                val candidateEx = exercises[candidateIdx]
                val open = candidateEx.sets.indexOfFirst { !it.completed }
                if (open >= 0 || candidateEx.sets.size < candidateEx.template.targetSets) {
                    targetExIdx = candidateIdx
                    targetSet = if (open >= 0) open else candidateEx.sets.size
                    found = true
                    break
                }
            }
            if (found) {
                newExIndex = targetExIdx
                newSetIndex = targetSet
            } else if (allDone) {
                newExIndex = (exerciseIndex + 1).coerceAtMost(exercises.size - 1)
                newSetIndex = 0
            } else {
                newExIndex = exerciseIndex
                newSetIndex = nextOpenIndex.takeIf { it >= 0 } ?: newSets.size
            }
        } else {
            newExIndex = if (allDone) (exerciseIndex + 1).coerceAtMost(exercises.size - 1) else exerciseIndex
            newSetIndex = if (allDone) 0 else nextOpenIndex.takeIf { it >= 0 } ?: newSets.size
        }

        val updated = current.copy(
            exercises            = exercises,
            currentExerciseIndex = newExIndex,
            currentSetIndex      = newSetIndex,
        )
        _session.value = updated
        // broadcastSessionToPhone already ships the full session over the
        // fast MessageClient path, so a separate weight-only event isn't needed.
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun addMiniSet(exerciseIndex: Int, setIndex: Int, miniReps: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val exercise = exercises[exerciseIndex]
        val targetIdx = if (setIndex in exercise.sets.indices) setIndex else exercise.sets.lastIndex
        if (targetIdx !in exercise.sets.indices) return

        val set = exercise.sets[targetIdx]
        val currentMini = set.getMiniSets()
        val updatedSet = set.withMiniSets(currentMini + miniReps)

        val newSets = exercise.sets.toMutableList().also { it[targetIdx] = updatedSet }
        exercises[exerciseIndex] = exercise.copy(sets = newSets)

        val updated = current.copy(
            exercises = exercises,
            currentExerciseIndex = exerciseIndex,
            currentSetIndex = targetIdx,
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun removeLastMiniSet(exerciseIndex: Int, setIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val exercise = exercises[exerciseIndex]
        val targetIdx = if (setIndex in exercise.sets.indices) setIndex else exercise.sets.lastIndex
        if (targetIdx !in exercise.sets.indices) return

        val set = exercise.sets[targetIdx]
        val currentMini = set.getMiniSets()
        if (currentMini.isEmpty()) return
        val updatedSet = set.withMiniSets(currentMini.dropLast(1))

        val newSets = exercise.sets.toMutableList().also { it[targetIdx] = updatedSet }
        exercises[exerciseIndex] = exercise.copy(sets = newSets)

        val updated = current.copy(
            exercises = exercises,
            currentExerciseIndex = exerciseIndex,
            currentSetIndex = targetIdx,
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun addExtraReps(exerciseIndex: Int, setIndex: Int, extraReps: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val exercise = exercises[exerciseIndex]
        val targetIdx = if (setIndex in exercise.sets.indices) setIndex else exercise.sets.lastIndex
        if (targetIdx !in exercise.sets.indices) return

        val set = exercise.sets[targetIdx]
        val currentExtra = set.getExtraReps()
        val updatedSet = set.withExtraReps(currentExtra + extraReps)

        val newSets = exercise.sets.toMutableList().also { it[targetIdx] = updatedSet }
        exercises[exerciseIndex] = exercise.copy(sets = newSets)

        val updated = current.copy(
            exercises = exercises,
            currentExerciseIndex = exerciseIndex,
            currentSetIndex = targetIdx,
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun removeLastExtraReps(exerciseIndex: Int, setIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        val exercise = exercises[exerciseIndex]
        val targetIdx = if (setIndex in exercise.sets.indices) setIndex else exercise.sets.lastIndex
        if (targetIdx !in exercise.sets.indices) return

        val set = exercise.sets[targetIdx]
        val currentExtra = set.getExtraReps()
        if (currentExtra.isEmpty()) return
        val updatedSet = set.withExtraReps(currentExtra.dropLast(1))

        val newSets = exercise.sets.toMutableList().also { it[targetIdx] = updatedSet }
        exercises[exerciseIndex] = exercise.copy(sets = newSets)

        val updated = current.copy(
            exercises = exercises,
            currentExerciseIndex = exerciseIndex,
            currentSetIndex = targetIdx,
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun finishMyoSet(exerciseIndex: Int, setIndex: Int) = finishExtraSet(exerciseIndex, setIndex)

    fun finishExtraSet(exerciseIndex: Int, setIndex: Int) {
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises
        val exercise = exercises[exerciseIndex]
        val nextOpenIndex = exercise.sets.indexOfFirst { !it.completed }
        val allDone = nextOpenIndex < 0 && exercise.completedSets >= exercise.template.targetSets

        val sGroup = exercise.supersetGroup ?: exercise.template.supersetGroup
        val groupIndices = if (sGroup != null) {
            exercises.indices.filter {
                (exercises[it].supersetGroup ?: exercises[it].template.supersetGroup) == sGroup
            }
        } else emptyList()

        val newExIndex: Int
        val newSetIndex: Int

        if (groupIndices.size > 1) {
            val currentPos = groupIndices.indexOf(exerciseIndex)
            var targetExIdx = exerciseIndex
            var targetSet = 0
            var found = false
            for (step in 1..groupIndices.size) {
                val candidateIdx = groupIndices[(currentPos + step) % groupIndices.size]
                val candidateEx = exercises[candidateIdx]
                val open = candidateEx.sets.indexOfFirst { !it.completed }
                if (open >= 0 || candidateEx.sets.size < candidateEx.template.targetSets) {
                    targetExIdx = candidateIdx
                    targetSet = if (open >= 0) open else candidateEx.sets.size
                    found = true
                    break
                }
            }
            if (found) {
                newExIndex = targetExIdx
                newSetIndex = targetSet
            } else if (allDone) {
                newExIndex = (exerciseIndex + 1).coerceAtMost(exercises.size - 1)
                newSetIndex = 0
            } else {
                newExIndex = exerciseIndex
                newSetIndex = nextOpenIndex.takeIf { it >= 0 } ?: exercise.sets.size
            }
        } else {
            newExIndex = if (allDone) (exerciseIndex + 1).coerceAtMost(exercises.size - 1) else exerciseIndex
            newSetIndex = if (allDone) 0 else nextOpenIndex.takeIf { it >= 0 } ?: exercise.sets.size
        }

        val updated = current.copy(
            currentExerciseIndex = newExIndex,
            currentSetIndex = newSetIndex,
        )
        _session.value = updated
        broadcastSessionToPhone("/herculex_watch_session_update", updated)
    }

    fun finishWorkout() = endSession(isFinish = true, notifyPhone = true)
    fun discardWorkout() = endSession(isFinish = false, notifyPhone = true)
    fun endSessionFromPhone() = endSession(isFinish = true, notifyPhone = false)

    // ── Internals & DataClient Sync ──────────────────────────────────────────

    private fun broadcastSessionToPhone(path: String, session: WorkoutSession) {
        try {
            val json = WorkoutStore.sessionToJson(getApplication(), session)
            viewModelScope.launch {
                // Durable fallback: persists to WearSyncPaths.STATE_ACTIVE_WORKOUT,
                // which the phone syncs via DataClient even if the node was
                // disconnected right now — no separate raw DataClient put needed
                // on this literal path (that used to double-deliver alongside
                // the MessageClient send below, since the phone listened for
                // both onDataChanged AND onMessageReceived on the same path).
                //
                // Isolated in its own runCatching (ENG-16): an exception here
                // (e.g. DataClient unreachable) used to propagate out of this
                // unguarded sequential `await`, which both skipped the fast
                // MessageClient send below entirely and crashed the coroutine
                // (viewModelScope has no exception handler of its own).
                runCatching { syncManager.pushActiveWorkoutSession(json) }
                    .onFailure { android.util.Log.e("WorkoutViewModel", "Durable session push failed", it) }
                // Fast path: near-instant MessageClient delivery so the phone
                // reflects set/weight/exercise changes without waiting on
                // DataClient's system-level batching. Must run regardless of
                // whether the durable put above succeeded.
                syncManager.sendMessageToAllNodes(path, json)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun plannedSetsForTemplate(template: ExerciseTemplate): List<LoggedSet> {
        if (template.plannedSets.isNotEmpty()) {
            return template.plannedSets.mapIndexed { index, planned ->
                LoggedSet(
                    wireId = planned.wireId ?: "planned_$index",
                    setIndex = planned.setIndex,
                    weight = planned.targetWeightKg ?: template.prevWeight,
                    reps = planned.targetReps ?: planned.targetRepsMin ?: template.prevReps.coerceAtLeast(1),
                    distanceMeters = planned.targetDistanceMeters,
                    setType = planned.setType,
                    isWarmup = planned.isWarmup,
                    completed = false,
                    setTypeMetaJson = planned.setTypeMetaJson,
                )
            }
        }
        return (0 until template.targetSets).map { index ->
            LoggedSet(
                wireId = "planned_$index",
                setIndex = index,
                weight = template.prevWeight,
                reps = template.prevReps.coerceAtLeast(1),
                completed = false,
            )
        }
    }

    private fun broadcastSessionEndToPhone(entityId: String) {
        try {
            viewModelScope.launch {
                // See the matching comment in broadcastSessionToPhone (ENG-16)
                // — a failed durable put must not skip the fast message send.
                runCatching { syncManager.pushActiveWorkoutSession(null, endedEntityId = entityId) }
                    .onFailure { android.util.Log.e("WorkoutViewModel", "Durable session-end push failed", it) }
                syncManager.sendMessageToAllNodes(
                    WearSyncPaths.MESSAGE_WATCH_SESSION_END,
                    endEnvelope(entityId),
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun broadcastSessionDiscardToPhone(entityId: String) {
        try {
            viewModelScope.launch {
                // See the matching comment in broadcastSessionToPhone (ENG-16)
                // — a failed durable put must not skip the fast message send.
                runCatching { syncManager.pushActiveWorkoutSession(null, endedEntityId = entityId) }
                    .onFailure { android.util.Log.e("WorkoutViewModel", "Durable session-discard push failed", it) }
                syncManager.sendMessageToAllNodes(
                    WearSyncPaths.MESSAGE_WATCH_SESSION_DISCARD,
                    endEnvelope(entityId),
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /// Real, identity-carrying envelope for a session end/discard message —
    /// these used to send an empty payload (`""`/`"discard"`), which is why
    /// the phone couldn't tell which session was ending. Payload is empty on
    /// purpose; only the entityId matters here.
    private fun endEnvelope(entityId: String): String {
        return WearSyncContract.encodeEnvelope(
            entity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
            entityId = entityId,
            revision = WearRevisionAllocator(getApplication(), "workout").next(),
            origin = WearSyncContract.ORIGIN_WATCH,
            payload = org.json.JSONObject(),
        )
    }

    private fun startServiceIfNeeded(
        startEpochMs: Long = System.currentTimeMillis(),
        isUpdate: Boolean = false,
    ) {
        val currentSession = _session.value
        val title = currentSession?.template?.name ?: "Active Workout"
        val exName = currentSession?.exercises?.getOrNull(currentSession.currentExerciseIndex)?.template?.name
        val intent = Intent(getApplication(), WorkoutOngoingService::class.java).apply {
            action = if (isUpdate) WorkoutOngoingService.ACTION_UPDATE else WorkoutOngoingService.ACTION_START
            putExtra(WorkoutOngoingService.EXTRA_START_EPOCH_MS, startEpochMs)
            putExtra(WorkoutOngoingService.EXTRA_WORKOUT_TITLE, title)
            if (!exName.isNullOrBlank()) {
                putExtra(WorkoutOngoingService.EXTRA_EXERCISE_NAME, exName)
            }
        }
        if (isUpdate) {
            getApplication<Application>().startService(intent)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getApplication<Application>().startForegroundService(intent)
        } else {
            getApplication<Application>().startService(intent)
        }
    }

    private fun endSession(isFinish: Boolean, notifyPhone: Boolean) {
        val currentSession = _session.value
        val endingSessionId = currentSession?.sessionId
        if (isFinish && currentSession != null) {
            _finishedWorkoutSummary.value = WatchPrEvaluator.computeSummary(
                session = currentSession,
                elapsedSeconds = _elapsedSeconds.value,
                heartRate = _heartRate.value,
                sessionPrs = _sessionPrs.value,
            )
        }
        timerJob?.cancel()
        _session.value        = null
        _elapsedSeconds.value = 0L
        if (notifyPhone && endingSessionId != null) {
            if (isFinish) {
                broadcastSessionEndToPhone(endingSessionId)
            } else {
                broadcastSessionDiscardToPhone(endingSessionId)
            }
        }
        val intent = Intent(getApplication(), WorkoutOngoingService::class.java).apply {
            action = WorkoutOngoingService.ACTION_STOP
        }
        getApplication<Application>().startService(intent)
    }

    fun showPrCelebration(event: WatchPrEvent) {
        _prCelebration.value = event
    }

    fun dismissPrCelebration() {
        _prCelebration.value = null
    }

    fun clearFinishedSummary() {
        _finishedWorkoutSummary.value = null
    }

    private fun startTimer() {
        timerJob?.cancel()
        timerJob = viewModelScope.launch {
            while (true) {
                delay(1_000)
                _elapsedSeconds.value += 1
            }
        }
    }

    override fun onCleared() {
        if (SyncService.activeViewModel == this) SyncService.activeViewModel = null
        timerJob?.cancel()
        super.onCleared()
    }
}
