package com.ams.herculex.sync

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class MobileWearSyncManager(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val dataClient = Wearable.getDataClient(appContext)
    private val messageClient = Wearable.getMessageClient(appContext)
    private val nodeClient = Wearable.getNodeClient(appContext)
    private val stateStore = MobileWearStateStore(appContext)
    private val queueStore = WearMessageQueueStore(appContext, "mobile_wear_queue")

    suspend fun syncActiveWorkoutSession(sessionJson: String?) {
        stateStore.saveString(MobileWearStateStore.KEY_ACTIVE_WORKOUT_SESSION, sessionJson)
        putState(
            path = WearSyncPaths.STATE_ACTIVE_WORKOUT,
            values = mapOf(
                "session_json" to (sessionJson ?: ""),
                "has_active_session" to (sessionJson != null),
            ),
        )
    }

    /**
     * Fast-path session sync: persists the latest state for reconnect replay
     * (via [syncActiveWorkoutSession]) AND fires an immediate MessageClient
     * send so a connected watch reflects the change without waiting on
     * DataClient's system-level batching.
     */
    suspend fun syncActiveSession(sessionJson: String, isStart: Boolean) {
        savePendingWorkout(sessionJson)
        syncActiveWorkoutSession(sessionJson)
        sendMessageToAllNodes(
            path = if (isStart) WearSyncPaths.MESSAGE_ACTIVE_SESSION_START else WearSyncPaths.MESSAGE_ACTIVE_SESSION_UPDATE,
            payload = sessionJson,
        )
    }

    suspend fun endActiveSession() {
        clearPendingWorkout()
        syncActiveWorkoutSession(null)
        sendMessageToAllNodes(path = WearSyncPaths.MESSAGE_ACTIVE_SESSION_END, payload = "")
    }

    private fun savePendingWorkout(sessionJson: String) {
        appContext.getSharedPreferences("wear_workout_pending", Context.MODE_PRIVATE)
            .edit()
            .putString("session_json", sessionJson)
            .apply()
    }

    private fun clearPendingWorkout() {
        appContext.getSharedPreferences("wear_workout_pending", Context.MODE_PRIVATE)
            .edit()
            .remove("session_json")
            .apply()
    }

    private suspend fun sendMessageToAllNodes(path: String, payload: String) {
        val nodes = try {
            nodeClient.connectedNodes.awaitResult()
        } catch (error: Exception) {
            Log.e(TAG, "connectedNodes lookup failed for $path", error)
            emptyList()
        }
        if (nodes.isEmpty()) {
            Log.w(TAG, "No connected nodes for $path — relying on DataClient fallback")
            return
        }
        val bytes = payload.toByteArray(Charsets.UTF_8)
        for (node in nodes) {
            try {
                messageClient.sendMessage(node.id, path, bytes).awaitResult()
                Log.d(TAG, "Sent $path to ${node.displayName} (${bytes.size}B)")
            } catch (error: Exception) {
                // Best-effort: DataClient state above still lets the watch
                // catch up on reconnect/onPeerConnected.
                Log.e(TAG, "Failed to send $path to ${node.displayName}", error)
            }
        }
    }

    suspend fun syncMacroTargets(macroTargetsJson: String) {
        stateStore.saveString(MobileWearStateStore.KEY_MACRO_TARGETS, macroTargetsJson)
        putState(
            path = WearSyncPaths.STATE_MACRO_TARGETS,
            values = mapOf("macro_targets_json" to macroTargetsJson),
        )
    }

    suspend fun syncFastingSnapshot(fastingJson: String) {
        stateStore.saveString(MobileWearStateStore.KEY_FASTING_SNAPSHOT, fastingJson)
        putState(
            path = WearSyncPaths.STATE_FASTING,
            values = mapOf("fasting_json" to fastingJson),
        )
        sendMessageToAllNodes(
            path = WearSyncPaths.MESSAGE_FASTING_SNAPSHOT,
            payload = fastingJson,
        )
    }

    suspend fun syncUserToken(userToken: String?) {
        stateStore.saveString(MobileWearStateStore.KEY_USER_TOKEN, userToken)
        putState(
            path = WearSyncPaths.STATE_USER_TOKEN,
            values = mapOf("user_token" to (userToken ?: "")),
        )
    }

    suspend fun sendRealtimeEvent(path: String, payloadJson: String = "{}"): Boolean {
        queueStore.enqueue(path = path, payloadJson = payloadJson)
        return flushPendingRealtimeMessages()
    }

    suspend fun replayPersistentState() {
        stateStore.readString(MobileWearStateStore.KEY_ACTIVE_WORKOUT_SESSION)?.let {
            syncActiveWorkoutSession(it.ifBlank { null })
        }
        stateStore.readString(MobileWearStateStore.KEY_MACRO_TARGETS)?.let { syncMacroTargets(it) }
        stateStore.readString(MobileWearStateStore.KEY_FASTING_SNAPSHOT)?.let { syncFastingSnapshot(it) }
        stateStore.readString(MobileWearStateStore.KEY_USER_TOKEN)?.let {
            syncUserToken(it.ifBlank { null })
        }
    }

    suspend fun flushPendingRealtimeMessages(): Boolean {
        val nodes = nodeClient.connectedNodes.awaitResult()
        if (nodes.isEmpty()) {
            return false
        }

        val sentIds = mutableListOf<String>()
        for (message in queueStore.readAll()) {
            var deliveredToAllNodes = true
            for (node in nodes) {
                try {
                    messageClient.sendMessage(
                        node.id,
                        message.path,
                        message.payloadJson.toByteArray(Charsets.UTF_8),
                    ).awaitResult()
                } catch (_: Exception) {
                    deliveredToAllNodes = false
                    break
                }
            }

            if (!deliveredToAllNodes) {
                break
            }

            sentIds += message.id
        }

        queueStore.removeAll(sentIds)
        return sentIds.isNotEmpty()
    }

    private companion object {
        private const val TAG = "WearSync"
    }

    private suspend fun putState(path: String, values: Map<String, Any>) {
        val request = PutDataMapRequest.create(path)
        values.forEach { (key, value) ->
            when (value) {
                is Boolean -> request.dataMap.putBoolean(key, value)
                is Int -> request.dataMap.putInt(key, value)
                is Long -> request.dataMap.putLong(key, value)
                is String -> request.dataMap.putString(key, value)
                else -> error("Unsupported data-layer payload type: ${value::class.java.simpleName}")
            }
        }
        request.dataMap.putLong("updated_at_epoch_ms", System.currentTimeMillis())
        try {
            dataClient.putDataItem(request.asPutDataRequest().setUrgent()).awaitResult()
            Log.d(TAG, "putDataItem OK for $path")
        } catch (error: Exception) {
            Log.e(TAG, "putDataItem FAILED for $path", error)
            throw error
        }
    }
}

private data class PendingWearMessage(
    val id: String,
    val path: String,
    val payloadJson: String,
)

private class WearMessageQueueStore(
    context: Context,
    private val prefsName: String,
) {
    private val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    fun enqueue(path: String, payloadJson: String) {
        val items = JSONArray(prefs.getString(KEY_PENDING_MESSAGES, "[]"))
        items.put(
            JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("path", path)
                .put("payloadJson", payloadJson),
        )
        prefs.edit().putString(KEY_PENDING_MESSAGES, items.toString()).apply()
    }

    fun readAll(): List<PendingWearMessage> {
        val items = JSONArray(prefs.getString(KEY_PENDING_MESSAGES, "[]"))
        return buildList(items.length()) {
            for (index in 0 until items.length()) {
                val item = items.getJSONObject(index)
                add(
                    PendingWearMessage(
                        id = item.getString("id"),
                        path = item.getString("path"),
                        payloadJson = item.optString("payloadJson", "{}"),
                    ),
                )
            }
        }
    }

    fun removeAll(messageIds: Collection<String>) {
        if (messageIds.isEmpty()) {
            return
        }

        val current = JSONArray(prefs.getString(KEY_PENDING_MESSAGES, "[]"))
        val retained = JSONArray()
        for (index in 0 until current.length()) {
            val item = current.getJSONObject(index)
            if (item.getString("id") !in messageIds) {
                retained.put(item)
            }
        }
        prefs.edit().putString(KEY_PENDING_MESSAGES, retained.toString()).apply()
    }

    private companion object {
        private const val KEY_PENDING_MESSAGES = "pending_messages"
    }
}

private class MobileWearStateStore(
    context: Context,
) {
    private val prefs = context.getSharedPreferences("mobile_wear_state", Context.MODE_PRIVATE)

    fun saveString(key: String, value: String?) {
        prefs.edit().putString(key, value).apply()
    }

    fun readString(key: String): String? = prefs.getString(key, null)

    companion object {
        const val KEY_ACTIVE_WORKOUT_SESSION = "active_workout_session"
        const val KEY_MACRO_TARGETS = "macro_targets"
        const val KEY_FASTING_SNAPSHOT = "fasting_snapshot"
        const val KEY_USER_TOKEN = "user_token"
    }
}

private suspend fun <T> Task<T>.awaitResult(): T {
    return suspendCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener { continuation.resumeWithException(it) }
        addOnCanceledListener { continuation.resumeWithException(IllegalStateException("Task was cancelled.")) }
    }
}
