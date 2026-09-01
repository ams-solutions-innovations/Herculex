package com.ams.herculex.sync

import android.content.Context
import org.json.JSONObject
import java.util.UUID

data class FastingSnapshot(
    val hasActiveFast: Boolean = false,
    val startedAtEpochMs: Long? = null,
    val targetSeconds: Long = 16L * 60L * 60L,
    val phoneSessionId: String? = null,
    val endedAtEpochMs: Long? = null,
    val completed: Boolean = false,
    val revision: Long = 0L,
    val updatedAtEpochMs: Long = 0L,
    val lastFastDurationSeconds: Long? = null,
    val nextFastEpochMs: Long? = null,
    val nextFastPlanName: String? = null,
    val nextFastTargetSeconds: Long? = null,
    val hasSchedule: Boolean = false,
    val currentStageMessage: String? = null,
) {
    fun elapsedSeconds(nowEpochMs: Long = System.currentTimeMillis()): Long {
        val start = startedAtEpochMs ?: return 0L
        return ((nowEpochMs - start) / 1000L).coerceAtLeast(0L)
    }

    fun elapsedText(nowEpochMs: Long = System.currentTimeMillis()): String {
        val elapsed = elapsedSeconds(nowEpochMs)
        val hours = elapsed / 3600L
        val minutes = (elapsed % 3600L) / 60L
        return "${hours}h ${minutes}m"
    }

    fun progress(nowEpochMs: Long = System.currentTimeMillis()): Float {
        if (!hasActiveFast || targetSeconds <= 0L) return 0f
        return (elapsedSeconds(nowEpochMs).toFloat() / targetSeconds.toFloat()).coerceIn(0f, 1f)
    }

    fun nextFastFormatted(nowEpochMs: Long = System.currentTimeMillis()): String? {
        val nextMs = nextFastEpochMs ?: return null
        val calNow = java.util.Calendar.getInstance().apply { timeInMillis = nowEpochMs }
        val calNext = java.util.Calendar.getInstance().apply { timeInMillis = nextMs }

        val isToday = calNow.get(java.util.Calendar.YEAR) == calNext.get(java.util.Calendar.YEAR) &&
                calNow.get(java.util.Calendar.DAY_OF_YEAR) == calNext.get(java.util.Calendar.DAY_OF_YEAR)
        val isTomorrow = calNow.get(java.util.Calendar.YEAR) == calNext.get(java.util.Calendar.YEAR) &&
                calNow.get(java.util.Calendar.DAY_OF_YEAR) + 1 == calNext.get(java.util.Calendar.DAY_OF_YEAR)

        val timeStr = "%02d:%02d".format(calNext.get(java.util.Calendar.HOUR_OF_DAY), calNext.get(java.util.Calendar.MINUTE))
        return when {
            isToday -> "Today $timeStr"
            isTomorrow -> "Tomorrow $timeStr"
            else -> timeStr
        }
    }

    fun timeUntilNextFast(nowEpochMs: Long = System.currentTimeMillis()): String? {
        val nextMs = nextFastEpochMs ?: return null
        val diffMs = nextMs - nowEpochMs
        if (diffMs <= 0) return "now"
        val totalMins = diffMs / 60000L
        val h = totalMins / 60L
        val m = totalMins % 60L
        return if (h > 0) "${h}h ${m}m" else "${m}m"
    }
}

object FastingStore {
    private const val PREFS = "herculex_fasting"
    private const val KEY_SNAPSHOT_JSON = "snapshot_json"
    private const val KEY_PENDING_COMMANDS = "pending_commands"

    fun saveSnapshot(context: Context, json: String): FastingSnapshot {
        val envelope = WearSyncContract.decodeEnvelope(
            json = json,
            fallbackEntity = WearSyncContract.ENTITY_FASTING,
            fallbackEntityId = "fasting",
            fallbackOrigin = WearSyncContract.ORIGIN_PHONE,
        )
        val p = envelope.payload
        val snapshot = FastingSnapshot(
            hasActiveFast = p.optBoolean("hasActiveFast", false),
            startedAtEpochMs = p.optNullableLong("startedAtEpochMs"),
            targetSeconds = p.optLong("targetSeconds", 16L * 60L * 60L),
            phoneSessionId = p.optString("phoneSessionId").takeIf { it.isNotBlank() && it != "null" },
            endedAtEpochMs = p.optNullableLong("endedAtEpochMs"),
            completed = p.optBoolean("completed", false),
            revision = envelope.revision,
            updatedAtEpochMs = envelope.updatedAtEpochMs,
            lastFastDurationSeconds = p.optNullableLong("lastFastDurationSeconds"),
            nextFastEpochMs = p.optNullableLong("nextFastEpochMs"),
            nextFastPlanName = p.optString("nextFastPlanName").takeIf { it.isNotBlank() && it != "null" },
            nextFastTargetSeconds = p.optNullableLong("nextFastTargetSeconds"),
            hasSchedule = p.optBoolean("hasSchedule", false),
            currentStageMessage = p.optString("currentStageMessage").takeIf { it.isNotBlank() && it != "null" },
        )
        prefs(context).edit().putString(KEY_SNAPSHOT_JSON, json).apply()
        return snapshot
    }

    fun snapshot(context: Context): FastingSnapshot {
        val json = prefs(context).getString(KEY_SNAPSHOT_JSON, null) ?: return FastingSnapshot()
        return runCatching { saveSnapshot(context, json) }.getOrDefault(FastingSnapshot())
    }

    fun snapshotToJson(context: Context, snapshot: FastingSnapshot): String {
        val payload = JSONObject()
            .put("hasActiveFast", snapshot.hasActiveFast)
            .put("startedAtEpochMs", snapshot.startedAtEpochMs)
            .put("targetSeconds", snapshot.targetSeconds)
            .put("completed", snapshot.completed)
        return WearSyncContract.encodeEnvelope(
            entity = WearSyncContract.ENTITY_FASTING,
            entityId = "fasting",
            revision = WearRevisionAllocator(context, "fasting").next(),
            origin = WearSyncContract.ORIGIN_WATCH,
            payload = payload,
        )
    }

    fun createCommand(action: String, targetSeconds: Long = 16L * 60L * 60L): String {
        return JSONObject()
            .put("commandId", UUID.randomUUID().toString())
            .put("action", action)
            .put("targetSeconds", targetSeconds)
            .put("completed", action == "stop")
            .put("createdAtEpochMs", System.currentTimeMillis())
            .toString()
    }

    fun savePendingCommand(context: Context, commandJson: String) {
        val commands = org.json.JSONArray(prefs(context).getString(KEY_PENDING_COMMANDS, "[]"))
        commands.put(commandJson)
        prefs(context).edit().putString(KEY_PENDING_COMMANDS, commands.toString()).apply()
    }

    fun pendingCommands(context: Context): List<String> {
        val commands = org.json.JSONArray(prefs(context).getString(KEY_PENDING_COMMANDS, "[]"))
        return buildList(commands.length()) {
            for (index in 0 until commands.length()) {
                commands.optString(index).takeIf { it.isNotBlank() }?.let(::add)
            }
        }
    }

    fun clearPendingCommand(context: Context, commandId: String) {
        val current = org.json.JSONArray(prefs(context).getString(KEY_PENDING_COMMANDS, "[]"))
        val retained = org.json.JSONArray()
        for (index in 0 until current.length()) {
            val commandJson = current.optString(index)
            val id = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
            if (id != commandId) retained.put(commandJson)
        }
        prefs(context).edit().putString(KEY_PENDING_COMMANDS, retained.toString()).apply()
    }

    private fun JSONObject.optNullableLong(name: String): Long? {
        if (!has(name) || isNull(name)) return null
        return optLong(name).takeIf { it > 0L }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
