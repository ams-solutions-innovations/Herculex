package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.util.Log
import androidx.lifecycle.lifecycleScope
import com.ams.herculex.bubble.WorkoutBubbleController
import com.ams.herculex.sync.MobileWearSyncManager
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

// The `health` plugin registers its Health Connect permission launcher via
// registerForActivityResult, which requires a FragmentActivity host to work
// reliably through the full activity lifecycle. Plain FlutterActivity leaves
// that launcher unregistered (native log: "Permission launcher not found"),
// which silently fails every permission request/toggle.
class MainActivity : FlutterFragmentActivity() {

    private val wearChannel = "com.example.herculex/wear"
    private val widgetChannel = "com.ams.herculex/widget"
    private val bubbleChannel = "com.ams.herculex/workout_bubble"
    private var methodChannel: MethodChannel? = null
    private var bubbleMethodChannel: MethodChannel? = null
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
                    val nutrientTrendsJson = call.argument<String>("nutrient_trends_json") ?: "[]"
                    val calorieGoal = call.argument<Int>("calorie_goal") ?: 2000
                    val proteinGoal = call.argument<Int>("protein_goal") ?: 150
                    val carbsGoal   = call.argument<Int>("carbs_goal") ?: 200
                    val fatGoal     = call.argument<Int>("fat_goal") ?: 65
                    val waterGoal   = call.argument<Int>("water_goal") ?: 2000
                    syncMacrosToWear(calories, protein, carbs, fats, fasting, weeklyTonnage, weeklySets, weeklyVolumeJson, nutrientTrendsJson, calorieGoal, proteinGoal, carbsGoal, fatGoal, waterGoal)
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
                "markWatchRamblerCommandApplied" -> {
                    val commandId = call.argument<String>("command_id") ?: ""
                    PhoneWearListenerService.clearPendingRamblerCommand(applicationContext, commandId)
                    sendRamblerAckToWear(commandId)
                    result.success(null)
                }
                "syncMediaState" -> {
                    val mediaJson = call.argument<String>("media_json") ?: ""
                    syncMediaStateToWear(mediaJson)
                    result.success(null)
                }
                "getMediaInfoNative" -> {
                    result.success(getCurrentMediaInfoNative())
                }
                "mediaActionNative" -> {
                    val action = call.argument<String>("action") ?: ""
                    performMediaActionNative(action)
                    result.success(null)
                }
                "sendAchievement" -> {
                    val achievementJson = call.argument<String>("achievement_json") ?: ""
                    sendAchievementToWear(achievementJson)
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

        PhoneWearListenerService.onWatchRamblerCommandListener = { commandJson ->
            runOnUiThread {
                methodChannel?.invokeMethod("onWatchRamblerCommand", mapOf("command_json" to commandJson))
            }
        }

        PhoneWearListenerService.onWatchMediaCommandListener = { commandJson ->
            runOnUiThread {
                methodChannel?.invokeMethod("onWatchMediaCommand", mapOf("command_json" to commandJson))
            }
        }

        // Rep-capture traffic (`/herculex/reps/*`, 10-03b). One listener for
        // all three paths, forwarded verbatim — this file never parses,
        // reorders or recomputes a capture payload (REP-04/T-10-12).
        PhoneWearListenerService.onRepMessageListener = { path, payload ->
            runOnUiThread {
                methodChannel?.invokeMethod(
                    "onRepMessage",
                    mapOf("path" to path, "payload" to payload),
                )
            }
        }

        // ── Home-screen widget sync channel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                val prefs = CnsWidgetProvider.getPrefs(applicationContext)
                val editor = prefs.edit()

                when (call.method) {
                    "syncNutrition", "syncMacros" -> {
                        editor.putInt(
                            TodayCaloriesSmallWidgetProvider.KEY_CALORIES_BASE_GOAL,
                            call.argument<Int>("baseGoalKcal") ?: 0
                        )
                        editor.putInt(
                            TodayCaloriesSmallWidgetProvider.KEY_CALORIES_FOOD,
                            call.argument<Int>("foodKcal") ?: 0
                        )
                        editor.putInt(
                            TodayCaloriesSmallWidgetProvider.KEY_CALORIES_EXERCISE,
                            call.argument<Int>("exerciseKcal") ?: 0
                        )
                        editor.putInt(
                            TodayCaloriesSmallWidgetProvider.KEY_CALORIES_REMAINING,
                            call.argument<Int>("remainingKcal") ?: 0
                        )
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
                            TodayCaloriesSmallWidgetProvider::class.java,
                            TodayCaloriesMediumWidgetProvider::class.java,
                            TodayMacrosMediumWidgetProvider::class.java,
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

        // ── Workout Bubble (floating chat head) channel ───────────────────────
        val bubble = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bubbleChannel)
        bubbleMethodChannel = bubble
        bubble.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    // Drift row ids arrive as Int or Long depending on
                    // magnitude, so read them as a plain Number.
                    val sessionId = call.argument<Number>("sessionId")?.toLong()
                    val startedAt = call.argument<Number>("startedAtEpochMs")?.toLong()
                    if (sessionId == null || startedAt == null) {
                        result.error(
                            "bad_args",
                            "sessionId and startedAtEpochMs are required",
                            null,
                        )
                    } else {
                        WorkoutBubbleController.show(
                            applicationContext,
                            WorkoutBubbleController.BubbleSnapshot(
                                sessionId = sessionId,
                                startedAtEpochMs = startedAt,
                                exerciseName = call.argument<String>("exerciseName").orEmpty(),
                                subtitle = call.argument<String>("subtitle").orEmpty(),
                                setNumber = call.argument<String>("setNumber") ?: "1",
                                weight = call.argument<String>("weight") ?: "-",
                                reps = call.argument<String>("reps") ?: "-",
                                rpe = call.argument<String>("rpe") ?: "RPE",
                                totalSetsText = call.argument<String>("totalSetsText") ?: "0",
                                tonnageText = call.argument<String>("tonnageText") ?: "0 kg",
                                lastSetText = call.argument<String>("lastSetText"),
                                targetSetId = call.argument<Number>("targetSetId")?.toLong(),
                                actions = parseBubbleActions(call.argument("actions")),
                            ),
                        )
                        result.success(null)
                    }
                }

                "hide" -> {
                    WorkoutBubbleController.hide(applicationContext)
                    result.success(null)
                }

                "canDrawOverlays" -> {
                    result.success(WorkoutBubbleController.canDrawOverlays(applicationContext))
                }

                else -> result.notImplemented()
            }
        }

        // Control taps in the bubble's popup are applied by Dart through the
        // same command helper the notification actions use — this side only
        // forwards the shared action ID.
        WorkoutBubbleController.onAction = { actionId, sessionId, setId, value ->
            runOnUiThread {
                bubbleMethodChannel?.invokeMethod(
                    "onBubbleAction",
                    mapOf(
                        "actionId" to actionId,
                        "sessionId" to sessionId,
                        "setId" to setId,
                        "value" to value,
                    ),
                )
            }
        }
    }

    private fun parseBubbleActions(raw: List<Map<String, Any?>>?): List<WorkoutBubbleController.BubbleAction> {
        if (raw == null) return emptyList()
        return raw.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            WorkoutBubbleController.BubbleAction(
                id = id,
                label = entry["label"] as? String ?: id,
                primary = entry["primary"] as? Boolean ?: false,
            )
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
        // Native guard: the bubble must never float on top of the app itself.
        // Dart hides it from its own lifecycle listener too, but that only
        // works once the engine is running — this covers a cold start opened
        // straight from the bubble.
        WorkoutBubbleController.clearDismissed()
        WorkoutBubbleController.hide(applicationContext)
        handleWorkoutsIntent(intent)
    }

    override fun onDestroy() {
        // The overlay deliberately outlives this Activity, but the Flutter
        // engine does not. Leaving the sink attached would have popup taps
        // invoke a dead channel and silently do nothing; nulling it makes the
        // controller fall back to reopening the app instead.
        WorkoutBubbleController.onAction = null
        bubbleMethodChannel = null
        super.onDestroy()
    }

    private fun handleWorkoutsIntent(intent: Intent?) {
        if (intent?.action == ScannerWidgetProvider.ACTION_SCAN) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, widgetChannel).invokeMethod("openScanner", null)
            }
            intent?.action = null
        }

        if (intent?.action == TodayCaloriesMediumWidgetProvider.ACTION_SEARCH_FOOD) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, widgetChannel).invokeMethod("openFoodSearch", null)
            }
            intent?.action = null
        }

        if (intent?.action == TodayCaloriesSmallWidgetProvider.ACTION_OPEN_NUTRITION) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, widgetChannel).invokeMethod("openNutrition", null)
            }
            intent?.action = null
        }

        if (intent?.getBooleanExtra("open_active_workout", false) == true) {
            val sessionJson = intent.getStringExtra("session_json")
            val action = intent.getStringExtra("workout_action")
            pendingJumpToWorkout = true
            intent.removeExtra("open_active_workout")
            intent.removeExtra("workout_action")
            if (sessionJson != null) {
                pendingSessionJson = sessionJson
                dispatchPendingWorkout()
            } else {
                openActiveWorkoutInFlutter(action)
            }
        }
    }

    private fun openActiveWorkoutInFlutter(action: String? = null) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            val args = if (action != null) mapOf("action" to action) else null
            MethodChannel(messenger, widgetChannel).invokeMethod("openActiveWorkout", args)
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
        } else {
            val storedSessionJson = PhoneWearListenerService.pendingWatchWorkout(applicationContext)
            if (storedSessionJson != null) {
                methodChannel?.invokeMethod(
                    "onWatchWorkoutUpdated",
                    mapOf("session_json" to storedSessionJson)
                )
            }
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
        for (commandJson in PhoneWearListenerService.pendingRamblerCommands(applicationContext)) {
            methodChannel?.invokeMethod(
                "onWatchRamblerCommand",
                mapOf("command_json" to commandJson),
            )
        }
    }

    // ── Wearable DataClient Sync Helpers ─────────────────────────────────────

    private fun syncMacrosToWear(
        calories: Int,
        protein: Int,
        carbs: Int,
        fats: Int,
        fasting: String,
        weeklyTonnage: Double,
        weeklySets: Int,
        weeklyVolumeJson: String,
        nutrientTrendsJson: String = "[]",
        calorieGoal: Int = 2000,
        proteinGoal: Int = 150,
        carbsGoal: Int = 200,
        fatGoal: Int = 65,
        waterGoal: Int = 2000,
    ) {
        val putDataMapReq = PutDataMapRequest.create("/herculex_sync_data")
        putDataMapReq.dataMap.putInt("calories", calories)
        putDataMapReq.dataMap.putInt("protein", protein)
        putDataMapReq.dataMap.putInt("carbs", carbs)
        putDataMapReq.dataMap.putInt("fats", fats)
        putDataMapReq.dataMap.putString("fasting", fasting)
        putDataMapReq.dataMap.putDouble("weekly_tonnage", weeklyTonnage)
        putDataMapReq.dataMap.putInt("weekly_sets", weeklySets)
        putDataMapReq.dataMap.putString("weekly_volume_json", weeklyVolumeJson)
        putDataMapReq.dataMap.putString("nutrient_trends_json", nutrientTrendsJson)
        putDataMapReq.dataMap.putInt("calorie_goal", calorieGoal)
        putDataMapReq.dataMap.putInt("protein_goal", proteinGoal)
        putDataMapReq.dataMap.putInt("carbs_goal", carbsGoal)
        putDataMapReq.dataMap.putInt("fat_goal", fatGoal)
        putDataMapReq.dataMap.putInt("water_goal", waterGoal)
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

    private fun syncMediaStateToWear(mediaJson: String) {
        lifecycleScope.launch {
            try {
                wearSyncManager.syncMediaState(mediaJson)
                Log.d("WearSync", "Synced media state to wear: $mediaJson")
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to sync media state to wear", e)
            }
        }
    }

    /// Replaces the `flutter_media_controller` plugin's own `getMediaInfo` —
    /// that plugin's native side calls `getActiveSessions()` scoped to
    /// `MediaControlWidgetProvider` (a plain `AppWidgetProvider`, never
    /// granted or grantable notification-listener access), so it always
    /// throws `SecurityException` and silently falls back to "no track
    /// playing". The listener actually declared and grantable in our
    /// manifest is the plugin's `MediaNotificationListener` service — this
    /// queries against that instead. Also prefers a session that's actually
    /// [PlaybackState.STATE_PLAYING] over `getActiveSessions()`'s first
    /// entry, which has no ordering guarantee and can be some other app's
    /// paused/idle session ahead of Spotify's.
    private fun getCurrentMediaInfoNative(): Map<String, Any> {
        val mediaSessionManager = getSystemService(android.content.Context.MEDIA_SESSION_SERVICE)
            as android.media.session.MediaSessionManager
        val componentName = ComponentName(
            this,
            com.example.flutter_media_controller.MediaNotificationListener::class.java,
        )
        try {
            val controllers = mediaSessionManager.getActiveSessions(componentName)
            val controller = controllers.firstOrNull {
                it.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
            } ?: controllers.firstOrNull()
            if (controller != null) {
                val metadata = controller.metadata
                val isPlaying = controller.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
                val artwork = metadata?.getBitmap(android.media.MediaMetadata.METADATA_KEY_ART)
                    ?: metadata?.getBitmap(android.media.MediaMetadata.METADATA_KEY_ALBUM_ART)
                val thumbnailBase64 = artwork?.let { bitmap ->
                    val out = java.io.ByteArrayOutputStream()
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                    android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.DEFAULT)
                } ?: ""
                return mapOf(
                    "track" to (metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""),
                    "artist" to (metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST) ?: ""),
                    "isPlaying" to isPlaying,
                    "packageName" to controller.packageName,
                    "thumbnailUrl" to thumbnailBase64,
                )
            }
        } catch (e: SecurityException) {
            Log.w("MediaInfo", "Notification listener access not granted for MediaNotificationListener", e)
        }
        return mapOf("track" to "", "artist" to "", "isPlaying" to false, "packageName" to "", "thumbnailUrl" to "")
    }

    /// Replaces the `flutter_media_controller` plugin's own `mediaAction` —
    /// same wrong-`ComponentName` bug as [getCurrentMediaInfoNative], so
    /// watch/phone transport commands (play/pause/next/previous) silently
    /// no-op via the plugin's native path.
    private fun performMediaActionNative(action: String) {
        val mediaSessionManager = getSystemService(android.content.Context.MEDIA_SESSION_SERVICE)
            as android.media.session.MediaSessionManager
        val componentName = ComponentName(
            this,
            com.example.flutter_media_controller.MediaNotificationListener::class.java,
        )
        try {
            val controllers = mediaSessionManager.getActiveSessions(componentName)
            val controller = controllers.firstOrNull {
                it.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
            } ?: controllers.firstOrNull() ?: return
            when (action) {
                "previous" -> controller.transportControls.skipToPrevious()
                "next" -> controller.transportControls.skipToNext()
                "playPause", "play_pause" -> {
                    if (controller.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING) {
                        controller.transportControls.pause()
                    } else {
                        controller.transportControls.play()
                    }
                }
            }
        } catch (e: SecurityException) {
            Log.w("MediaInfo", "Notification listener access not granted for MediaNotificationListener", e)
        }
    }

    private fun sendAchievementToWear(achievementJson: String) {
        if (achievementJson.isBlank()) return
        lifecycleScope.launch {
            try {
                wearSyncManager.sendAchievement(achievementJson)
                Log.d("WearSync", "Sent achievement to wear: $achievementJson")
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to send achievement to wear", e)
            }
        }
    }

    private fun endWorkoutOnWear(entityId: String) {
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

    private fun sendRamblerAckToWear(commandId: String) {
        if (commandId.isBlank()) return
        lifecycleScope.launch {
            try {
                wearSyncManager.sendRealtimeEvent(
                    com.ams.herculex.sync.WearSyncPaths.MESSAGE_RAMBLER_ACK,
                    "{\"commandId\":\"$commandId\"}",
                )
            } catch (e: Exception) {
                Log.e("WearSync", "Failed to ack rambler command", e)
            }
        }
    }
}
