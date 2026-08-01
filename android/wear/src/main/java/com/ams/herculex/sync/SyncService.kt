package com.ams.herculex.sync

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.ams.herculex.MainActivity
import com.ams.herculex.complication.CaloriesComplicationService
import com.ams.herculex.complication.CarbsComplicationService
import com.ams.herculex.complication.FastingComplicationService
import com.ams.herculex.complication.FatsComplicationService
import com.ams.herculex.complication.ProteinComplicationService
import com.ams.herculex.tile.MacrosTileService
import com.ams.herculex.workout.ExerciseCatalog
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

                    MacroStore.save(this, calories, protein, carbs, fats, fasting)

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
                        handleSessionUpdate(sessionJson)
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
                handleSessionStart(String(messageEvent.data))
            }
            WearSyncPaths.MESSAGE_ACTIVE_SESSION_UPDATE -> {
                handleSessionUpdate(String(messageEvent.data))
            }
            WearSyncPaths.MESSAGE_ACTIVE_SESSION_END -> {
                handleSessionEnd()
            }
        }
    }

    private fun handleSessionStart(sessionJson: String?) {
        Log.d("SyncService", "Active workout start received from phone")
        if (!sessionJson.isNullOrBlank()) {
            persistSession(sessionJson)
            WorkoutStore.parseAndStartSession(this, sessionJson, activeViewModel)
        }
        // Launch MainActivity on watch to display live workout screen. Only
        // the explicit start signal does this — see the durable-path note in
        // onDataChanged.
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(launchIntent)
    }

    private fun handleSessionUpdate(sessionJson: String?) {
        if (!sessionJson.isNullOrBlank()) {
            // Persist unconditionally: when the watch app isn't running there
            // is no activeViewModel to update, and without this the session
            // would be lost entirely rather than restored on next launch.
            persistSession(sessionJson)
            WorkoutStore.parseAndUpdateSession(sessionJson, activeViewModel)
        }
    }

    private fun handleSessionEnd() {
        WorkoutStore.clearActiveSession(this)
        activeViewModel?.endSessionFromPhone()
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
