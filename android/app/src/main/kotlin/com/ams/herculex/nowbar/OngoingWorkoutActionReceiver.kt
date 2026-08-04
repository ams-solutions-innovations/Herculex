package com.ams.herculex.nowbar

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.ams.herculex.MainActivity

class OngoingWorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WORKOUT_SURFACE_COMMAND) return
        val actionId = intent.getStringExtra(EXTRA_ACTION_ID)
        if (actionId.isNullOrBlank() || actionId !in SUPPORTED_ACTION_IDS) {
            Log.w(TAG, "Ignored unsupported workout surface action $actionId")
            return
        }
        val sessionId = intent.getLongExtra(EXTRA_SESSION_ID, 0L)
        val setId = if (intent.hasExtra(EXTRA_SET_ID)) {
            intent.getLongExtra(EXTRA_SET_ID, 0L).takeIf { value -> value > 0L }
        } else {
            null
        }
        val stateStore = OngoingWorkoutSurfaceStateStore(context)
        val activeState = stateStore.displayState()
        val activeSessionId = activeState?.sessionId
        val activeSetId = activeState?.targetSetId
        if (sessionId <= 0L || activeSessionId == null || sessionId != activeSessionId) {
            stateStore.recordRejectedAction(actionId, REJECT_REASON_STALE_SESSION)
            Log.w(
                TAG,
                "Ignored stale workout surface action $actionId for session=$sessionId active=$activeSessionId",
            )
            Log.i(
                TAG,
                "diagnostics event=rejected action=$actionId session=$sessionId active=$activeSessionId",
            )
            return
        }
        if (setId != null && activeSetId != null && setId != activeSetId) {
            stateStore.recordRejectedAction(actionId, REJECT_REASON_STALE_SET)
            Log.w(
                TAG,
                "Ignored stale workout surface action $actionId for set=$setId activeSet=$activeSetId",
            )
            Log.i(
                TAG,
                "diagnostics event=rejected action=$actionId reason=stale_set " +
                    "session=$sessionId set=$setId activeSet=$activeSetId",
            )
            return
        }
        if (actionId in activeState.requiresUnlockActionIds) {
            // No action is flagged today (all five are low-risk), so this is a guard
            // against a future high-risk action being executed silently from the lock
            // screen rather than a change to current behaviour.
            stateStore.recordRejectedAction(actionId, REJECT_REASON_REQUIRES_UNLOCK)
            launchAppForUnlock(context, sessionId)
            Log.w(TAG, "Deferred workout surface action $actionId until unlock")
            Log.i(
                TAG,
                "diagnostics event=rejected action=$actionId reason=requires_unlock " +
                    "session=$sessionId set=$setId",
            )
            return
        }
        OngoingWorkoutActionQueue(context).enqueue(actionId, sessionId, setId)
        val feedbackPosted = OngoingWorkoutSurfaceFeedback.showQueued(context, actionId)
        stateStore.recordQueuedAction(actionId, feedbackPosted)
        Log.d(TAG, "Queued workout surface action $actionId")
        Log.i(
            TAG,
            "diagnostics event=queued action=$actionId session=$sessionId " +
                "set=$setId feedbackPosted=$feedbackPosted",
        )
    }

    /**
     * Sends the user to the app (through the keyguard) instead of executing the
     * action, so a high-risk command is never applied from the lock screen.
     */
    private fun launchAppForUnlock(context: Context, sessionId: Long) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_active_workout", true)
            putExtra("active_session_id", sessionId)
        }
        runCatching { context.startActivity(intent) }.onFailure { error ->
            Log.w(TAG, "Unable to launch app for unlock-gated workout action", error)
        }
    }

    companion object {
        const val ACTION_WORKOUT_SURFACE_COMMAND =
            "com.ams.herculex.nowbar.WORKOUT_SURFACE_COMMAND"
        const val EXTRA_ACTION_ID = "action_id"
        const val EXTRA_SESSION_ID = "session_id"
        const val EXTRA_SET_ID = "set_id"

        private const val TAG = "OngoingWorkoutAction"
        private const val REJECT_REASON_STALE_SESSION = "stale_session"
        private const val REJECT_REASON_STALE_SET = "stale_set"
        private const val REJECT_REASON_REQUIRES_UNLOCK = "requires_unlock"

        val SUPPORTED_ACTION_IDS = listOf(
            "workout.reps.up",
            "workout.weight.up",
            "workout.set.complete",
            "workout.reps.down",
            "workout.weight.down",
        )

        fun pendingIntentFor(
            context: Context,
            actionId: String,
            sessionId: Long,
            setId: Long?,
        ): PendingIntent {
            val requestCode = 31 * (31 * actionId.hashCode() + sessionId.hashCode()) +
                (setId?.hashCode() ?: 0)
            val intent = Intent(context, OngoingWorkoutActionReceiver::class.java).apply {
                action = ACTION_WORKOUT_SURFACE_COMMAND
                putExtra(EXTRA_ACTION_ID, actionId)
                putExtra(EXTRA_SESSION_ID, sessionId)
                if (setId != null) putExtra(EXTRA_SET_ID, setId)
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
