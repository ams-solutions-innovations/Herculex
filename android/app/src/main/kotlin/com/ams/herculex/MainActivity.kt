package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.util.Log
import androidx.lifecycle.lifecycleScope
import com.ams.herculex.sync.MobileWearSyncManager
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    private val wearChannel = "com.example.herculex/wear"
    private val widgetChannel = "com.ams.herculex/widget"
    private var methodChannel: MethodChannel? = null
    private val wearSyncManager by lazy { MobileWearSyncManager(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wearChannel)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "syncMacros" -> {
                    val calories = call.argument<Int>("calories") ?: 0
                    val protein  = call.argument<Int>("protein") ?: 0
                    val carbs    = call.argument<Int>("carbs") ?: 0
                    val fats     = call.argument<Int>("fats") ?: 0
                    val fasting  = call.argument<String>("fasting") ?: "0h 0m"
                    val weeklyTonnage = call.argument<Double>("weekly_tonnage") ?: 0.0
                    val weeklySets = call.argument<Int>("weekly_sets") ?: 0
                    val weeklyVolumeJson = call.argument<String>("weekly_volume_json") ?: "[]"
                    syncMacrosToWear(calories, protein, carbs, fats, fasting, weeklyTonnage, weeklySets, weeklyVolumeJson)
                    result.success(null)
                }
                "syncFastingSnapshot" -> {
                    val fastingJson = call.argument<String>("fasting_json") ?: ""
                    syncFastingSnapshotToWear(fastingJson)
                    result.success(null)
                }
                "syncWorkouts" -> {
                    val workoutsJson = call.argument<String>("workouts_json") ?: ""
                    syncWorkoutsToWear(workoutsJson)
                    result.success(null)
                }
                "syncCatalog" -> {
                    val catalogJson = call.argument<String>("catalog_json") ?: ""
                    syncCatalogToWear(catalogJson)
                    result.success(null)
                }
                "syncQuickAddFoods" -> {
                    val quickAddJson = call.argument<String>("quickadd_json") ?: ""
                    syncQuickAddFoodsToWear(quickAddJson)
                    result.success(null)
                }
                "syncActiveSession" -> {
                    val sessionJson = call.argument<String>("session_json") ?: ""
                    val isStart     = call.argument<Boolean>("is_start") ?: false
                    syncActiveSessionToWear(sessionJson, isStart)
                    result.success(null)
                }
                "endWorkoutOnWatch" -> {
                    val entityId = call.argument<String>("entity_id").orEmpty()
                    endWorkoutOnWear(entityId)
                    result.success(null)
                }
                "checkPendingWatchWorkout" -> {
                    dispatchPendingWorkout()
                    result.success(null)
                }
                "markWatchWorkoutApplied" -> {
                    // Dart has the watch's session in the database now, so the
                    // persisted copy has done its job.
                    PhoneWearListenerService.clearPendingWatchWorkout(applicationContext)
                    result.success(null)
                }
                "markWatchFastingCommandApplied" -> {
                    val commandId = call.argument<String>("command_id") ?: ""
                    PhoneWearListenerService.clearPendingFastingCommand(applicationContext, commandId)
                    sendFastingAckToWear(commandId)
                    result.success(null)
                }
                "markWatchQuickAddCommandApplied" -> {
                    val commandId = call.argument<String>("command_id") ?: ""
                    PhoneWearListenerService.clearPendingQuickAddCommand(applicationContext, commandId)
                    sendQuickAddAckToWear(commandId)
                    result.success(null)
                }
                "markWatchMacroCommandApplied" -> {
                    val commandId = call.argument<String>("command_id") ?: ""
                    PhoneWearListenerService.clearPendingMacroCommand(applicationContext, commandId)
                    sendMacroAckToWear(commandId)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Connect PhoneWearListenerService callbacks to Flutter MethodChannel
        PhoneWearListenerService.onWatchWorkoutStartListener = { sessionJson ->
            pendingSessionJson = sessionJson
            pendingJumpToWorkout = false
            runOnUiThread {
                dispatchPendingWorkout()
            }
        }

        PhoneWearListenerService.onWatchWorkoutUpdateListener = { sessionJson ->
            runOnUiThread {
                methodChannel?.invokeMethod("onWatchWorkoutUpdated", mapOf("session_json" to sessionJson))
            }
        }

        PhoneWearListenerService.onWatchWorkoutEndListener = { isDiscard, entityId ->
            runOnUiThread {
                methodChannel?.invokeMethod(
                    "onWatchWorkoutEnded",
                    mapOf("isDiscard" to isDiscard, "entityId" to entityId),
                )
            }
        }

        PhoneWearListenerService.onSyncRequestedListener = {
            runOnUiThread {
                methodChannel?.invokeMethod("onRequestSync", null)
            }
        }

        PhoneWearListenerService.onWatchFastingCommandListener = { commandJson ->
            runOnUiThread {
                methodChannel?.invokeMethod("onWatchFastingCommand", mapOf("command_json" to commandJson))
            }
        }

        PhoneWearListenerService.onWatchQuickAddCommandListener = { commandJson ->
            runOnUiThread {
                methodChannel?.invokeMethod("onWatchQuickAddCommand", mapOf("command_json" to commandJson))
            }
        }

        PhoneWearListenerService.onWatchMacroCommandListener = { commandJson ->
            runOnUiThread {
                methodChannel?.invokeMethod("onWatchMacroCommand", mapOf("command_json" to commandJson))
            }
        }

        // ── Home-screen widget sync channel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                val prefs = CnsWidgetProvider.getPrefs(applicationContext)
                val editor = prefs.edit()

                when (call.method) {
                    "syncMacros" -> {
                        editor.putInt(
                            CarbsWidgetProvider.KEY_CARBS_CURRENT,
                            call.argument<Int>("carbsCurrent") ?: 0
                        )
                        editor.putInt(
                            CarbsWidgetProvider.KEY_CARBS_TARGET,
                            call.argument<Int>("carbsTarget") ?: 0
                        )
                        editor.putInt(
                            FatWidgetProvider.KEY_FAT_CURRENT,
                            call.argument<Int>("fatCurrent") ?: 0
                        )
                        editor.putInt(
                            FatWidgetProvider.KEY_FAT_TARGET,
                            call.argument<Int>("fatTarget") ?: 0
                        )
                        editor.putInt(
                            ProteinWidgetProvider.KEY_PROTEIN_CURRENT,
                            call.argument<Int>("proteinCurrent") ?: 0
                        )
                        editor.putInt(
                            ProteinWidgetProvider.KEY_PROTEIN_TARGET,
                            call.argument<Int>("proteinTarget") ?: 0
                        )
                        editor.apply()
                        refreshWidgets(
                            CarbsWidgetProvider::class.java,
                            FatWidgetProvider::class.java,
                            ProteinWidgetProvider::class.java,
                        )
                        result.success(null)
                    }

                    "syncCns" -> {
                        editor.putInt(
                            CnsWidgetProvider.KEY_CNS_READINESS,
                            call.argument<Int>("readinessPct") ?: 0
                        )
                        editor.putString(
                            CnsWidgetProvider.KEY_CNS_STATUS,
                            call.argument<String>("status") ?: "—"
                        )
                        editor.apply()
                        refreshWidgets(CnsWidgetProvider::class.java)
                        result.success(null)
                    }

                    "syncRecovery" -> {
                        editor.putInt(
                            RecoveryWidgetProvider.KEY_RECOVERY_SCORE,
                            call.argument<Int>("scorePct") ?: 0
                        )
                        editor.apply()
                        refreshWidgets(RecoveryWidgetProvider::class.java)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private var pendingSessionJson: String? = null
    private var pendingJumpToWorkout: Boolean = false

    private fun refreshWidgets(vararg providerClasses: Class<*>) {
        val manager = AppWidgetManager.getInstance(applicationContext)
        for (cls in providerClasses) {
            @Suppress("UNCHECKED_CAST")
            val ids = manager.getAppWidgetIds(
                ComponentName(applicationContext, cls as Class<android.appwidget.AppWidgetProvider>)
            )
            if (ids.isNotEmpty()) {
                val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                    component = ComponentName(applicationContext, cls)
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                sendBroadcast(intent)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWorkoutsIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleWorkoutsIntent(intent)
    }

    private fun handleWorkoutsIntent(intent: Intent?) {
        if (intent?.action == ScannerWidgetProvider.ACTION_SCAN) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, widgetChannel).invokeMethod("openScanner", null)
            }
            intent?.action = null
        }

        if (intent?.getBooleanExtra("open_active_workout", false) == true) {
            val sessionJson = intent.getStringExtra("session_json")
            pendingJumpToWorkout = true
            intent.removeExtra("open_active_workout")
            if (sessionJson != null) {
                pendingSessionJson = sessionJson
                dispatchPendingWorkout()
            } else {
                openActiveWorkoutInFlutter()
            }
        }
    }

    private fun openActiveWorkoutInFlutter() {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, widgetChannel).invokeMethod("openActiveWorkout", null)
        }
    }

    /**
     * Hands the watch's session to Dart.
     *
     * The persisted copy is deliberately NOT cleared here. `invokeMethod` is
     * fire-and-forget, and both callers run before Dart has registered its
     * watch handlers: `onResume` (notification tap) fires before the first
     * widget build, and `checkPendingWatchWorkout` is invoked from `main()`.
     * Clearing on dispatch therefore threw the workout away in exactly the
     * case it mattered — opening the app from the "started on watch"
     * notification. Dart acks via `markWatchWorkoutApplied` once the session
     * is in the database; until then the copy survives to be replayed.
     */
    private fun dispatchPendingWorkout() {
        val sessionJson = pendingSessionJson
        if (sessionJson != null) {
            val jump = pendingJumpToWorkout
            pendingSessionJson = null
            pendingJumpToWorkout = false
            methodChannel?.invokeMethod(
                "onWatchWorkoutStarted",
                mapOf("session_json" to sessionJson, "jump_to_workout" to jump)
            )
            return
        }

        val storedSessionJson = PhoneWearListenerService.pendingWatchWorkout(applicationContext)
        if (storedSessionJson != null) {
            methodChannel?.invokeMethod(
                "onWatchWorkoutUpdated",
                mapOf("session_json" to storedSessionJson)
            )
        }
        for (commandJson in PhoneWearListenerService.pendingFastingCommands(applicationContext)) {
            methodChannel?.invokeMethod(
                "onWatchFastingCommand",
                mapOf("command_json" to commandJson),
            )
        }
        for (commandJson in PhoneWearListenerService.pendingQuickAddCommands(applicationContext)) {
            methodChannel?.invokeMethod(
                "onWatchQuickAddCommand",
                mapOf("command_json" to commandJson),
            )
        }
        for (commandJson in PhoneWearListenerService.pendingMacroCommands(applicationContext)) {
            methodChannel?.invokeMethod(
                "onWatchMacroCommand",
                mapOf("command_json" to commandJson),
            )
        }
    }

    // ── Wearable DataClient Sync Helpers ─────────────────────────────────────

    private fun syncMacrosToWear(calories: Int, protein: Int, carbs: Int, fats: Int, fasting: String, weeklyTonnage: Double, weeklySets: Int, weeklyVolumeJson: String) {
        val putDataMapReq = PutDataMapRequest.create("/herculex_sync_data")
        putDataMapReq.dataMap.putInt("calories", calories)
        putDataMapReq.dataMap.putInt("protein", protein)
        putDataMapReq.dataMap.putInt("carbs", carbs)
        putDataMapReq.dataMap.putInt("fats", fats)
        putDataMapReq.dataMap.putString("fasting", fasting)
        putDataMapReq.dataMap.putDouble("weekly_tonnage", weeklyTonnage)
        putDataMapReq.dataMap.putInt("weekly_sets", weeklySets)
        putDataMapReq.dataMap.putString("weekly_volume_json", weeklyVolumeJson)
        putDataMapReq.dataMap.putLong("timestamp", System.currentTimeMillis())
        val putDataReq = putDataMapReq.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(putDataReq)
            .addOnSuccessListener { Log.d("WearSync", "Synced macros & volume to wear") }
            .addOnFailureListener { e -> Log.e("WearSync", "Failed to sync macros & volume", e) }
    }

    private fun syncFastingSnapshotToWear(fastingJson: String) {
        lifecycleScope.launch {
            try {
                wearSyncManager.syncFastingSnapshot(fastingJson)
                Log.d("WearSync", "Synced fasting snapshot to wear")
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to sync fasting snapshot", e)
            }
        }
    }

    private fun syncWorkoutsToWear(workoutsJson: String) {
        val putDataMapReq = PutDataMapRequest.create("/herculex_workout_data")
        putDataMapReq.dataMap.putString("workouts_json", workoutsJson)
        putDataMapReq.dataMap.putLong("timestamp", System.currentTimeMillis())
        val putDataReq = putDataMapReq.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(putDataReq)
            .addOnSuccessListener { Log.d("WearSync", "Synced workouts to wear") }
            .addOnFailureListener { e -> Log.e("WearSync", "Failed to sync workouts", e) }
    }

    private fun syncCatalogToWear(catalogJson: String) {
        val putDataMapReq = PutDataMapRequest.create("/herculex_catalog_data")
        putDataMapReq.dataMap.putString("catalog_json", catalogJson)
        putDataMapReq.dataMap.putLong("timestamp", System.currentTimeMillis())
        val putDataReq = putDataMapReq.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(putDataReq)
            .addOnSuccessListener { Log.d("WearSync", "Synced catalog to wear") }
            .addOnFailureListener { e -> Log.e("WearSync", "Failed to sync catalog", e) }
    }

    private fun syncQuickAddFoodsToWear(quickAddJson: String) {
        val putDataMapReq = PutDataMapRequest.create("/herculex_quickadd_data")
        putDataMapReq.dataMap.putString("quickadd_json", quickAddJson)
        putDataMapReq.dataMap.putLong("timestamp", System.currentTimeMillis())
        val putDataReq = putDataMapReq.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(putDataReq)
            .addOnSuccessListener { Log.d("WearSync", "Synced quick-add foods to wear") }
            .addOnFailureListener { e -> Log.e("WearSync", "Failed to sync quick-add foods", e) }
    }

    private fun syncActiveSessionToWear(sessionJson: String, isStart: Boolean) {
        // Fast path: MessageClient delivery to a connected watch is near-instant,
        // unlike DataClient puts which the system can batch/coalesce.
        // wearSyncManager also persists the state for reconnect replay.
        lifecycleScope.launch {
            try {
                wearSyncManager.syncActiveSession(sessionJson, isStart)
                Log.d("WearSync", "Synced active session to wear (isStart=$isStart)")
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to sync active session to wear", e)
            }
        }
    }

    private fun endWorkoutOnWear(entityId: String) {
        if (entityId.isBlank()) return
        PhoneWearListenerService.clearPendingWatchWorkout(applicationContext)
        PhoneWearListenerService.clearNotifiedWatchSession(applicationContext)
        lifecycleScope.launch {
            try {
                wearSyncManager.endActiveSession(entityId)
                Log.d("WearSync", "Synced session end to wear")
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to sync session end to wear", e)
            }
        }
    }

    private fun sendFastingAckToWear(commandId: String) {
        if (commandId.isBlank()) return
        lifecycleScope.launch {
            try {
                wearSyncManager.sendRealtimeEvent(
                    com.ams.herculex.sync.WearSyncPaths.MESSAGE_FASTING_ACK,
                    "{\"commandId\":\"$commandId\"}",
                )
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to ack fasting command", e)
            }
        }
    }

    private fun sendQuickAddAckToWear(commandId: String) {
        if (commandId.isBlank()) return
        lifecycleScope.launch {
            try {
                wearSyncManager.sendRealtimeEvent(
                    com.ams.herculex.sync.WearSyncPaths.MESSAGE_QUICKADD_ACK,
                    "{\"commandId\":\"$commandId\"}",
                )
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to ack quick-add command", e)
            }
        }
    }

    private fun sendMacroAckToWear(commandId: String) {
        if (commandId.isBlank()) return
        lifecycleScope.launch {
            try {
                wearSyncManager.sendRealtimeEvent(
                    com.ams.herculex.sync.WearSyncPaths.MESSAGE_MACRO_ACK,
                    "{\"commandId\":\"$commandId\"}",
                )
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to ack macro command", e)
            }
        }
    }
}
