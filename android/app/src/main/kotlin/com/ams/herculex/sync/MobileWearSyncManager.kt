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

    suspend fun syncActiveWorkoutSession(sessionJson: String?, endedEntityId: String? = null) {
        stateStore.saveString(MobileWearStateStore.KEY_ACTIVE_WORKOUT_SESSION, sessionJson)
        putState(
            path = WearSyncPaths.STATE_ACTIVE_WORKOUT,
            values = mapOf(
                "session_json" to (sessionJson ?: ""),
                "has_active_session" to (sessionJson != null),
                "ended_entity_id" to (endedEntityId ?: ""),
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

    suspend fun endActiveSession(entityId: String) {
        clearPendingWorkout()
        syncActiveWorkoutSession(null, endedEntityId = entityId)
        sendMessageToAllNodes(
            path = WearSyncPaths.MESSAGE_ACTIVE_SESSION_END,
            payload = buildEndEnvelope(entityId),
        )
    }

    /**
     * Minimal, wire-compatible envelope (same shape `WearSyncContract.
     * encodeEnvelope` on the wear module produces) so the watch's existing
     * `decodeEnvelope()` needs no special-casing for this message. Hand-built
     * here because this `app` module has no `WearSyncContract`/`SyncEnvelope`
     * type of its own — that lives in the `wear` module only.
     */
    private fun buildEndEnvelope(entityId: String): String {
        val now = System.currentTimeMillis()
        return JSONObject()
            .put("schemaVersion", 2)
            .put("entity", "active_workout")
            .put("entityId", entityId)
            // Session-end is idempotent by nature (ending an already-ended
            // session is a no-op on the watch), so a plain timestamp is fine
            // here without a full persisted WearRevisionAllocator instance.
            .put("revision", now)
            .put("origin", "phone")
            .put("updatedAtEpochMs", now)
            .put("payload", JSONObject())
            .toString()
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

    /**
     * Isolated (Phase 4): each field is replayed in its own [runCatching] so
     * a `putState` failure on one (e.g. macro targets) can't prevent the
     * others from replaying — previously these four ran as one unguarded
     * sequence and `putState` rethrows on failure, so the first exception
     * silently dropped every field after it.
     */
    suspend fun replayPersistentState() {
        runCatching {
            stateStore.readString(MobileWearStateStore.KEY_ACTIVE_WORKOUT_SESSION)?.let {
                syncActiveWorkoutSession(it.ifBlank { null })
            }
        }.onFailure { Log.e(TAG, "replayPersistentState: active workout session failed", it) }

        runCatching {
            stateStore.readString(MobileWearStateStore.KEY_MACRO_TARGETS)?.let { syncMacroTargets(it) }
        }.onFailure { Log.e(TAG, "replayPersistentState: macro targets failed", it) }

        runCatching {
            stateStore.readString(MobileWearStateStore.KEY_FASTING_SNAPSHOT)?.let { syncFastingSnapshot(it) }
        }.onFailure { Log.e(TAG, "replayPersistentState: fasting snapshot failed", it) }

        runCatching {
            stateStore.readString(MobileWearStateStore.KEY_USER_TOKEN)?.let {
                syncUserToken(it.ifBlank { null })
            }
        }.onFailure { Log.e(TAG, "replayPersistentState: user token failed", it) }
    }

    /**
     * Best-effort drain (Phase 4): every queued message gets its own
     * delivery attempt, in order — a message that fails on some/all nodes no
     * longer `break`s the loop and blocks every message behind it (the
     * previous behavior, made worse by this queue being persisted in
     * SharedPreferences, so the block survived a restart). Messages that
     * exceed [MAX_DELIVERY_ATTEMPTS] or [MAX_MESSAGE_AGE_MS] are dropped
     * rather than retried forever, so a permanently-undeliverable message
     * can't grow the queue without bound.
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
        try {
            dataClient.putDataItem(request.asPutDataRequest().setUrgent()).awaitResult()
            Log.d(TAG, "putDataItem OK for $path")
        } catch (error: Exception) {
            Log.e(TAG, "putDataItem FAILED for $path", error)
            throw error
        }
    }
}

/// [enqueuedAtEpochMs]/[attempts] back the Phase 4 retry cap in
/// [MobileWearSyncManager.flushPendingRealtimeMessages] — `internal` (rather
/// than `private`) and [isExpired] being a free function lets both be unit
/// tested without mocking the Wearable `MessageClient`/`NodeClient` APIs.
internal data class PendingWearMessage(
    val id: String,
    val path: String,
    val payloadJson: String,
    val enqueuedAtEpochMs: Long,
    val attempts: Int,
)

internal fun isExpired(message: PendingWearMessage, nowEpochMs: Long, maxAttempts: Int, maxAgeMs: Long): Boolean {
    return message.attempts >= maxAttempts || (nowEpochMs - message.enqueuedAtEpochMs) > maxAgeMs
}

internal class WearMessageQueueStore(
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
                .put("payloadJson", payloadJson)
                .put("enqueuedAtEpochMs", System.currentTimeMillis())
                .put("attempts", 0),
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
