package com.ams.herculex.sync

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class WearDataLayerSyncManager(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val dataClient = Wearable.getDataClient(appContext)
    private val messageClient = Wearable.getMessageClient(appContext)
    private val nodeClient = Wearable.getNodeClient(appContext)
    private val stateStore = WearStateStore(appContext)
    private val queueStore = WearRealtimeQueueStore(appContext)

    suspend fun pushActiveWorkoutSession(sessionJson: String?) {
        stateStore.saveString(WearStateStore.KEY_ACTIVE_WORKOUT_SESSION, sessionJson)
        putState(
            // Watch -> phone durable path (distinct from STATE_ACTIVE_WORKOUT,
            // which is phone -> watch only — see WearSyncPaths).
            path = WearSyncPaths.STATE_WATCH_ACTIVE_WORKOUT,
            values = mapOf(
                "session_json" to (sessionJson ?: ""),
                "has_active_session" to (sessionJson != null),
            ),
        )
    }

    suspend fun sendRealtimeEvent(path: String, payloadJson: String = "{}"): Boolean {
        queueStore.enqueue(path = path, payloadJson = payloadJson)
        return flushPendingRealtimeMessages()
    }

    /**
     * Fire-and-forget MessageClient broadcast to all connected nodes — near
     * instant, unlike DataClient puts which the system can batch/coalesce.
     * Callers should also keep their existing DataClient put as the durable
     * fallback for delivery after a reconnect.
     */
    suspend fun sendMessageToAllNodes(path: String, payload: String) {
        val nodes = try {
            nodeClient.connectedNodes.awaitResult()
        } catch (_: Exception) {
            emptyList()
        }
        val bytes = payload.toByteArray(Charsets.UTF_8)
        for (node in nodes) {
            try {
                messageClient.sendMessage(node.id, path, bytes).awaitResult()
            } catch (_: Exception) {
                // Best-effort: DataClient state above still lets the phone
                // catch up on reconnect/onPeerConnected.
            }
        }
    }

    suspend fun replayPersistentState() {
        stateStore.readString(WearStateStore.KEY_ACTIVE_WORKOUT_SESSION)?.let {
            pushActiveWorkoutSession(it.ifBlank { null })
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
        dataClient.putDataItem(request.asPutDataRequest().setUrgent()).awaitResult()
    }
}

private data class PendingWearRealtimeMessage(
    val id: String,
    val path: String,
    val payloadJson: String,
)

private class WearRealtimeQueueStore(context: Context) {
    private val prefs = context.getSharedPreferences("wear_realtime_queue", Context.MODE_PRIVATE)

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

    fun readAll(): List<PendingWearRealtimeMessage> {
        val items = JSONArray(prefs.getString(KEY_PENDING_MESSAGES, "[]"))
        return buildList(items.length()) {
            for (index in 0 until items.length()) {
                val item = items.getJSONObject(index)
                add(
                    PendingWearRealtimeMessage(
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

private class WearStateStore(context: Context) {
    private val prefs = context.getSharedPreferences("wear_persistent_state", Context.MODE_PRIVATE)

    fun saveString(key: String, value: String?) {
        prefs.edit().putString(key, value).apply()
    }

    fun readString(key: String): String? = prefs.getString(key, null)

    companion object {
        const val KEY_ACTIVE_WORKOUT_SESSION = "active_workout_session"
    }
}

private suspend fun <T> Task<T>.awaitResult(): T {
    return suspendCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener { continuation.resumeWithException(it) }
        addOnCanceledListener { continuation.resumeWithException(IllegalStateException("Task was cancelled.")) }
    }
}
