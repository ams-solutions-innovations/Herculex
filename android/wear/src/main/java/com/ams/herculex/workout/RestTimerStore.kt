package com.ams.herculex.workout

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ams.herculex.MainActivity
import com.ams.herculex.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/**
 * The rest period the phone is counting down, mirrored on the watch.
 *
 * The phone owns the rest timer (it knows the exercise's rest target and the
 * user's Workout settings) and sends `{endsAtEpochMs, totalSeconds, label,
 * showOnWatch, alert}` whenever it starts, extends or skips one. The watch
 * shows the countdown under the set number and, when [alert] is on, buzzes
 * once with "IT'S GO TIME" at the end — the phone then stays quiet so the
 * lifter is not notified twice.
 */
data class RestTimer(
    val endsAtEpochMs: Long,
    val totalSeconds: Int,
    val label: String,
    val showOnWatch: Boolean,
    val alert: Boolean,
) {
    fun remainingSeconds(nowMs: Long = System.currentTimeMillis()): Int =
        ((endsAtEpochMs - nowMs + 999) / 1000).toInt().coerceAtLeast(0)
}

object RestTimerStore {
    private const val TAG = "RestTimerStore"
    private const val CHANNEL_ID = "rest_timer_go_time"
    private const val NOTIFICATION_ID = 4711
    private const val REQUEST_CODE = 4711

    private val _timer = MutableStateFlow<RestTimer?>(null)
    val timer: StateFlow<RestTimer?> = _timer.asStateFlow()

    /** Bumped each time a rest ends while the app is on screen. */
    private val _goTimeEvents = MutableStateFlow(0)
    val goTimeEvents: StateFlow<Int> = _goTimeEvents.asStateFlow()

    /** Set by [MainActivity] — decides overlay vs. notification at the end. */
    @Volatile
    var appInForeground: Boolean = false

    /** Applies a payload from the phone. `endsAtEpochMs <= now` clears it. */
    fun applyFromPhone(context: Context, json: String) {
        val obj = runCatching { JSONObject(json) }.getOrNull() ?: return
        val endsAt = obj.optLong("endsAtEpochMs", 0L)
        val appContext = context.applicationContext
        if (endsAt <= System.currentTimeMillis()) {
            clear(appContext)
            return
        }
        val timer = RestTimer(
            endsAtEpochMs = endsAt,
            totalSeconds = obj.optInt("totalSeconds", 0),
            label = obj.optString("label", ""),
            showOnWatch = obj.optBoolean("showOnWatch", true),
            alert = obj.optBoolean("alert", true),
        )
        _timer.value = timer
        scheduleAlarm(appContext, timer)
    }

    fun clear(context: Context) {
        _timer.value = null
        cancelAlarm(context.applicationContext)
    }

    private fun alarmIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, RestTimerAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun scheduleAlarm(context: Context, timer: RestTimer) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarmIntent(context)
        alarmManager.cancel(pending)
        if (!timer.alert) return
        // Exact when allowed; otherwise the inexact idle-safe variant, which
        // Wear still fires within seconds while a workout keeps us foreground.
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        runCatching {
            if (canExact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timer.endsAtEpochMs,
                    pending,
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timer.endsAtEpochMs,
                    pending,
                )
            }
        }.onFailure { Log.w(TAG, "Could not schedule rest alarm", it) }
    }

    private fun cancelAlarm(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarmIntent(context))
    }

    /** Called by [RestTimerAlarmReceiver] when the rest is over. */
    internal fun onRestFinished(context: Context) {
        val timer = _timer.value
        _timer.value = null
        if (timer != null && !timer.alert) return
        vibrateGoTime(context)
        if (appInForeground) {
            _goTimeEvents.value += 1
        } else {
            postGoTimeNotification(context, timer?.label)
        }
    }

    /** Two short pulses: noticeable on the wrist, never a long buzz. */
    private fun vibrateGoTime(context: Context) {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        runCatching {
            vibrator?.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0, 140, 110, 140), -1),
            )
        }
    }

    private fun postGoTimeNotification(context: Context, label: String?) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Rest finished",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "A short buzz when your rest between sets is over"
                    // The buzz above is the alert; the channel stays quiet so
                    // the wrist is never hit twice.
                    enableVibration(false)
                    setSound(null, null)
                },
            )
        }
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("open_active_workout", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_workout_ongoing)
            .setContentTitle("IT'S GO TIME")
            .setContentText(label?.takeIf { it.isNotBlank() } ?: "Rest is over — next set")
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setTimeoutAfter(6_000)
            .build()
        runCatching { manager.notify(NOTIFICATION_ID, notification) }
    }
}

class RestTimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        RestTimerStore.onRestFinished(context.applicationContext)
    }
}
