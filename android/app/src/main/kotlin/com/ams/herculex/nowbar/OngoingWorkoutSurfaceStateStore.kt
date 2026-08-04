package com.ams.herculex.nowbar

import android.content.Context
import org.json.JSONObject

class OngoingWorkoutSurfaceStateStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE,
    )

    fun recordQueuedAction(actionId: String, feedbackPosted: Boolean) {
        prefs.edit()
            .putInt(KEY_PENDING_NATIVE_ACTION_COUNT, pendingNativeActionCount() + 1)
            .putString(KEY_LAST_NATIVE_ACTION_ID, actionId)
            .putLong(KEY_LAST_NATIVE_ACTION_AT_MILLIS, System.currentTimeMillis())
            .putBoolean(KEY_LAST_NATIVE_FEEDBACK_POSTED, feedbackPosted)
            .apply()
    }

    fun recordSurface(snapshot: OngoingWorkoutSurfaceSnapshot) {
        val actionLabels = JSONObject()
        snapshot.expanded.actions.forEach { action ->
            actionLabels.put(action.id, action.label)
        }
        val requiresUnlock = snapshot.expanded.actions
            .map { action -> action.id }
            .filter { actionId -> snapshot.requiresUnlock(actionId) }
            .toSet() + snapshot.privacy.requiresUnlock
        prefs.edit()
            .putStringSet(KEY_REQUIRES_UNLOCK_ACTION_IDS, requiresUnlock)
            .putLong(KEY_SESSION_ID, snapshot.sessionId)
            .apply {
                if (snapshot.targetSetId != null) {
                    putLong(KEY_TARGET_SET_ID, snapshot.targetSetId)
                } else {
                    remove(KEY_TARGET_SET_ID)
                }
            }
            .putLong(KEY_STARTED_AT_MILLIS, snapshot.startedAtEpochMillis)
            .putString(KEY_TITLE, snapshot.collapsed.title)
            .putString(KEY_COMPACT_CONTENT, compactContent(snapshot))
            .putString(KEY_COLLAPSED_VALUE, snapshot.collapsed.value)
            .putString(KEY_EXPANDED_CONTENT, expandedContent(snapshot))
            .putString(KEY_ACTION_LABELS_JSON, actionLabels.toString())
            .apply()
    }

    fun clearQueuedActions() {
        prefs.edit()
            .putInt(KEY_PENDING_NATIVE_ACTION_COUNT, 0)
            .remove(KEY_LAST_NATIVE_ACTION_ID)
            .remove(KEY_LAST_NATIVE_ACTION_AT_MILLIS)
            .remove(KEY_LAST_NATIVE_FEEDBACK_POSTED)
            .apply()
    }

    fun recordDroppedActions(count: Int) {
        if (count <= 0) return
        prefs.edit()
            .putInt(KEY_DROPPED_NATIVE_ACTION_COUNT, droppedNativeActionCount() + count)
            .apply()
    }

    fun recordRejectedAction(actionId: String, reason: String) {
        prefs.edit()
            .putInt(KEY_REJECTED_NATIVE_ACTION_COUNT, rejectedNativeActionCount() + 1)
            .putString(KEY_LAST_REJECTED_NATIVE_ACTION_ID, actionId)
            .putString(KEY_LAST_REJECTED_NATIVE_ACTION_REASON, reason)
            .putLong(KEY_LAST_REJECTED_NATIVE_ACTION_AT_MILLIS, System.currentTimeMillis())
            .apply()
    }

    fun clearSurface() {
        prefs.edit()
            .remove(KEY_PENDING_NATIVE_ACTION_COUNT)
            .remove(KEY_DROPPED_NATIVE_ACTION_COUNT)
            .remove(KEY_REJECTED_NATIVE_ACTION_COUNT)
            .remove(KEY_LAST_NATIVE_ACTION_ID)
            .remove(KEY_LAST_NATIVE_ACTION_AT_MILLIS)
            .remove(KEY_LAST_NATIVE_FEEDBACK_POSTED)
            .remove(KEY_LAST_REJECTED_NATIVE_ACTION_ID)
            .remove(KEY_LAST_REJECTED_NATIVE_ACTION_REASON)
            .remove(KEY_LAST_REJECTED_NATIVE_ACTION_AT_MILLIS)
            .remove(KEY_SESSION_ID)
            .remove(KEY_TARGET_SET_ID)
            .remove(KEY_STARTED_AT_MILLIS)
            .remove(KEY_TITLE)
            .remove(KEY_COMPACT_CONTENT)
            .remove(KEY_COLLAPSED_VALUE)
            .remove(KEY_EXPANDED_CONTENT)
            .remove(KEY_ACTION_LABELS_JSON)
            .remove(KEY_REQUIRES_UNLOCK_ACTION_IDS)
            .apply()
    }

    fun pendingNativeActionCount(): Int {
        return prefs.getInt(KEY_PENDING_NATIVE_ACTION_COUNT, 0)
    }

    fun droppedNativeActionCount(): Int {
        return prefs.getInt(KEY_DROPPED_NATIVE_ACTION_COUNT, 0)
    }

    fun rejectedNativeActionCount(): Int {
        return prefs.getInt(KEY_REJECTED_NATIVE_ACTION_COUNT, 0)
    }

    fun diagnostics(): Map<String, Any?> {
        val lastActionAt = prefs.getLong(KEY_LAST_NATIVE_ACTION_AT_MILLIS, 0L)
        val lastRejectedAt = prefs.getLong(KEY_LAST_REJECTED_NATIVE_ACTION_AT_MILLIS, 0L)
        return mapOf(
            "pendingNativeActionCount" to pendingNativeActionCount(),
            "droppedNativeActionCount" to droppedNativeActionCount(),
            "rejectedNativeActionCount" to rejectedNativeActionCount(),
            "lastNativeActionId" to prefs.getString(KEY_LAST_NATIVE_ACTION_ID, null),
            "lastNativeActionAtMillis" to if (lastActionAt > 0L) lastActionAt else null,
            "lastNativeFeedbackPosted" to if (lastActionAt > 0L) {
                prefs.getBoolean(KEY_LAST_NATIVE_FEEDBACK_POSTED, false)
            } else {
                null
            },
            "lastRejectedNativeActionId" to prefs.getString(
                KEY_LAST_REJECTED_NATIVE_ACTION_ID,
                null,
            ),
            "lastRejectedNativeActionReason" to prefs.getString(
                KEY_LAST_REJECTED_NATIVE_ACTION_REASON,
                null,
            ),
            "lastRejectedNativeActionAtMillis" to if (lastRejectedAt > 0L) {
                lastRejectedAt
            } else {
                null
            },
        )
    }

    fun displayState(): OngoingWorkoutSurfaceDisplayState? {
        val sessionId = prefs.getLong(KEY_SESSION_ID, 0L)
        val title = prefs.getString(KEY_TITLE, null)
        if (sessionId <= 0L || title.isNullOrBlank()) return null
        return OngoingWorkoutSurfaceDisplayState(
            sessionId = sessionId,
            targetSetId = prefs.getLong(KEY_TARGET_SET_ID, 0L).takeIf { value -> value > 0L },
            startedAtMillis = prefs.getLong(KEY_STARTED_AT_MILLIS, System.currentTimeMillis()),
            title = title,
            compactContent = prefs.getString(KEY_COMPACT_CONTENT, "") ?: "",
            collapsedValue = prefs.getString(KEY_COLLAPSED_VALUE, "") ?: "",
            expandedContent = prefs.getString(KEY_EXPANDED_CONTENT, "") ?: "",
            actionLabels = readActionLabels(),
            requiresUnlockActionIds = prefs.getStringSet(
                KEY_REQUIRES_UNLOCK_ACTION_IDS,
                emptySet(),
            ) ?: emptySet(),
        )
    }

    private fun readActionLabels(): Map<String, String> {
        val json = prefs.getString(KEY_ACTION_LABELS_JSON, "{}") ?: "{}"
        val labels = JSONObject(json)
        return labels.keys().asSequence().associateWith { key -> labels.getString(key) }
    }

    private fun compactContent(snapshot: OngoingWorkoutSurfaceSnapshot): String {
        return listOf(
            snapshot.collapsed.subtitle,
            snapshot.collapsed.value,
            snapshot.collapsed.elapsedLabel,
        ).filter { value -> value.isNotBlank() }.joinToString(" - ")
    }

    private fun expandedContent(snapshot: OngoingWorkoutSurfaceSnapshot): String {
        val status = compactContent(snapshot)
        val rows = snapshot.expanded.rows.joinToString("\n") { row ->
            "${row.label}: ${row.value}"
        }
        return listOf(status, rows)
            .filter { value -> value.isNotBlank() }
            .joinToString("\n")
    }

    companion object {
        private const val PREFS_NAME = "herculex_nowbar_surface_state"
        private const val KEY_PENDING_NATIVE_ACTION_COUNT = "pending_native_action_count"
        private const val KEY_DROPPED_NATIVE_ACTION_COUNT = "dropped_native_action_count"
        private const val KEY_REJECTED_NATIVE_ACTION_COUNT = "rejected_native_action_count"
        private const val KEY_LAST_NATIVE_ACTION_ID = "last_native_action_id"
        private const val KEY_LAST_NATIVE_ACTION_AT_MILLIS = "last_native_action_at_millis"
        private const val KEY_LAST_NATIVE_FEEDBACK_POSTED = "last_native_feedback_posted"
        private const val KEY_LAST_REJECTED_NATIVE_ACTION_ID = "last_rejected_native_action_id"
        private const val KEY_LAST_REJECTED_NATIVE_ACTION_REASON =
            "last_rejected_native_action_reason"
        private const val KEY_LAST_REJECTED_NATIVE_ACTION_AT_MILLIS =
            "last_rejected_native_action_at_millis"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_TARGET_SET_ID = "target_set_id"
        private const val KEY_STARTED_AT_MILLIS = "started_at_millis"
        private const val KEY_TITLE = "title"
        private const val KEY_COMPACT_CONTENT = "compact_content"
        private const val KEY_COLLAPSED_VALUE = "collapsed_value"
        private const val KEY_EXPANDED_CONTENT = "expanded_content"
        private const val KEY_ACTION_LABELS_JSON = "action_labels_json"
        private const val KEY_REQUIRES_UNLOCK_ACTION_IDS = "requires_unlock_action_ids"
    }
}

data class OngoingWorkoutSurfaceDisplayState(
    val sessionId: Long,
    val targetSetId: Long?,
    val startedAtMillis: Long,
    val title: String,
    val compactContent: String,
    val collapsedValue: String,
    val expandedContent: String,
    val actionLabels: Map<String, String>,
    /** Action ids the snapshot flagged as executable only on an unlocked device. */
    val requiresUnlockActionIds: Set<String> = emptySet(),
)
