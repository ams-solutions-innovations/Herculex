package com.ams.herculex

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ams.herculex.sync.MobileWearSyncManager
import com.ams.herculex.sync.WearSyncPaths
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/// entityId/revision extracted from a pending-workout slot's raw JSON, for
/// [shouldReplacePendingWorkout]'s collision policy. `null` fields mean
/// "unknown/legacy payload, can't compare" — never "zero"/"empty".
internal data class PendingWorkoutSlot(val entityId: String?, val revision: Long?)

/// Pure collision-resolution policy for [PhoneWearListenerService]'s single
/// `KEY_SESSION_JSON` slot (Phase 4). Top-level and side-effect-free so it's
/// unit-testable without standing up the full `WearableListenerService`.
/// Callers are expected to have already established that [existing] and
/// [incoming] carry different, non-null entityIds — i.e. this is only
/// reached for an actual collision, not a normal in-place update.
internal fun shouldReplacePendingWorkout(existing: PendingWorkoutSlot, incoming: PendingWorkoutSlot): Boolean {
    val existingRevision = existing.revision
    val incomingRevision = incoming.revision
    if (existingRevision != null && incomingRevision != null) {
        return incomingRevision >= existingRevision
    }
    // Can't compare revisions (legacy/malformed payload) — fall back to the
    // pre-Phase-4 last-write-wins behavior rather than getting stuck.
    return true
}

class PhoneWearListenerService : WearableListenerService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val CHANNEL_ID = "wear_workout_channel"
        private const val NOTIF_ID   = 99182
        private const val PREFS_NAME = "wear_workout_pending"
        private const val KEY_SESSION_JSON = "session_json"
        private const val KEY_FASTING_COMMANDS = "fasting_commands"
        private const val KEY_QUICKADD_COMMANDS = "quickadd_commands"
        private const val KEY_MACRO_COMMANDS = "macro_commands"

        /// Identifies the last watch-started session we raised [NOTIF_ID] for.
        ///
        /// Deliberately separate from [KEY_SESSION_JSON]: that one is a
        /// replay-ack ("Dart hasn't stored this session yet"), which Dart
        /// clears via `markWatchWorkoutApplied` on *every* applied update.
        /// Using it as the notification guard re-armed the alert mid-session,
        /// so the next push from the watch raised a fresh high-priority
        /// "Workout Started on Watch" for a workout already showing in the
        /// ongoing surface. This key is cleared only when the session ends.
        private const val KEY_NOTIFIED_SESSION = "notified_watch_session_key"

        var onWatchWorkoutStartListener: ((String?) -> Unit)? = null
        var onWatchWorkoutUpdateListener: ((String?) -> Unit)? = null
        var onWatchWorkoutEndListener: ((Boolean, String?) -> Unit)? = null
        var onSyncRequestedListener: (() -> Unit)? = null
        var onWatchFastingCommandListener: ((String?) -> Unit)? = null
        var onWatchQuickAddCommandListener: ((String?) -> Unit)? = null
        var onWatchMacroCommandListener: ((String?) -> Unit)? = null

        /// Rep-capture traffic (`/herculex/reps/*`). One listener for all three
        /// paths — the path is passed through as the first argument and the
        /// payload verbatim as the second, so this file never parses, reorders
        /// or reinterprets a capture payload.
        ///
        /// Assigning a non-null listener drains anything held while Flutter was
        /// detached, in arrival order, before any new message is delivered
        /// (LESSONS.md:72 — a batch that arrives while Flutter is not running
        /// must be held and delivered on attach, not dropped; a dropped mid-set
        /// batch is indistinguishable at the Dart layer from a Bluetooth
        /// dropout).
        var onRepMessageListener: ((String, String) -> Unit)? = null
            set(value) {
                field = value
                if (value != null) drainHeldRepMessages(value)
            }

        /// In-memory ONLY, for the lifetime of this process (T-10-11 / REP-04).
        /// Deliberately NOT the SharedPreferences-backed stores the workout and
        /// command paths use: raw motion samples must never touch disk.
        private val heldRepMessages = ArrayDeque<Pair<String, String>>()
        private val repHoldLock = Any()

        /// ~300 s at roughly one batch per second — matches the watch's ring
        /// buffer depth, so an unbounded detach can't grow the hold forever.
        private const val MAX_HELD_REP_MESSAGES = 320

        private fun drainHeldRepMessages(listener: (String, String) -> Unit) {
            val drained = synchronized(repHoldLock) {
                if (heldRepMessages.isEmpty()) return
                val snapshot = heldRepMessages.toList()
                heldRepMessages.clear()
                snapshot
            }
            Log.d("PhoneWearListener", "Delivering ${drained.size} held rep message(s) on attach")
            // Replayed in arrival order and never coalesced, so `seq` stays
            // meaningful and a real gap still reads as a gap.
            for ((path, payload) in drained) listener(path, payload)
        }

        fun pendingWatchWorkout(context: Context): String? {
            return context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_SESSION_JSON, null)
                ?.takeIf { it.isNotBlank() }
        }

        fun clearPendingWatchWorkout(context: Context) {
            context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_SESSION_JSON)
                .apply()
        }

        /// Re-arms the "started on watch" alert. Call when a session actually
        /// ends — never when Dart merely acks having stored an update.
        fun clearNotifiedWatchSession(context: Context) {
            context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_NOTIFIED_SESSION)
                .apply()
        }

        fun pendingFastingCommands(context: Context): List<String> {
            val raw = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_FASTING_COMMANDS, "[]")
            val array = JSONArray(raw ?: "[]")
            return buildList(array.length()) {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                }
            }
        }

        fun clearPendingFastingCommand(context: Context, commandId: String) {
            if (commandId.isBlank()) return
            val prefs = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = JSONArray(prefs.getString(KEY_FASTING_COMMANDS, "[]") ?: "[]")
            val retained = JSONArray()
            for (index in 0 until current.length()) {
                val commandJson = current.optString(index)
                val id = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
                if (id != commandId) retained.put(commandJson)
            }
            prefs.edit().putString(KEY_FASTING_COMMANDS, retained.toString()).apply()
        }

        fun pendingQuickAddCommands(context: Context): List<String> {
            val raw = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_QUICKADD_COMMANDS, "[]")
            val array = JSONArray(raw ?: "[]")
            return buildList(array.length()) {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                }
            }
        }

        fun clearPendingQuickAddCommand(context: Context, commandId: String) {
            if (commandId.isBlank()) return
            val prefs = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = JSONArray(prefs.getString(KEY_QUICKADD_COMMANDS, "[]") ?: "[]")
            val retained = JSONArray()
            for (index in 0 until current.length()) {
                val commandJson = current.optString(index)
                val id = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
                if (id != commandId) retained.put(commandJson)
            }
            prefs.edit().putString(KEY_QUICKADD_COMMANDS, retained.toString()).apply()
        }

        fun pendingMacroCommands(context: Context): List<String> {
            val raw = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_MACRO_COMMANDS, "[]")
            val array = JSONArray(raw ?: "[]")
            return buildList(array.length()) {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                }
            }
        }

        fun clearPendingMacroCommand(context: Context, commandId: String) {
            if (commandId.isBlank()) return
            val prefs = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = JSONArray(prefs.getString(KEY_MACRO_COMMANDS, "[]") ?: "[]")
            val retained = JSONArray()
            for (index in 0 until current.length()) {
                val commandJson = current.optString(index)
                val id = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
                if (id != commandId) retained.put(commandJson)
            }
            prefs.edit().putString(KEY_MACRO_COMMANDS, retained.toString()).apply()
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        super.onDataChanged(dataEvents)

        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val path = event.dataItem.uri.path ?: continue
            val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap

            when (path) {
                // Durable fallback for the watch's session state: DataClient
                // guarantees eventual delivery even if the fast MessageClient
                // send (WorkoutViewModel.broadcastSessionToPhone) missed a
                // disconnected node. This is a dedicated path — never reused
                // for the phone -> watch direction — since onDataChanged also
                // fires for data items THIS device wrote, and treating a
                // self-authored write as "from the watch" would misapply it.
                WearSyncPaths.STATE_WATCH_ACTIVE_WORKOUT -> {
                    val sessionJson = dataMap.getString("session_json").orEmpty()
                    val hasActiveSession = dataMap.getBoolean("has_active_session", false)
                    if (hasActiveSession && sessionJson.isNotBlank()) {
                        Log.d("PhoneWearListener", "Received watch workout state (durable path)")
                        savePendingWorkout(sessionJson)
                        maybeNotifyWatchWorkout(sessionJson)
                        onWatchWorkoutUpdateListener?.invoke(sessionJson)
                    } else {
                        Log.d("PhoneWearListener", "Received watch workout end (durable path)")
                        clearPendingWatchWorkout(this)
                        dismissWorkoutNotification()
                        val entityId = dataMap.getString("ended_entity_id")?.takeIf { it.isNotBlank() }
                        onWatchWorkoutEndListener?.invoke(false, entityId)
                    }
                }

                // Back-compat with a watch build that predates the
                // MessageClient fast path. The current watch app no longer
                // writes these DataClient paths (it sends them as messages
                // instead), so these branches are inert once both sides are
                // updated — but without them, a stale watch APK silently
                // stops syncing to the phone entirely. The wear module is a
                // separate APK that `flutter run` does NOT install, so the
                // two sides drifting apart is easy to hit.
                "/herculex_watch_workout_started" -> {
                    val sessionJson = dataMap.getString("session_json")
                    Log.d("PhoneWearListener", "Received watch workout start (legacy path)")
                    savePendingWorkout(sessionJson)
                    maybeNotifyWatchWorkout(sessionJson)
                    onWatchWorkoutStartListener?.invoke(sessionJson)
                }
                "/herculex_watch_session_update" -> {
                    val sessionJson = dataMap.getString("session_json")
                    Log.d("PhoneWearListener", "Received watch workout update (legacy path)")
                    savePendingWorkout(sessionJson)
                    onWatchWorkoutUpdateListener?.invoke(sessionJson)
                }
                "/herculex_watch_session_end" -> {
                    Log.d("PhoneWearListener", "Received watch workout end (legacy path)")
                    clearPendingWatchWorkout(this)
                    dismissWorkoutNotification()
                    // Legacy DataClient path predates the entityId envelope
                    // entirely — no identity to extract, same as before Phase 1.
                    onWatchWorkoutEndListener?.invoke(false, null)
                }
                "/herculex_watch_session_discard" -> {
                    Log.d("PhoneWearListener", "Received watch workout discard (legacy path)")
                    clearPendingWatchWorkout(this)
                    dismissWorkoutNotification()
                    onWatchWorkoutEndListener?.invoke(true, null)
                }
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        when (messageEvent.path) {
            "/herculex_watch_workout_started" -> {
                val sessionJson = String(messageEvent.data)
                savePendingWorkout(sessionJson)
                maybeNotifyWatchWorkout(sessionJson)
                onWatchWorkoutStartListener?.invoke(sessionJson)
            }
            "/herculex_watch_session_update" -> {
                val sessionJson = String(messageEvent.data)
                Log.d("PhoneWearListener", "Received watch workout update (fast path)")
                savePendingWorkout(sessionJson)
                onWatchWorkoutUpdateListener?.invoke(sessionJson)
            }
            "/herculex_watch_session_end" -> {
                clearPendingWatchWorkout(this)
                dismissWorkoutNotification()
                onWatchWorkoutEndListener?.invoke(false, extractEntityId(String(messageEvent.data)))
            }
            "/herculex_watch_session_discard" -> {
                clearPendingWatchWorkout(this)
                dismissWorkoutNotification()
                onWatchWorkoutEndListener?.invoke(true, extractEntityId(String(messageEvent.data)))
            }
            "/request_sync" -> {
                Log.d("PhoneWearListener", "Received /request_sync message from watch")
                onSyncRequestedListener?.invoke()
            }
            WearSyncPaths.MESSAGE_START_REST_TIMER,
            WearSyncPaths.MESSAGE_UPDATE_WEIGHT,
            WearSyncPaths.MESSAGE_FINISH_WORKOUT -> {
                Log.d("PhoneWearListener", "Received realtime event ${messageEvent.path}")
            }
            WearSyncPaths.MESSAGE_FASTING_COMMAND -> {
                val commandJson = String(messageEvent.data)
                Log.d("PhoneWearListener", "Received fasting command")
                savePendingFastingCommand(commandJson)
                onWatchFastingCommandListener?.invoke(commandJson)
            }
            WearSyncPaths.MESSAGE_QUICKADD_COMMAND -> {
                val commandJson = String(messageEvent.data)
                Log.d("PhoneWearListener", "Received quick-add command")
                savePendingQuickAddCommand(commandJson)
                onWatchQuickAddCommandListener?.invoke(commandJson)
            }
            WearSyncPaths.MESSAGE_MACRO_COMMAND -> {
                val commandJson = String(messageEvent.data)
                Log.d("PhoneWearListener", "Received macro command")
                savePendingMacroCommand(commandJson)
                onWatchMacroCommandListener?.invoke(commandJson)
            }

            // Rep capture. Forwarded verbatim — this file computes, adjusts
            // and substitutes nothing, and in particular never touches the
            // capture-end payload's `provisionalCount`, which is
            // non-authoritative by contract (T-10-09).
            WearSyncPaths.MESSAGE_REP_CAPTURE_START,
            WearSyncPaths.MESSAGE_REP_SAMPLES,
            WearSyncPaths.MESSAGE_REP_CAPTURE_END -> {
                deliverOrHoldRepMessage(messageEvent.path, String(messageEvent.data))
            }
        }
    }

    /// Delivers to Dart when attached, otherwise holds in memory for delivery
    /// on attach. The check and the enqueue share a lock so a listener
    /// attaching concurrently cannot cause a batch to be both held and
    /// delivered, or neither.
    private fun deliverOrHoldRepMessage(path: String, payload: String) {
        val listener = synchronized(repHoldLock) {
            val current = onRepMessageListener
            if (current == null) {
                heldRepMessages.addLast(path to payload)
                while (heldRepMessages.size > MAX_HELD_REP_MESSAGES) {
                    heldRepMessages.removeFirst()
                }
                Log.d("PhoneWearListener", "Flutter detached — holding $path (${heldRepMessages.size} held)")
            }
            current
        }
        listener?.invoke(path, payload)
    }

    override fun onPeerConnected(peer: Node) {
        super.onPeerConnected(peer)
        serviceScope.launch {
            val syncManager = MobileWearSyncManager(applicationContext)
            // Isolated (Phase 4): a failure in one must not prevent the other
            // from running — previously a durable-put exception in replay
            // skipped the flush entirely.
            runCatching { syncManager.replayPersistentState() }
                .onFailure { Log.e("PhoneWearListener", "replayPersistentState failed", it) }
            runCatching { syncManager.flushPendingRealtimeMessages() }
                .onFailure { Log.e("PhoneWearListener", "flushPendingRealtimeMessages failed", it) }
        }
    }

    /// Collision-safe (Phase 4): [KEY_SESSION_JSON] is a single slot that
    /// previously overwrote blindly. It only holds an *unconfirmed* payload —
    /// Dart clears it via `markWatchWorkoutApplied` once the payload is
    /// durably applied — so if it's still populated with a *different*
    /// entityId than the incoming one, that's a genuine collision (two
    /// distinct sessions raced for the one slot before either was
    /// confirmed), not just a normal in-place update. Resolve it by keeping
    /// whichever envelope carries the higher (now trustworthy, per Phase 1)
    /// revision, logging loudly either way instead of silently letting the
    /// last write win.
    private fun savePendingWorkout(sessionJson: String?) {
        if (sessionJson.isNullOrBlank()) return
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existingJson = prefs.getString(KEY_SESSION_JSON, null)?.takeIf { it.isNotBlank() }
        val existing = existingJson?.let { PendingWorkoutSlot(extractEntityId(it), extractRevision(it)) }
        val incoming = PendingWorkoutSlot(extractEntityId(sessionJson), extractRevision(sessionJson))
        val isCollision = existing != null && existing.entityId != null && incoming.entityId != null &&
            existing.entityId != incoming.entityId

        if (isCollision) {
            Log.w(
                "PhoneWearListener",
                "Pending workout collision: unconfirmed session ${existing!!.entityId} " +
                    "(rev ${existing.revision}) vs incoming ${incoming.entityId} (rev ${incoming.revision})",
            )
        }

        if (!isCollision || shouldReplacePendingWorkout(existing!!, incoming)) {
            prefs.edit().putString(KEY_SESSION_JSON, sessionJson).apply()
        } else {
            Log.w(
                "PhoneWearListener",
                "Keeping existing pending workout ${existing!!.entityId} (rev ${existing.revision}) " +
                    "over lower-revision incoming ${incoming.entityId} (rev ${incoming.revision})",
            )
        }
    }

    private fun savePendingFastingCommand(commandJson: String?) {
        if (commandJson.isNullOrBlank()) return
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val items = JSONArray(prefs.getString(KEY_FASTING_COMMANDS, "[]") ?: "[]")
        val commandId = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
        if (!commandId.isNullOrBlank()) {
            for (index in 0 until items.length()) {
                val existing = runCatching { JSONObject(items.optString(index)).optString("commandId") }.getOrNull()
                if (existing == commandId) return
            }
        }
        items.put(commandJson)
        prefs.edit().putString(KEY_FASTING_COMMANDS, items.toString()).apply()
    }

    private fun savePendingQuickAddCommand(commandJson: String?) {
        if (commandJson.isNullOrBlank()) return
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val items = JSONArray(prefs.getString(KEY_QUICKADD_COMMANDS, "[]") ?: "[]")
        val commandId = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
        if (!commandId.isNullOrBlank()) {
            for (index in 0 until items.length()) {
                val existing = runCatching { JSONObject(items.optString(index)).optString("commandId") }.getOrNull()
                if (existing == commandId) return
            }
        }
        items.put(commandJson)
        prefs.edit().putString(KEY_QUICKADD_COMMANDS, items.toString()).apply()
    }

    private fun savePendingMacroCommand(commandJson: String?) {
        if (commandJson.isNullOrBlank()) return
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val items = JSONArray(prefs.getString(KEY_MACRO_COMMANDS, "[]") ?: "[]")
        val commandId = runCatching { JSONObject(commandJson).optString("commandId") }.getOrNull()
        if (!commandId.isNullOrBlank()) {
            for (index in 0 until items.length()) {
                val existing = runCatching { JSONObject(items.optString(index)).optString("commandId") }.getOrNull()
                if (existing == commandId) return
            }
        }
        items.put(commandJson)
        prefs.edit().putString(KEY_MACRO_COMMANDS, items.toString()).apply()
    }

    /// Raises the "started on watch" alert at most once per watch-started
    /// session.
    ///
    /// Both the fast (MessageClient) and durable (DataClient) paths funnel
    /// through here, so a watch that sends the same start over both — which it
    /// does — only alerts once. Sessions the watch merely adopted from the
    /// phone carry `origin = "phone"` and are skipped: the phone already shows
    /// them in its ongoing workout surface.
    private fun maybeNotifyWatchWorkout(sessionJson: String?) {
        if (!isWatchOrigin(sessionJson)) return
        val sessionKey = watchSessionKey(sessionJson) ?: return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_NOTIFIED_SESSION, null) == sessionKey) return
        prefs.edit().putString(KEY_NOTIFIED_SESSION, sessionKey).apply()
        showWorkoutNotification(sessionJson)
    }

    /// Stable per-session identity, so repeated pushes for the same workout
    /// collapse. Prefers the envelope's `entityId`; falls back to the payload's
    /// start timestamp for legacy envelope-less payloads from an older watch.
    private fun watchSessionKey(sessionJson: String?): String? {
        if (sessionJson.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(sessionJson)
            obj.optString("entityId").takeIf { it.isNotBlank() }
                ?: obj.optJSONObject("payload")?.optLong("startedAtEpochMs")?.takeIf { it > 0L }?.toString()
                ?: obj.optLong("startedAtEpochMs").takeIf { it > 0L }?.toString()
        } catch (_: Exception) {
            null
        }
    }

    /// Just the wire `entityId`, no fallback — used to gate an end/discard
    /// event, where a fallback to a timestamp key (as [watchSessionKey] does
    /// for notification dedup) would be the wrong semantics.
    private fun extractEntityId(json: String?): String? {
        if (json.isNullOrBlank()) return null
        return try {
            JSONObject(json).optString("entityId").takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    /// Wire `revision`, used only to break a [savePendingWorkout] collision
    /// between two different unconfirmed sessions — `null` (missing/legacy
    /// payload) means "can't compare", not "zero".
    private fun extractRevision(json: String?): Long? {
        if (json.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(json)
            if (obj.has("revision")) obj.optLong("revision") else null
        } catch (_: Exception) {
            null
        }
    }

    private fun showWorkoutNotification(sessionJson: String?) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Watch Workout Sync",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for workouts started on Herculex Watch"
            }
            manager.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_active_workout", true)
            putExtra("session_json", sessionJson)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Workout Started on Watch ⌚")
            .setContentText("Tap to open and view workout on phone")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .build()

        manager.notify(NOTIF_ID, notif)
    }

    private fun dismissWorkoutNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIF_ID)
        // The session is over — re-arm so the next watch-started workout alerts.
        clearNotifiedWatchSession(this)
    }

    private fun isWatchOrigin(sessionJson: String?): Boolean {
        if (sessionJson.isNullOrBlank()) return false
        return try {
            val obj = JSONObject(sessionJson)
            val origin = obj.optString("origin")
            origin == "watch"
        } catch (_: Exception) {
            false
        }
    }
}
