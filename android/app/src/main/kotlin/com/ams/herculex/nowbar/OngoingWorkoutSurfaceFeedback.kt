package com.ams.herculex.nowbar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ams.herculex.MainActivity
import com.ams.herculex.R

object OngoingWorkoutSurfaceFeedback {
    fun showQueued(context: Context, actionId: String): Boolean {
        val appContext = context.applicationContext
        val state = OngoingWorkoutSurfaceStateStore(appContext).displayState()
        if (state == null) {
            Log.i(TAG, "diagnostics event=feedbackSkipped action=$actionId reason=no_display_state")
            return false
        }
        val manager = appContext.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)

        val actionLabel = state.actionLabels[actionId] ?: actionId
        val queuedLine = "Queued $actionLabel"
        val expandedText = listOf(
            queuedLine,
            state.expandedContent,
        ).filter { value -> value.isNotBlank() }.joinToString("\n")

        val builder = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(state.title)
            .setContentText("$queuedLine - ${state.compactContent}".trimEnd('-', ' '))
            .setSubText(state.collapsedValue.ifBlank { null })
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(state.title)
                    .bigText(expandedText)
                    .setSummaryText(state.collapsedValue.ifBlank { null }),
            )
            .setContentIntent(openWorkoutIntent(appContext, state.sessionId))
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(state.startedAtMillis)
            .setUsesChronometer(true)
            .setLocalOnly(true)
            .setSilent(true)

        OngoingWorkoutActionReceiver.SUPPORTED_ACTION_IDS.forEach { supportedActionId ->
            val label = state.actionLabels[supportedActionId] ?: return@forEach
            builder.addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_edit,
                    label,
                    OngoingWorkoutActionReceiver.pendingIntentFor(
                        appContext,
                        supportedActionId,
                        state.sessionId,
                        state.targetSetId,
                    ),
                ).build(),
            )
        }

        val notification = builder.build().apply {
            flags = flags or Notification.FLAG_ONGOING_EVENT
        }
        val posted = runCatching {
            manager.notify(NOTIFICATION_ID, notification)
        }.onFailure { error ->
            Log.w(TAG, "Unable to show queued workout feedback", error)
        }.isSuccess
        Log.i(
            TAG,
            "diagnostics event=feedback action=$actionId posted=$posted label=\"$actionLabel\" " +
                "session=${state.sessionId} value=\"${state.collapsedValue}\"",
        )
        return posted
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows active workout status and quick set controls"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun openWorkoutIntent(context: Context, sessionId: Long): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_active_workout", true)
            putExtra("active_session_id", sessionId)
        }
        return PendingIntent.getActivity(
            context,
            OPEN_WORKOUT_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private const val CHANNEL_ID = "workout_live"
    private const val CHANNEL_NAME = "Live Workout"
    /**
     * Deliberately NOT id 1 — that id belongs to the promotable Live Update posted by
     * [AndroidOngoingWorkoutSurfaceRenderer], and reusing it would overwrite the promoted
     * notification with this non-promotable one.
     */
    private const val NOTIFICATION_ID = 4202
    private const val OPEN_WORKOUT_REQUEST_CODE = 4201
    private const val TAG = "WorkoutSurfaceFeedback"
}
