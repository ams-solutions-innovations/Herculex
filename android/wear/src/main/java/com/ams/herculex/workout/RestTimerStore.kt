package com.ams.herculex.workout

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
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

    private const val PREFS = "rest_timer_store"
    private const val KEY_TIMER = "timer"
    private const val WAKE_LOCK_SLACK_MS = 10_000L

    // The rest ends on whichever fires first: this in-process handler (held
    // awake by a short wake lock, so it lands on the second even with the
    // wrist down) or the AlarmManager backup (survives the process dying).
    private val handler = Handler(Looper.getMainLooper())
    private var finishRunnable: Runnable? = null
    private var wakeLock: PowerManager.WakeLock? = null

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
        persist(appContext, timer)
        scheduleAlarm(appContext, timer)
        scheduleInProcess(appContext, timer)
    }

    fun clear(context: Context) {
        val appContext = context.applicationContext
        _timer.value = null
        forget(appContext)
        cancelInProcess()
        cancelAlarm(appContext)
    }

    private fun scheduleInProcess(context: Context, timer: RestTimer) {
        cancelInProcess()
        val delayMs = (timer.endsAtEpochMs - System.currentTimeMillis()).coerceAtLeast(0L)
        // Only a rest that will buzz needs the CPU awake; a silent one just
        // has to be cleared when it runs out.
        if (timer.alert) {
            runCatching {
                val power = context.getSystemService(PowerManager::class.java)
                wakeLock = power?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "herculex:rest_timer")
                    ?.apply { acquire(delayMs + WAKE_LOCK_SLACK_MS) }
            }.onFailure { Log.w(TAG, "Could not hold rest wake lock", it) }
        }
        val runnable = Runnable { onRestFinished(context) }
        finishRunnable = runnable
        handler.postDelayed(runnable, delayMs)
    }

    private fun cancelInProcess() {
        finishRunnable?.let { handler.removeCallbacks(it) }
        finishRunnable = null
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
    }

    // Kept on disk so the alarm still knows what to announce if the process
    // was reclaimed while the lifter was resting.
    private fun persist(context: Context, timer: RestTimer) {
        val json = JSONObject()
            .put("endsAtEpochMs", timer.endsAtEpochMs)
            .put("totalSeconds", timer.totalSeconds)
            .put("label", timer.label)
            .put("showOnWatch", timer.showOnWatch)
            .put("alert", timer.alert)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_TIMER, json.toString()).apply()
    }

    private fun forget(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_TIMER).apply()
    }

    private fun persisted(context: Context): RestTimer? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_TIMER, null) ?: return null
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        return RestTimer(
            endsAtEpochMs = obj.optLong("endsAtEpochMs", 0L),
            totalSeconds = obj.optInt("totalSeconds", 0),
            label = obj.optString("label", ""),
            showOnWatch = obj.optBoolean("showOnWatch", true),
            alert = obj.optBoolean("alert", true),
        )
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

    /**
     * The rest is over — called by the in-process handler or the alarm,
     * whichever is first; the second finds nothing left to announce.
     */
    internal fun onRestFinished(context: Context) {
        val appContext = context.applicationContext
        val timer = _timer.value ?: persisted(appContext) ?: return
        _timer.value = null
        forget(appContext)
        cancelInProcess()
        cancelAlarm(appContext)
        if (!timer.alert) return
        vibrateGoTime(appContext)
        // The in-app flash is only for a lifter who is looking at the app. With
        // the screen off/ambient (or the app away) it must be a real system
        // notification, otherwise the rest ends unnoticed.
        val power = appContext.getSystemService(PowerManager::class.java)
        val watching = appInForeground && power?.isInteractive != false
        if (watching) {
            _goTimeEvents.value += 1
        } else {
            postGoTimeNotification(appContext, timer.label)
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
