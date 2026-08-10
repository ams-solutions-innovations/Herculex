package com.ams.herculex.sync

import android.content.Context
import android.util.Log
import org.json.JSONObject

data class SyncEnvelope(
    val schemaVersion: Int,
    val entity: String,
    val entityId: String,
    val revision: Long,
    val origin: String,
    val updatedAtEpochMs: Long,
    val payload: JSONObject,
)

object WearSyncContract {
    const val SCHEMA_VERSION = 1
    const val ENTITY_ACTIVE_WORKOUT = "active_workout"
    const val ENTITY_FASTING = "fasting"
    const val ORIGIN_PHONE = "phone"
    const val ORIGIN_WATCH = "watch"

    fun decodeEnvelope(
        json: String,
        fallbackEntity: String,
        fallbackEntityId: String,
        fallbackOrigin: String,
    ): SyncEnvelope {
        val obj = JSONObject(json)
        val payload = obj.optJSONObject("payload")
        return if (payload != null && obj.has("schemaVersion") && obj.has("entity")) {
            SyncEnvelope(
                schemaVersion = obj.optInt("schemaVersion", SCHEMA_VERSION),
                entity = obj.optString("entity", fallbackEntity),
                entityId = obj.optString("entityId", fallbackEntityId),
                revision = obj.optLong("revision", 0L),
                origin = obj.optString("origin", fallbackOrigin),
                updatedAtEpochMs = obj.optLong("updatedAtEpochMs", 0L),
                payload = payload,
            )
        } else {
            SyncEnvelope(
                schemaVersion = 0,
                entity = fallbackEntity,
                entityId = fallbackEntityId,
                revision = obj.optLong("revision", 0L),
                origin = fallbackOrigin,
                updatedAtEpochMs = obj.optLong("updatedAtEpochMs", obj.optLong("startedAtEpochMs", 0L)),
                payload = obj,
            )
        }
    }

    fun encodeEnvelope(
        entity: String,
        entityId: String,
        revision: Long,
        origin: String,
        payload: JSONObject,
    ): String {
        return JSONObject()
            .put("schemaVersion", SCHEMA_VERSION)
            .put("entity", entity)
            .put("entityId", entityId)
            .put("revision", revision)
            .put("origin", origin)
            .put("updatedAtEpochMs", System.currentTimeMillis())
            .put("payload", payload)
            .toString()
    }

    fun normalizeSetType(raw: String?): String {
        return when (raw?.trim()?.lowercase().orEmpty()) {
            "", "normal", "work", "working" -> "standard"
            "warmup", "warm_up" -> "standard"
            "failure" -> "forced"
            else -> raw!!.trim().lowercase()
        }
    }

    fun normalizeIsWarmup(setType: String?, isWarmup: Boolean): Boolean {
        val raw = setType?.trim()?.lowercase().orEmpty()
        return isWarmup || raw == "warmup" || raw == "warm_up"
    }
}

class AppliedRevisionStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("wear_sync_applied_revisions", Context.MODE_PRIVATE)

    fun shouldAccept(envelope: SyncEnvelope): Boolean {
        if (envelope.schemaVersion == 0 && envelope.revision == 0L && envelope.updatedAtEpochMs == 0L) {
            return true
        }
        val key = "${envelope.entity}:${envelope.entityId}:${envelope.origin}"
        val previousRevision = prefs.getLong("${key}:revision", Long.MIN_VALUE)
        val previousUpdatedAt = prefs.getLong("${key}:updatedAt", Long.MIN_VALUE)
        if (envelope.revision < previousRevision) return false
        if (envelope.revision == previousRevision && envelope.updatedAtEpochMs <= previousUpdatedAt) {
            return false
        }
        prefs.edit()
            .putLong("${key}:revision", envelope.revision)
            .putLong("${key}:updatedAt", envelope.updatedAtEpochMs)
            .apply()
        return true
    }
}

fun logWearSync(envelope: SyncEnvelope, path: String, delivery: String, apply: String) {
    Log.d(
        "WearSync",
        "entity=${envelope.entity} revision=${envelope.revision} origin=${envelope.origin} " +
            "entityId=${envelope.entityId} path=$path delivery=$delivery apply=$apply",
    )
}
