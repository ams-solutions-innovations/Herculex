package com.ams.herculex.nowbar

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class OngoingWorkoutSurfaceAdapter(
    context: Context,
    private val capability: LiveUpdatesCapability = LiveUpdatesCapability(context),
    private val renderer: OngoingWorkoutSurfaceRenderer = AndroidOngoingWorkoutSurfaceRenderer(
        context,
        capability,
    ),
) {
    companion object {
        const val CHANNEL_NAME = "com.ams.herculex/ongoing_workout_surface"
        private const val TAG = "OngoingWorkoutSurface"
        private const val ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS =
            "android.settings.APP_NOTIFICATION_PROMOTION_SETTINGS"
    }

    private val appContext = context.applicationContext
    private val actionQueue = OngoingWorkoutActionQueue(context)
    private val stateStore = OngoingWorkoutSurfaceStateStore(context)
    private var latestSnapshot: OngoingWorkoutSurfaceSnapshot? = null
    private var latestActionPendingIntents: Map<String, PendingIntent> = emptyMap()

    fun install(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                val rawSnapshot = call.arguments as? Map<*, *>
                if (rawSnapshot == null) {
                    result.error(
                        "INVALID_SNAPSHOT",
                        "Ongoing workout surface snapshot must be a map.",
                        null,
                    )
                    return
                }
                val snapshot = OngoingWorkoutSurfaceSnapshot.fromMap(rawSnapshot).getOrElse { error ->
                    result.error(
                        "INVALID_SNAPSHOT",
                        error.message ?: "Ongoing workout surface snapshot is invalid.",
                        null,
                    )
                    return
                }
                val previous = latestSnapshot
                // The elapsed label ticks continuously but is never rendered by the
                // notification — the chronometer draws it — so a snapshot that differs
                // only there is not worth a re-post.
                val onlyElapsedChanged = previous != null &&
                    previous.withoutElapsedLabel() == snapshot.withoutElapsedLabel()
                val targetChanged = previous == null ||
                    previous.sessionId != snapshot.sessionId ||
                    previous.targetSetId != snapshot.targetSetId

                latestSnapshot = snapshot
                if (targetChanged) {
                    latestActionPendingIntents = buildActionPendingIntents(snapshot)
                }
                stateStore.recordSurface(snapshot)

                if (onlyElapsedChanged) {
                    Log.i(TAG, "diagnostics event=updateSkipped reason=unchanged")
                } else {
                    renderer.show(snapshot, latestActionPendingIntents)
                    Log.d(
                        TAG,
                        "Updated ${snapshot.surfaceId} with " +
                            "${latestActionPendingIntents.size} action intents",
                    )
                }
                result.success(null)
            }

            "clear" -> {
                latestSnapshot = null
                latestActionPendingIntents = emptyMap()
                actionQueue.clear()
                stateStore.clearSurface()
                renderer.clear()
                Log.d(TAG, "Cleared snapshot")
                Log.i(TAG, "diagnostics event=cleared")
                result.success(null)
            }

            "drainPendingActions" -> {
                val activeSessionId = latestSnapshot?.sessionId ?: stateStore.displayState()?.sessionId
                if (activeSessionId == null) {
                    Log.i(TAG, "diagnostics event=drainSkipped reason=no_active_session")
                    result.success(emptyList<String>())
                    return
                }
                val drainResult = actionQueue.drainForSession(activeSessionId)
                val actions = drainResult.actions
                stateStore.clearQueuedActions()
                if (actions.isNotEmpty()) {
                    Log.i(
                        TAG,
                        "diagnostics event=drained session=$activeSessionId " +
                            "count=${actions.size} dropped=${drainResult.dropped} " +
                            "actions=${actions.joinToString(",") { action -> action.logLabel() }}",
                    )
                }
                if (drainResult.dropped > 0) {
                    stateStore.recordDroppedActions(drainResult.dropped)
                    Log.i(
                        TAG,
                        "diagnostics event=dropped session=$activeSessionId count=${drainResult.dropped}",
                    )
                }
                result.success(actions.map { action -> action.toMap() })
            }

            "getCapabilities" -> {
                result.success(capability.toMap())
            }

            "getSurfaceDiagnostics" -> {
                result.success(surfaceDiagnostics())
            }

            "sendDiagnosticAction" -> {
                result.success(sendDiagnosticAction(call))
            }

            "openPromotedNotificationSettings" -> {
                result.success(openPromotedNotificationSettings())
            }

            else -> result.notImplemented()
        }
    }

    private fun buildActionPendingIntents(
        snapshot: OngoingWorkoutSurfaceSnapshot,
    ): Map<String, PendingIntent> {
        return snapshot.expanded.actions
            .filter { action -> action.id in OngoingWorkoutActionReceiver.SUPPORTED_ACTION_IDS }
            .associate { action ->
                action.id to OngoingWorkoutActionReceiver.pendingIntentFor(
                    appContext,
                    action.id,
                    snapshot.sessionId,
                    snapshot.targetSetId,
                )
            }
    }

    private fun surfaceDiagnostics(): Map<String, Any?> {
        val snapshot = latestSnapshot
        val displayState = stateStore.displayState()
        return renderer.diagnostics() + stateStore.diagnostics() + mapOf(
            "surfaceId" to snapshot?.surfaceId,
            "sessionId" to (snapshot?.sessionId ?: displayState?.sessionId),
            "targetSetId" to (snapshot?.targetSetId ?: displayState?.targetSetId),
            "title" to (snapshot?.collapsed?.title ?: displayState?.title),
            "collapsedValue" to (snapshot?.collapsed?.value ?: displayState?.collapsedValue),
            "expandedRowCount" to (snapshot?.expanded?.rows?.size ?: 0),
            "expandedControlCount" to (snapshot?.expanded?.controls?.size ?: 0),
            "expandedActionCount" to latestActionPendingIntents.size,
            "supportedNativeActionIds" to OngoingWorkoutActionReceiver.SUPPORTED_ACTION_IDS,
            "diagnosticActionsAvailable" to appContext.isDebuggable(),
        )
    }

    private fun sendDiagnosticAction(call: MethodCall): Boolean {
        if (!appContext.isDebuggable()) {
            Log.w(TAG, "Ignoring diagnostic action outside debug build")
            return false
        }
        val args = call.arguments as? Map<*, *> ?: return false
        val actionId = args["actionId"] as? String ?: return false
        if (actionId !in OngoingWorkoutActionReceiver.SUPPORTED_ACTION_IDS) return false

        val displayState = stateStore.displayState()
        val sessionId = (args["sessionId"] as? Number)?.toLong()
            ?: latestSnapshot?.sessionId
            ?: displayState?.sessionId
            ?: return false
        val setId = (args["setId"] as? Number)?.toLong()
            ?: latestSnapshot?.targetSetId
            ?: displayState?.targetSetId

        return try {
            OngoingWorkoutActionReceiver.pendingIntentFor(
                appContext,
                actionId,
                sessionId,
                setId,
            ).send()
            Log.i(
                TAG,
                "diagnostics event=diagnosticActionSent action=$actionId " +
                    "session=$sessionId set=$setId",
            )
            true
        } catch (error: PendingIntent.CanceledException) {
            Log.w(TAG, "Unable to send diagnostic workout action $actionId", error)
            false
        }
    }

    private fun openPromotedNotificationSettings(): Boolean {
        val promotedSettingsIntent = Intent(ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, appContext.packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        if (startSettingsActivity(promotedSettingsIntent)) {
            return true
        }

        val appNotificationSettingsIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, appContext.packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return startSettingsActivity(appNotificationSettingsIntent)
    }

    private fun startSettingsActivity(intent: Intent): Boolean {
        return try {
            appContext.startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "Settings activity not found for ${intent.action}", error)
            false
        } catch (error: SecurityException) {
            Log.w(TAG, "Unable to open settings for ${intent.action}", error)
            false
        }
    }

    private fun Context.isDebuggable(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

}
