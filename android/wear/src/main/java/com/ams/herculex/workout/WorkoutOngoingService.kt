package com.ams.herculex.workout

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.ams.herculex.MainActivity
import com.ams.herculex.R

/**
 * Foreground service that keeps the workout alive while the app is in the background.
 * Publishes it as a Wear OS Ongoing Activity (the same surface Spotify/media playback
 * uses) so it stays reachable from the watch face and app switcher, plus a persistent
 * "Workout in progress" notification.
 */
class WorkoutOngoingService : Service() {

    companion object {
        private const val CHANNEL_ID      = "workout_ongoing"
        private const val NOTIFICATION_ID = 1001
        const val EXTRA_START_EPOCH_MS = "start_epoch_ms"
    }

    private var startEpochMs: Long = System.currentTimeMillis()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.hasExtra(EXTRA_START_EPOCH_MS) == true) {
            startEpochMs = intent.getLongExtra(EXTRA_START_EPOCH_MS, System.currentTimeMillis())
        }

        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val touchIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Workout in progress")
            .setContentText("Your workout is running.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setContentIntent(touchIntent)
            .setOngoing(true)

        // Status.StopwatchPart renders a live count-up timer from startEpochMs —
        // the system refreshes it on its own, no polling needed.
        val status = Status.Builder()
            .addTemplate("Workout • #elapsed#")
            .addPart("elapsed", Status.StopwatchPart(startEpochMs))
            .build()

        OngoingActivity.Builder(this, NOTIFICATION_ID, notificationBuilder)
            .setStaticIcon(R.mipmap.ic_launcher)
            .setTouchIntent(touchIntent)
            .setStatus(status)
            .build()
            .apply(this)

        return notificationBuilder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ongoing Workout",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
