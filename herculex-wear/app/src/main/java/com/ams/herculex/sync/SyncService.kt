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
import com.google.android.gms.wearable.WearableListenerService

class SyncService : WearableListenerService() {

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

                // ── Active workout session start from phone ─────────────────
                path.startsWith("/herculex_active_session_start") -> {
                    val sessionJson = dataMap.getString("session_json")
                    Log.d("SyncService", "Active workout start received from phone")
                    if (!sessionJson.isNullOrBlank()) {
                        WorkoutStore.parseAndStartSession(this, sessionJson, activeViewModel)
                    }
                    // Launch MainActivity on watch to display live workout screen
                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    startActivity(launchIntent)
                }

                // ── Active workout session update from phone ────────────────
                path.startsWith("/herculex_active_session_update") -> {
                    val sessionJson = dataMap.getString("session_json")
                    if (!sessionJson.isNullOrBlank()) {
                        WorkoutStore.parseAndUpdateSession(sessionJson, activeViewModel)
                    }
                }

                // ── Active workout session end from phone ───────────────────
                path.startsWith("/herculex_active_session_end") -> {
                    activeViewModel?.finishWorkout()
                }
            }
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
