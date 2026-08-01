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

class PhoneWearListenerService : WearableListenerService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val CHANNEL_ID = "wear_workout_channel"
        private const val NOTIF_ID   = 99182
        private const val PREFS_NAME = "wear_workout_pending"
        private const val KEY_SESSION_JSON = "session_json"

        var onWatchWorkoutStartListener: ((String?) -> Unit)? = null
        var onWatchWorkoutUpdateListener: ((String?) -> Unit)? = null
        var onWatchWorkoutEndListener: (() -> Unit)? = null
        var onSyncRequestedListener: (() -> Unit)? = null

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
                        showWorkoutNotification(sessionJson)
                        onWatchWorkoutUpdateListener?.invoke(sessionJson)
                    } else {
                        Log.d("PhoneWearListener", "Received watch workout end (durable path)")
                        clearPendingWatchWorkout(this)
                        dismissWorkoutNotification()
                        onWatchWorkoutEndListener?.invoke()
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
                    showWorkoutNotification(sessionJson)
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
                    onWatchWorkoutEndListener?.invoke()
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
                showWorkoutNotification(sessionJson)
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
                onWatchWorkoutEndListener?.invoke()
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
            .setAutoCancel(true)
            .build()

        manager.notify(NOTIF_ID, notif)
    }

    private fun dismissWorkoutNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIF_ID)
    }
}
