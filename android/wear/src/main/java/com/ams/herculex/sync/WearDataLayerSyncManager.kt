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

class WearDataLayerSyncManager(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val dataClient = Wearable.getDataClient(appContext)
    private val messageClient = Wearable.getMessageClient(appContext)
    private val nodeClient = Wearable.getNodeClient(appContext)
    private val stateStore = WearStateStore(appContext)
    private val queueStore = WearRealtimeQueueStore(appContext)

    suspend fun pushActiveWorkoutSession(sessionJson: String?, endedEntityId: String? = null) {
        stateStore.saveString(WearStateStore.KEY_ACTIVE_WORKOUT_SESSION, sessionJson)
        putState(
            // Watch -> phone durable path (distinct from STATE_ACTIVE_WORKOUT,
            // which is phone -> watch only — see WearSyncPaths).
            path = WearSyncPaths.STATE_WATCH_ACTIVE_WORKOUT,
            values = mapOf(
                "session_json" to (sessionJson ?: ""),
                "has_active_session" to (sessionJson != null),
                "ended_entity_id" to (endedEntityId ?: ""),
            ),
        )
    }

    suspend fun sendRealtimeEvent(path: String, payloadJson: String = "{}"): Boolean {
        queueStore.enqueue(path = path, payloadJson = payloadJson)
        return flushPendingRealtimeMessages()
    }

    suspend fun sendFastingCommand(commandJson: String): Boolean {
        FastingStore.savePendingCommand(appContext, commandJson)
        return sendRealtimeEvent(WearSyncPaths.MESSAGE_FASTING_COMMAND, commandJson)
    }

    suspend fun sendQuickAddCommand(commandJson: String): Boolean {
        return sendRealtimeEvent(WearSyncPaths.MESSAGE_QUICKADD_COMMAND, commandJson)
    }

    suspend fun sendMacroCommand(commandJson: String): Boolean {
        return sendRealtimeEvent(WearSyncPaths.MESSAGE_MACRO_COMMAND, commandJson)
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

    /**
     * As [sendMessageToAllNodes], but reports whether at least one node
     * accepted the message. Rep-capture sample batches need that signal to
     * decide whether to hold a batch in their in-memory ring buffer for
     * retry — they must NOT go through [sendRealtimeEvent], whose queue is
     * SharedPreferences-backed and would persist raw motion samples to disk
     * (REP-04 forbids that).
     *
     * @return true when the payload reached at least one connected node.
     */
    suspend fun sendMessageToAllNodesReporting(path: String, payload: String): Boolean {
        val nodes = try {
            nodeClient.connectedNodes.awaitResult()
        } catch (_: Exception) {
            emptyList()
        }
        val bytes = payload.toByteArray(Charsets.UTF_8)
        var delivered = false
        for (node in nodes) {
            try {
                messageClient.sendMessage(node.id, path, bytes).awaitResult()
                delivered = true
            } catch (_: Exception) {
                // Caller decides whether to hold and retry.
            }
        }
        return delivered
    }

    suspend fun replayPersistentState() {
        stateStore.readString(WearStateStore.KEY_ACTIVE_WORKOUT_SESSION)?.let {
            pushActiveWorkoutSession(it.ifBlank { null })
        }
    }

    /**
     * Best-effort drain (Phase 4): every queued message gets its own
     * delivery attempt, in order — a message that fails on some/all nodes no
     * longer `break`s the loop and blocks every message behind it (the
     * previous behavior, made worse by this queue being persisted in
     * SharedPreferences, so the block survived a restart). Messages that
     * exceed [MAX_DELIVERY_ATTEMPTS] or [MAX_MESSAGE_AGE_MS] are dropped
     * rather than retried forever, so a permanently-undeliverable message
     * can't grow the queue without bound. Mirrors
     * `MobileWearSyncManager.flushPendingRealtimeMessages` on the phone side.
     */
    suspend fun flushPendingRealtimeMessages(): Boolean {
        val nodes = nodeClient.connectedNodes.awaitResult()
        if (nodes.isEmpty()) {
            return false
        }

        val now = System.currentTimeMillis()
        val pending = queueStore.readAll()
        val expired = pending.filter { isExpired(it, now, MAX_DELIVERY_ATTEMPTS, MAX_MESSAGE_AGE_MS) }
        if (expired.isNotEmpty()) {
            Log.w(TAG, "Dropping ${expired.size} realtime message(s) past retry budget: ${expired.map { it.path }}")
            queueStore.removeAll(expired.map { it.id })
        }
        val expiredIds = expired.map { it.id }.toSet()

        val deliveredIds = mutableListOf<String>()
        val failedIds = mutableListOf<String>()
        for (message in pending) {
            if (message.id in expiredIds) continue
            var deliveredToAllNodes = true
            for (node in nodes) {
                try {
                    messageClient.sendMessage(
                        node.id,
                        message.path,
                        message.payloadJson.toByteArray(Charsets.UTF_8),
                    ).awaitResult()
                } catch (error: Exception) {
                    Log.e(TAG, "Failed to deliver queued ${message.path} to ${node.displayName}", error)
                    deliveredToAllNodes = false
                }
            }

            if (deliveredToAllNodes) {
                deliveredIds += message.id
            } else {
                failedIds += message.id
            }
        }

        queueStore.removeAll(deliveredIds)
        queueStore.recordFailedAttempts(failedIds)
        return deliveredIds.isNotEmpty()
    }

    private companion object {
        private const val TAG = "WearSync"
        private const val MAX_DELIVERY_ATTEMPTS = 20
        private const val MAX_MESSAGE_AGE_MS = 24L * 60L * 60L * 1000L
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

/// [enqueuedAtEpochMs]/[attempts] back the Phase 4 retry cap in
/// [WearDataLayerSyncManager.flushPendingRealtimeMessages] — `internal`
/// (rather than `private`) and [isExpired] being a free function lets both
/// be unit tested without mocking the Wearable `MessageClient`/`NodeClient`
/// APIs. Mirrors `PendingWearMessage`/`isExpired` in
/// `MobileWearSyncManager.kt` (separate Gradle module, so not literally
/// shared code, but kept in lockstep).
internal data class PendingWearRealtimeMessage(
    val id: String,
    val path: String,
    val payloadJson: String,
    val enqueuedAtEpochMs: Long,
    val attempts: Int,
)

internal fun isExpired(
    message: PendingWearRealtimeMessage,
    nowEpochMs: Long,
    maxAttempts: Int,
    maxAgeMs: Long,
): Boolean {
    return message.attempts >= maxAttempts || (nowEpochMs - message.enqueuedAtEpochMs) > maxAgeMs
}

internal class WearRealtimeQueueStore(context: Context) {
    private val prefs = context.getSharedPreferences("wear_realtime_queue", Context.MODE_PRIVATE)

    fun enqueue(path: String, payloadJson: String) {
        val items = JSONArray(prefs.getString(KEY_PENDING_MESSAGES, "[]"))
        items.put(
            JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("path", path)
                .put("payloadJson", payloadJson)
                .put("enqueuedAtEpochMs", System.currentTimeMillis())
                .put("attempts", 0),
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
                        enqueuedAtEpochMs = item.optLong("enqueuedAtEpochMs", 0L),
                        attempts = item.optInt("attempts", 0),
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

    /// Bumps the attempt counter for messages that were tried and failed to
    /// deliver to at least one node this pass, so [isExpired] can eventually
    /// retire a permanently-undeliverable message.
    fun recordFailedAttempts(messageIds: Collection<String>) {
        if (messageIds.isEmpty()) {
            return
        }

        val current = JSONArray(prefs.getString(KEY_PENDING_MESSAGES, "[]"))
        for (index in 0 until current.length()) {
            val item = current.getJSONObject(index)
            if (item.getString("id") in messageIds) {
                item.put("attempts", item.optInt("attempts", 0) + 1)
            }
        }
        prefs.edit().putString(KEY_PENDING_MESSAGES, current.toString()).apply()
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
