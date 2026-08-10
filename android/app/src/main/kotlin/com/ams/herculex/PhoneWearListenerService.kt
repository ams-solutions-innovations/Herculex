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

class PhoneWearListenerService : WearableListenerService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val CHANNEL_ID = "wear_workout_channel"
        private const val NOTIF_ID   = 99182
        private const val PREFS_NAME = "wear_workout_pending"
        private const val KEY_SESSION_JSON = "session_json"
        private const val KEY_FASTING_COMMANDS = "fasting_commands"
        private const val KEY_QUICKADD_COMMANDS = "quickadd_commands"

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
        var onWatchWorkoutEndListener: ((Boolean) -> Unit)? = null
        var onSyncRequestedListener: (() -> Unit)? = null
        var onWatchFastingCommandListener: ((String?) -> Unit)? = null
        var onWatchQuickAddCommandListener: ((String?) -> Unit)? = null

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
                        onWatchWorkoutEndListener?.invoke(false)
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
                    onWatchWorkoutEndListener?.invoke(false)
                }
                "/herculex_watch_session_discard" -> {
                    Log.d("PhoneWearListener", "Received watch workout discard (legacy path)")
                    clearPendingWatchWorkout(this)
                    dismissWorkoutNotification()
                    onWatchWorkoutEndListener?.invoke(true)
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
                onWatchWorkoutEndListener?.invoke(false)
            }
            "/herculex_watch_session_discard" -> {
                clearPendingWatchWorkout(this)
                dismissWorkoutNotification()
                onWatchWorkoutEndListener?.invoke(true)
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
        }
    }

    override fun onPeerConnected(peer: Node) {
        super.onPeerConnected(peer)
        serviceScope.launch {
            val syncManager = MobileWearSyncManager(applicationContext)
            syncManager.replayPersistentState()
            syncManager.flushPendingRealtimeMessages()
        }
    }

    private fun savePendingWorkout(sessionJson: String?) {
        if (sessionJson.isNullOrBlank()) return
        applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SESSION_JSON, sessionJson)
            .apply()
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
