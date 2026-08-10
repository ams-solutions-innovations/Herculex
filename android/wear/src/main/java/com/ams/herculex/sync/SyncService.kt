package com.ams.herculex.sync

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.ams.herculex.MainActivity
import com.ams.herculex.complication.CaloriesComplicationService
import com.ams.herculex.complication.CarbsComplicationService
import com.ams.herculex.complication.FastingComplicationService
import com.ams.herculex.complication.FatsComplicationService
import com.ams.herculex.complication.ProteinComplicationService
import com.ams.herculex.complication.WeeklySetsComplicationService
import com.ams.herculex.complication.WeeklyVolumeComplicationService
import com.ams.herculex.tile.MacrosTileService
import com.ams.herculex.workout.ExerciseCatalog
import com.ams.herculex.workout.WorkoutOngoingService
import com.ams.herculex.workout.WorkoutStore
import com.ams.herculex.workout.WorkoutViewModel
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class SyncService : WearableListenerService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val appliedRevisions by lazy { AppliedRevisionStore(applicationContext) }

    companion object {
        var activeViewModel: WorkoutViewModel? = null

        fun requestSyncFromPhone(context: Context) {
            com.google.android.gms.wearable.Wearable.getNodeClient(context).connectedNodes.addOnSuccessListener { nodes ->
                for (node in nodes) {
                    com.google.android.gms.wearable.Wearable.getMessageClient(context)
                        .sendMessage(node.id, "/request_sync", ByteArray(0))
                        .addOnSuccessListener { Log.d("SyncService", "Sent /request_sync to node ${node.displayName}") }
                }
            }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        super.onDataChanged(dataEvents)

        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue

            val path    = event.dataItem.uri.path ?: continue
            val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
            Log.d("SyncService", "onDataChanged $path, vm=${activeViewModel != null}")

            when {
                // ── Nutrition macros ─────────────────────────────────────────
                path == "/herculex_sync_data" -> {
                    val calories = dataMap.getInt("calories", 0)
                    val protein  = dataMap.getInt("protein",  0)
                    val carbs    = dataMap.getInt("carbs",    0)
                    val fats     = dataMap.getInt("fats",     0)
                    val fasting  = dataMap.getString("fasting", "0h 0m") ?: "0h 0m"
                    val weeklyTonnage = dataMap.getDouble("weekly_tonnage", 0.0)
                    val weeklySets = dataMap.getInt("weekly_sets", 0)
                    val weeklyVolumeJson = dataMap.getString("weekly_volume_json", "[]") ?: "[]"

                    MacroStore.save(this, calories, protein, carbs, fats, fasting)
                    MacroStore.saveWeeklyVolume(this, weeklyTonnage, weeklySets, weeklyVolumeJson)

                    if (dataMap.containsKey("calorie_goal")) {
                        MacroStore.saveGoals(
                            this,
                            dataMap.getInt("calorie_goal", 2000),
                            dataMap.getInt("protein_goal", 150),
                            dataMap.getInt("carbs_goal",   200),
                            dataMap.getInt("fat_goal",     65),
                            dataMap.getInt("water_goal",   2000),
                        )
                    }

                    requestComplicationUpdates()
                    requestTileUpdate()
                    Log.d("SyncService", "Nutrition synced: ${calories}kcal P${protein}")
                }

                // ── Workout definitions from phone ───────────────────────────
                path.startsWith("/herculex_workout_data") -> {
                    val workoutsJson = dataMap.getString("workouts_json")
                    if (!workoutsJson.isNullOrBlank()) {
                        WorkoutStore.saveJson(this, workoutsJson)
                        activeViewModel?.loadWorkouts()
                        Log.d("SyncService", "Workouts synced from phone")
                    }
                }

                // ── Exercise catalog from phone ─────────────────────────────
                path.startsWith("/herculex_catalog_data") -> {
                    val catalogJson = dataMap.getString("catalog_json")
                    if (!catalogJson.isNullOrBlank()) {
                        ExerciseCatalog.saveJson(this, catalogJson)
                        Log.d("SyncService", "Exercise catalog synced from phone")
                    }
                }

                // ── Quick-add foods + meal slots from phone ──────────────────
                path.startsWith("/herculex_quickadd_data") -> {
                    val quickAddJson = dataMap.getString("quickadd_json")
                    if (!quickAddJson.isNullOrBlank()) {
                        QuickAddStore.save(this, quickAddJson)
                        Log.d("SyncService", "Quick-add foods synced from phone")
                    }
                }

                // ── Active workout session state from phone (durable path) ──
                // DataClient-backed fallback, guaranteed to eventually sync
                // even if the fast MessageClient send missed a disconnected
                // node. It must NEVER launch the UI: this fires on every
                // phone-side session change, and when the watch app isn't
                // running there's no ViewModel to inspect — so launching here
                // yanks the app open over and over during a phone workout.
                // Instead it persists the state, so the session is simply
                // there when the user next opens the watch app. Only the
                // explicit start message below opens the UI.
                path == WearSyncPaths.STATE_ACTIVE_WORKOUT -> {
                    val sessionJson = dataMap.getString("session_json").orEmpty()
                    val hasActiveSession = dataMap.getBoolean("has_active_session", false)
                    if (hasActiveSession && sessionJson.isNotBlank()) {
                        val hadActiveSession =
                            WorkoutStore.getActiveSessionJson(this) != null
                        val accepted = handleSessionUpdate(
                            sessionJson,
                            path = path,
                            delivery = "data",
                        )
                        if (accepted && !hadActiveSession) {
                            startOngoingServiceIfNeeded(sessionJson, isNewStart = true)
                            openActiveWorkoutScreenOnWatch()
                        } else if (accepted) {
                            updateOngoingService(sessionJson)
                        }
                    } else {
                        handleSessionEnd()
                    }
                }

                path == WearSyncPaths.STATE_MACRO_TARGETS -> {
                    getSharedPreferences("wear_persistent_state", Context.MODE_PRIVATE)
                        .edit()
                        .putString("macro_targets_json", dataMap.getString("macro_targets_json").orEmpty())
                        .apply()
                }

                path == WearSyncPaths.STATE_FASTING -> {
                    val fastingJson = dataMap.getString("fasting_json").orEmpty()
                    if (fastingJson.isNotBlank()) {
                        handleFastingSnapshot(fastingJson, path, "data")
                    }
                }

                path == WearSyncPaths.STATE_USER_TOKEN -> {
                    getSharedPreferences("wear_persistent_state", Context.MODE_PRIVATE)
                        .edit()
                        .putString("user_token", dataMap.getString("user_token").orEmpty())
                        .apply()
                }
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        Log.d("SyncService", "onMessageReceived ${messageEvent.path} (${messageEvent.data.size}B), vm=${activeViewModel != null}")
        when (messageEvent.path) {
            WearSyncPaths.MESSAGE_START_REST_TIMER -> {
                Log.d("SyncService", "Received rest timer event: ${String(messageEvent.data)}")
            }
            WearSyncPaths.MESSAGE_UPDATE_WEIGHT -> {
                Log.d("SyncService", "Received weight update event: ${String(messageEvent.data)}")
            }
            WearSyncPaths.MESSAGE_FINISH_WORKOUT -> {
                activeViewModel?.endSessionFromPhone()
            }
            // Fast path: same payload/semantics as the DataClient paths above,
            // delivered via MessageClient for near-instant application.
            WearSyncPaths.MESSAGE_ACTIVE_SESSION_START -> {
                handleSessionStart(String(messageEvent.data), messageEvent.path, "message")
            }
            WearSyncPaths.MESSAGE_ACTIVE_SESSION_UPDATE -> {
                if (handleSessionUpdate(String(messageEvent.data), messageEvent.path, "message")) {
                    updateOngoingService(String(messageEvent.data))
                }
            }
            WearSyncPaths.MESSAGE_ACTIVE_SESSION_END -> {
                handleSessionEnd()
            }
            WearSyncPaths.MESSAGE_FASTING_SNAPSHOT -> {
                handleFastingSnapshot(String(messageEvent.data), messageEvent.path, "message")
            }
            WearSyncPaths.MESSAGE_FASTING_ACK -> {
                val payload = String(messageEvent.data)
                val commandId = runCatching {
                    org.json.JSONObject(payload).optString("commandId")
                }.getOrNull().orEmpty()
                FastingStore.clearPendingCommand(this, commandId)
            }
            WearSyncPaths.MESSAGE_QUICKADD_ACK -> {
                Log.d("SyncService", "Phone applied quick-add command")
            }
        }
    }

    private fun handleSessionStart(sessionJson: String?, path: String, delivery: String) {
        Log.d("SyncService", "Active workout start received from phone")
        val accepted = if (!sessionJson.isNullOrBlank()) {
            handleSessionUpdate(sessionJson, path, delivery)
        } else {
            false
        }
        if (accepted) {
            startOngoingServiceIfNeeded(sessionJson, isNewStart = true)
            openActiveWorkoutScreenOnWatch()
        }
    }

    private fun openActiveWorkoutScreenOnWatch() {
        try {
            val openIntent = Intent(applicationContext, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("open_active_workout", true)
            }
            applicationContext.startActivity(openIntent)
        } catch (e: Exception) {
            Log.e("SyncService", "Failed to launch workout screen on watch", e)
        }
    }

    private fun startOngoingServiceIfNeeded(
        sessionJson: String?,
        isNewStart: Boolean = false,
        action: String = WorkoutOngoingService.ACTION_START,
    ) {
        var startEpochMs = System.currentTimeMillis()
        var workoutTitle = "Active Workout"
        var exerciseName: String? = null

        if (!sessionJson.isNullOrBlank()) {
            startEpochMs = WorkoutStore.startedAtEpochMsFromSessionJson(sessionJson) ?: System.currentTimeMillis()
            try {
                val obj = org.json.JSONObject(sessionJson)
                val templateObj = obj.optJSONObject("template")
                workoutTitle = templateObj?.optString("name", "Active Workout") ?: "Active Workout"
                val currentExIdx = obj.optInt("currentExerciseIndex", 0)
                val exArr = obj.optJSONArray("exercises")
                if (exArr != null && currentExIdx in 0 until exArr.length()) {
                    val exObj = exArr.optJSONObject(currentExIdx)
                    val exTemplate = exObj?.optJSONObject("template")
                    exerciseName = exTemplate?.optString("name")
                }
            } catch (e: Exception) {
                // Keep defaults on parse failure
            }
        }

        val intent = Intent(applicationContext, WorkoutOngoingService::class.java).apply {
            this.action = action
            putExtra(WorkoutOngoingService.EXTRA_START_EPOCH_MS, startEpochMs)
            putExtra(WorkoutOngoingService.EXTRA_WORKOUT_TITLE, workoutTitle)
            if (!exerciseName.isNullOrBlank()) {
                putExtra(WorkoutOngoingService.EXTRA_EXERCISE_NAME, exerciseName)
            }
            if (isNewStart) {
                putExtra(WorkoutOngoingService.EXTRA_IS_NEW_START, true)
            }
        }
        try {
            if (action == WorkoutOngoingService.ACTION_UPDATE) {
                applicationContext.startService(intent)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(intent)
            } else {
                applicationContext.startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.e("SyncService", "Failed to start ongoing service", e)
        }
    }



    private fun updateOngoingService(sessionJson: String?) {
        startOngoingServiceIfNeeded(sessionJson, action = WorkoutOngoingService.ACTION_UPDATE)
    }

    private fun handleSessionUpdate(
        sessionJson: String?,
        path: String = WearSyncPaths.STATE_ACTIVE_WORKOUT,
        delivery: String = "data",
    ): Boolean {
        if (!sessionJson.isNullOrBlank()) {
            val envelope = WearSyncContract.decodeEnvelope(
                sessionJson,
                fallbackEntity = WearSyncContract.ENTITY_ACTIVE_WORKOUT,
                fallbackEntityId = "phone_active_workout",
                fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
            )
            if (!appliedRevisions.shouldAccept(envelope)) {
                logWearSync(envelope, path, delivery, "ignored")
                return false
            }
            logWearSync(envelope, path, delivery, "accepted")
            // Persist unconditionally: when the watch app isn't running there
            // is no activeViewModel to update, and without this the session
            // would be lost entirely rather than restored on next launch.
            persistSession(sessionJson)
            WorkoutStore.parseAndUpdateSession(sessionJson, activeViewModel)
            return true
        }
        return false
    }

    private fun handleFastingSnapshot(fastingJson: String, path: String, delivery: String) {
        val envelope = WearSyncContract.decodeEnvelope(
            fastingJson,
            fallbackEntity = WearSyncContract.ENTITY_FASTING,
            fallbackEntityId = "fasting",
            fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
        )
        if (!appliedRevisions.shouldAccept(envelope)) {
            logWearSync(envelope, path, delivery, "ignored")
            return
        }
        FastingStore.saveSnapshot(this, fastingJson)
        logWearSync(envelope, path, delivery, "accepted")
        requestComplicationUpdates()
        requestTileUpdate()
    }

    private fun handleSessionEnd() {
        WorkoutStore.clearActiveSession(this)
        activeViewModel?.endSessionFromPhone()
        // Also retire the watch -> phone durable state. Without this it keeps
        // claiming has_active_session=true, and replayPersistentState() on the
        // next onPeerConnected re-pushes the finished session to the phone —
        // which adopts it again and re-posts the "started on watch"
        // notification. endSessionFromPhone() can't cover this: it runs with
        // notifyPhone=false, and activeViewModel is null whenever the watch app
        // isn't in the foreground.
        serviceScope.launch {
            try {
                WearDataLayerSyncManager(applicationContext).pushActiveWorkoutSession(null)
            } catch (e: Exception) {
                Log.e("SyncService", "Failed to clear watch active session state", e)
            }
        }
    }

    /// Keeps the original start time across updates so the elapsed timer
    /// doesn't reset every time the phone pushes a change.
    private fun persistSession(sessionJson: String) {
        val startEpoch = WorkoutStore.startedAtEpochMsFromSessionJson(sessionJson)
            ?: WorkoutStore.getActiveSessionStartEpoch(this)
            ?: System.currentTimeMillis()
        WorkoutStore.saveActiveSession(this, sessionJson, startEpoch)
    }

    override fun onPeerConnected(peer: Node) {
        super.onPeerConnected(peer)
        serviceScope.launch {
            val syncManager = WearDataLayerSyncManager(applicationContext)
            syncManager.replayPersistentState()
            syncManager.flushPendingRealtimeMessages()
        }
    }

    private fun requestComplicationUpdates() {
        for (service in listOf(
            CaloriesComplicationService::class.java,
            ProteinComplicationService::class.java,
            CarbsComplicationService::class.java,
            FatsComplicationService::class.java,
            FastingComplicationService::class.java,
            WeeklyVolumeComplicationService::class.java,
            WeeklySetsComplicationService::class.java,
        )) {
            ComplicationDataSourceUpdateRequester
                .create(this, ComponentName(this, service))
                .requestUpdateAll()
        }
    }

    private fun requestTileUpdate() {
        TileService.getUpdater(this).requestUpdate(MacrosTileService::class.java)
    }
}
