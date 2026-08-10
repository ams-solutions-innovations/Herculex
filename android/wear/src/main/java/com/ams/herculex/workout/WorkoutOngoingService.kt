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
 * Foreground service that keeps the active workout alive while the app is backgrounded.
 * Registers a Wear OS Ongoing Activity surface so a dumbbell ongoing indicator chip appears
 * at the bottom (6 o'clock) of watch faces and in system recents/launcher, allowing
 * one-tap return to the active workout screen.
 */
class WorkoutOngoingService : Service() {

    companion object {
        const val EXTRA_START_EPOCH_MS = "extra_start_epoch_ms"
        const val EXTRA_WORKOUT_TITLE = "extra_workout_title"
        const val EXTRA_EXERCISE_NAME = "extra_exercise_name"
        const val EXTRA_IS_NEW_START = "extra_is_new_start"
        const val ACTION_START = "com.ams.herculex.workout.START"
        const val ACTION_UPDATE = "com.ams.herculex.workout.UPDATE"
        const val ACTION_STOP = "STOP"
        
        private const val CHANNEL_ID = "ongoing_workout_channel"
        private const val NOTIFICATION_ID = 1204
    }

    private var startEpochMs: Long = System.currentTimeMillis()
    private var workoutTitle: String = "Active Workout"
    private var exerciseName: String? = null
    private var isNewStart: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.hasExtra(EXTRA_START_EPOCH_MS) == true) {
            startEpochMs = intent.getLongExtra(EXTRA_START_EPOCH_MS, System.currentTimeMillis())
        }
        if (intent?.hasExtra(EXTRA_WORKOUT_TITLE) == true) {
            workoutTitle = intent.getStringExtra(EXTRA_WORKOUT_TITLE) ?: "Active Workout"
        }
        if (intent?.hasExtra(EXTRA_EXERCISE_NAME) == true) {
            exerciseName = intent.getStringExtra(EXTRA_EXERCISE_NAME)
        }
        isNewStart = intent?.getBooleanExtra(EXTRA_IS_NEW_START, false) == true

        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        isNewStart = false
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val touchIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("open_active_workout", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val bodyText = if (!exerciseName.isNullOrBlank()) {
            "$workoutTitle • $exerciseName"
        } else {
            "$workoutTitle in progress"
        }

        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(workoutTitle)
            .setContentText(bodyText)
            .setSmallIcon(R.drawable.ic_workout_ongoing)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setContentIntent(touchIntent)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setSilent(!isNewStart)

        // Status.StopwatchPart renders a live count-up timer from startEpochMs —
        // the system refreshes it on its own without requiring periodic polling.
        val statusText = if (!exerciseName.isNullOrBlank()) {
            "$exerciseName • #elapsed#"
        } else {
            "$workoutTitle • #elapsed#"
        }

        val status = Status.Builder()
            .addTemplate(statusText)
            .addPart("elapsed", Status.StopwatchPart(startEpochMs))
            .build()

        OngoingActivity.Builder(this, NOTIFICATION_ID, notificationBuilder)
            .setAnimatedIcon(R.drawable.ic_workout_ongoing)
            .setStaticIcon(R.drawable.ic_workout_ongoing)
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
            ).apply {
                description = "Shows live ongoing workout status on watch face and recents"
                setSound(null, null)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
