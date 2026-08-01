package com.ams.herculex.workout

import android.app.Application
import android.content.Intent
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ams.herculex.sync.WearDataLayerSyncManager
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
                        WorkoutStore.sessionToJson(session),
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
    ) {
        val newSession = WorkoutSession(
            template  = template,
            exercises = template.exercises.map { ActiveExercise(template = it) },
        )
        _session.value = newSession
        _elapsedSeconds.value = 0L
        sessionStartEpochMs = startEpochMs
        _elapsedSeconds.value = ((System.currentTimeMillis() - startEpochMs) / 1000).coerceAtLeast(0)
        startTimer()
        startServiceIfNeeded(sessionStartEpochMs)

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
    ) {
        val effectiveStartEpochMs = startedAtEpochMs ?: sessionStartEpochMs
        val current = _session.value
        if (current != null) {
            sessionStartEpochMs = effectiveStartEpochMs
            _elapsedSeconds.value = ((System.currentTimeMillis() - effectiveStartEpochMs) / 1000).coerceAtLeast(0)
            _session.value = current.copy(
                exercises = exercises,
                currentExerciseIndex = currentExIndex,
                currentSetIndex = currentSetIndex,
            )
        } else {
            val template = WorkoutTemplate(
                id = "remote_session",
                name = templateName,
                exercises = exercises.map { it.template },
            )
            val newSession = WorkoutSession(
                template = template,
                exercises = exercises,
                currentExerciseIndex = currentExIndex,
                currentSetIndex = currentSetIndex,
            )
            _session.value = newSession
            sessionStartEpochMs = effectiveStartEpochMs
            _elapsedSeconds.value = ((System.currentTimeMillis() - effectiveStartEpochMs) / 1000).coerceAtLeast(0)
            startTimer()
            startServiceIfNeeded(sessionStartEpochMs)
        }
    }

    fun addExerciseToSession(exerciseTemplate: ExerciseTemplate) {
        val current = _session.value ?: return
        val exercises = current.exercises + ActiveExercise(template = exerciseTemplate)
        val updated = current.copy(exercises = exercises)
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
        val current = _session.value ?: return
        if (exerciseIndex !in current.exercises.indices) return
        val exercises = current.exercises.toMutableList()
        exercises[exerciseIndex] = ActiveExercise(template = newTemplate)
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
        exercises[exerciseIndex] = ex.copy(template = updatedTemplate)
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
        rpe: Int? = null,
        setType: String = "Normal",
        accessory: String? = null,
    ) {
        val current = _session.value ?: return
        val exercises = current.exercises.toMutableList()
        val exercise  = exercises[exerciseIndex]
        val newSets   = exercise.sets + LoggedSet(
            weight = weight,
            reps = reps,
            rpe = rpe,
            setType = setType,
            accessory = accessory,
        )
        exercises[exerciseIndex] = exercise.copy(sets = newSets)

        val allDone       = newSets.size >= exercise.template.targetSets
        val newExIndex    = if (allDone) (exerciseIndex + 1).coerceAtMost(exercises.size - 1) else exerciseIndex
        val newSetIndex   = if (allDone) 0 else newSets.size

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

    fun finishWorkout() = endSession(isFinish = true, notifyPhone = true)
    fun discardWorkout() = endSession(isFinish = false, notifyPhone = true)
    fun endSessionFromPhone() = endSession(isFinish = true, notifyPhone = false)

    // ── Internals & DataClient Sync ──────────────────────────────────────────

    private fun broadcastSessionToPhone(path: String, session: WorkoutSession) {
        try {
            val json = WorkoutStore.sessionToJson(session)
            viewModelScope.launch {
                // Durable fallback: persists to WearSyncPaths.STATE_ACTIVE_WORKOUT,
                // which the phone syncs via DataClient even if the node was
                // disconnected right now — no separate raw DataClient put needed
                // on this literal path (that used to double-deliver alongside
                // the MessageClient send below, since the phone listened for
                // both onDataChanged AND onMessageReceived on the same path).
                syncManager.pushActiveWorkoutSession(json)
                // Fast path: near-instant MessageClient delivery so the phone
                // reflects set/weight/exercise changes without waiting on
                // DataClient's system-level batching.
                syncManager.sendMessageToAllNodes(path, json)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun broadcastSessionEndToPhone() {
        try {
            viewModelScope.launch {
                syncManager.pushActiveWorkoutSession(null)
                syncManager.sendMessageToAllNodes(WearSyncPaths.MESSAGE_WATCH_SESSION_END, "")
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startServiceIfNeeded(startEpochMs: Long = System.currentTimeMillis()) {
        val intent = Intent(getApplication(), WorkoutOngoingService::class.java).apply {
            putExtra(WorkoutOngoingService.EXTRA_START_EPOCH_MS, startEpochMs)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getApplication<Application>().startForegroundService(intent)
        } else {
            getApplication<Application>().startService(intent)
        }
    }

    private fun endSession(isFinish: Boolean, notifyPhone: Boolean) {
        timerJob?.cancel()
        _session.value        = null
        _elapsedSeconds.value = 0L
        if (notifyPhone) {
            broadcastSessionEndToPhone()
        }
        val intent = Intent(getApplication(), WorkoutOngoingService::class.java).apply { action = "STOP" }
        getApplication<Application>().startService(intent)
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
