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
    const val SCHEMA_VERSION = 2
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

/// Issues revisions that never go backwards, even across a process restart.
///
/// Unlike the Dart side (`WearRevisionAllocator` in wear_sync_contract.dart),
/// there was no revision-allocator construct here at all before Phase 1 —
/// callers just inlined `System.currentTimeMillis()`, which reset on every
/// restart. [key] namespaces the persisted high-water mark per entity (e.g.
/// "workout" vs. "fasting") so their sequences can't collide. See Phase 1 of
/// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md.
class WearRevisionAllocator(context: Context, key: String) {
    private val prefs = context.applicationContext
        .getSharedPreferences("wear_sync_revision", Context.MODE_PRIVATE)
    private val prefKey = "revision_$key"

    @Synchronized
    fun next(): Long {
        val persistedLast = prefs.getLong(prefKey, 0L)
        val now = System.currentTimeMillis()
        val next = if (now > persistedLast) now else persistedLast + 1
        prefs.edit().putLong(prefKey, next).apply()
        return next
    }
}

/// Split (Phase 4) from a single combined `shouldAccept` into a pure
/// [wouldAccept] check and a mutating [commit], mirroring the Dart-side
/// `WearDedupeState.wouldAccept`/`commit` split from Phase 2. The old
/// combined method wrote the high-water mark as a side effect of the check
/// itself, *before* the caller's durable write (`persistSession`/
/// `WorkoutStore.parseAndUpdateSession`/`FastingStore.saveSnapshot`) had even
/// been attempted — a failed write still poisoned the dedupe state, so a
/// retry of the identical envelope was silently dropped forever. This was
/// deferred from both Phase 1 and Phase 2 (see their progress-log entries).
class AppliedRevisionStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("wear_sync_applied_revisions", Context.MODE_PRIVATE)

    /// Pure check — does not mutate the persisted high-water mark.
    fun wouldAccept(envelope: SyncEnvelope): Boolean {
        // Fail-closed (Phase 1c): this bypass existed for pre-envelope watch
        // builds. Once both APKs move to schemaVersion 2 together there's no
        // legitimate sender left for this shape, so reject instead of
        // always-accepting it.
        if (envelope.schemaVersion == 0 && envelope.revision == 0L && envelope.updatedAtEpochMs == 0L) {
            return false
        }
        val key = "${envelope.entity}:${envelope.entityId}:${envelope.origin}"
        val previousRevision = prefs.getLong("${key}:revision", Long.MIN_VALUE)
        val previousUpdatedAt = prefs.getLong("${key}:updatedAt", Long.MIN_VALUE)
        if (envelope.revision < previousRevision) return false
        if (envelope.revision == previousRevision && envelope.updatedAtEpochMs <= previousUpdatedAt) {
            return false
        }
        return true
    }

    /// Mutation only — call after the corresponding durable write succeeds.
    fun commit(envelope: SyncEnvelope) {
        val key = "${envelope.entity}:${envelope.entityId}:${envelope.origin}"
        prefs.edit()
            .putLong("${key}:revision", envelope.revision)
            .putLong("${key}:updatedAt", envelope.updatedAtEpochMs)
            .apply()
    }
}

fun logWearSync(envelope: SyncEnvelope, path: String, delivery: String, apply: String) {
    Log.d(
        "WearSync",
        "entity=${envelope.entity} revision=${envelope.revision} origin=${envelope.origin} " +
            "entityId=${envelope.entityId} path=$path delivery=$delivery apply=$apply",
    )
}
