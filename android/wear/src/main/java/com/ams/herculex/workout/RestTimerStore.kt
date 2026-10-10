package com.ams.herculex.workout

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
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
 * showOnWatch, alert, rev}` whenever it starts, extends or skips one. The
 * watch shows the countdown under the set number and, when [alert] is on,
 * buzzes once with "IT'S GO TIME" at the end.
 *
 * The phone only withdraws its own end-of-rest notification after the watch
 * has confirmed (see [RestApplyResult]) that the alert is armed. Before that
 * the phone's notification stays, so a watch that dropped the message, could
 * not schedule an exact alarm or has notifications off never leaves the
 * lifter without any alert.
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

/**
 * What [RestTimerStore.applyFromPhone] did with a payload.
 *
 * [armed] is true only when this watch will really alert on time: an exact
 * alarm is set AND notifications are allowed. That is the one thing the phone
 * needs to know before it stops alerting itself. [shouldAck] is false for
 * payloads that carry no news for the phone (duplicates, stale or unparseable
 * payloads, a cleared timer, alerts switched off).
 */
data class RestApplyResult(
    val shouldAck: Boolean,
    val armed: Boolean,
    val reason: String,
    val rev: Long,
    val endsAtEpochMs: Long,
) {
    fun toAckJson(): String = JSONObject()
        .put("endsAtEpochMs", endsAtEpochMs)
        .put("rev", rev)
        .put("armed", armed)
        .put("reason", reason)
        .toString()
}

object RestTimerStore {
    private const val TAG = "RestTimerStore"

    // Notification channels are immutable once created, so the version in the
    // id is how a changed vibration/timeout setting reaches existing installs.
    private const val CHANNEL_ID = "rest_timer_go_time_v2"
    private const val LEGACY_CHANNEL_ID = "rest_timer_go_time"
    private const val NOTIFICATION_ID = 4711
    private const val REQUEST_CODE = 4711
    private const val NOTIFICATION_TIMEOUT_MS = 30_000L

    private const val PREFS = "rest_timer_store"
    private const val KEY_LAST_REV = "last_rev"
    private const val KEY_LAST_REV_AT = "last_rev_applied_at"

    /// A lower revision only counts as stale while the newer one is recent.
    /// Rests last minutes; if hours have passed, a lower number can only come
    /// from a phone whose counter restarted, and it must not be ignored forever.
    private const val STALE_REVISION_WINDOW_MS = 10 * 60 * 1000L

    const val REASON_EXACT = "exact"
    const val REASON_INEXACT = "inexact"
    const val REASON_ALARM_FAILED = "alarm_failed"
    const val REASON_NOTIFICATIONS_DENIED = "notifications_denied"
    const val REASON_ALERT_OFF = "alert_off"
    const val REASON_CLEARED = "cleared"
    const val REASON_DUPLICATE = "duplicate"
    const val REASON_STALE = "stale"
    const val REASON_UNPARSEABLE = "unparseable"

    private val GO_TIME_PATTERN = longArrayOf(0, 140, 110, 140)

    private val _timer = MutableStateFlow<RestTimer?>(null)
    val timer: StateFlow<RestTimer?> = _timer.asStateFlow()

    /** Bumped each time a rest ends while the app is on screen. */
    private val _goTimeEvents = MutableStateFlow(0)
    val goTimeEvents: StateFlow<Int> = _goTimeEvents.asStateFlow()

    /** Set by [MainActivity] — decides overlay vs. notification at the end. */
    @Volatile
    var appInForeground: Boolean = false

    /**
     * Applies a payload from the phone, whether it came as a message or as the
     * durable DataItem copy. Idempotent: the same revision twice is a no-op,
     * and an older revision cannot undo a newer one (a skip must not be
     * resurrected by a late start). `endsAtEpochMs <= now` clears the timer.
     */
    fun applyFromPhone(
        context: Context,
        json: String,
        nowMs: Long = System.currentTimeMillis(),
    ): RestApplyResult {
        val appContext = context.applicationContext
        val obj = runCatching { JSONObject(json) }.getOrNull()
            ?: return RestApplyResult(false, false, REASON_UNPARSEABLE, 0L, 0L)
        val rev = obj.optLong("rev", 0L)
        val endsAt = obj.optLong("endsAtEpochMs", 0L)

        // `rev` is absent from older phone builds; those always apply.
        if (rev > 0L) {
            val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val lastRev = prefs.getLong(KEY_LAST_REV, 0L)
            val lastAt = prefs.getLong(KEY_LAST_REV_AT, 0L)
            if (rev == lastRev) {
                return RestApplyResult(false, false, REASON_DUPLICATE, rev, endsAt)
            }
            if (rev < lastRev && nowMs - lastAt < STALE_REVISION_WINDOW_MS) {
                Log.d(TAG, "Ignoring stale rest timer rev=$rev (have $lastRev)")
                return RestApplyResult(false, false, REASON_STALE, rev, endsAt)
            }
            prefs.edit()
                .putLong(KEY_LAST_REV, rev)
                .putLong(KEY_LAST_REV_AT, nowMs)
                .apply()
        }

        if (endsAt <= nowMs) {
            clear(appContext)
            return RestApplyResult(false, false, REASON_CLEARED, rev, endsAt)
        }

        val timer = RestTimer(
            endsAtEpochMs = endsAt,
            totalSeconds = obj.optInt("totalSeconds", 0),
            label = obj.optString("label", ""),
            showOnWatch = obj.optBoolean("showOnWatch", true),
            alert = obj.optBoolean("alert", true),
        )
        _timer.value = timer
        ensureChannel(appContext)
        val alarm = scheduleAlarm(appContext, timer)
        val notificationsOk = notificationsAllowed(appContext)
        val armed = alarm == REASON_EXACT && notificationsOk
        val reason = when {
            alarm == REASON_EXACT && !notificationsOk -> REASON_NOTIFICATIONS_DENIED
            else -> alarm
        }
        Log.d(TAG, "Rest timer rev=$rev endsAt=$endsAt armed=$armed reason=$reason")
        return RestApplyResult(
            shouldAck = alarm != REASON_ALERT_OFF,
            armed = armed,
            reason = reason,
            rev = rev,
            endsAtEpochMs = endsAt,
        )
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

    /// Returns which path was taken ([REASON_EXACT], [REASON_INEXACT],
    /// [REASON_ALARM_FAILED]) or [REASON_ALERT_OFF] when nothing is armed.
    ///
    /// Only the exact alarm counts as armed for the phone: an inexact
    /// `setAndAllowWhileIdle` may be delivered up to ~75% of the rest late,
    /// long after the phone's own on-time notification would have fired.
    private fun scheduleAlarm(context: Context, timer: RestTimer): String {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
            ?: return REASON_ALARM_FAILED
        val pending = alarmIntent(context)
        alarmManager.cancel(pending)
        if (!timer.alert) return REASON_ALERT_OFF

        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        if (canExact) {
            try {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timer.endsAtEpochMs,
                    pending,
                )
                return REASON_EXACT
            } catch (e: SecurityException) {
                // Permission revoked between the check and the call.
                Log.w(TAG, "Exact rest alarm refused, falling back to inexact", e)
            }
        }
        return try {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timer.endsAtEpochMs,
                pending,
            )
            REASON_INEXACT
        } catch (e: Exception) {
            Log.w(TAG, "Could not schedule rest alarm", e)
            REASON_ALARM_FAILED
        }
    }

    private fun cancelAlarm(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarmIntent(context))
    }

    /// The background alert is a notification, so it only counts if
    /// notifications — and this channel — are actually allowed.
    private fun notificationsAllowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (!manager.areNotificationsEnabled()) return false
        val channel = manager.getNotificationChannel(CHANNEL_ID)
        return channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    /** Called by [RestTimerAlarmReceiver] when the rest is over. */
    internal fun onRestFinished(context: Context) {
        val timer = _timer.value
        _timer.value = null
        if (timer != null && !timer.alert) return
        if (appInForeground) {
            // On screen: the overlay is the alert, plus a short buzz.
            vibrateGoTime(context)
            _goTimeEvents.value += 1
        } else {
            // Off screen the app process has no standing to vibrate by itself
            // (the system drops background vibrations that carry no usage), so
            // the buzz is carried by the notification channel instead, which
            // the system plays itself.
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
            // Tagged as an alarm so the system does not file it under "touch
            // feedback", which users commonly switch off. The AudioAttributes
            // overload is deprecated from API 33 but is the only public way to
            // attach a usage on every API level this app supports.
            @Suppress("DEPRECATION")
            vibrator?.vibrate(
                VibrationEffect.createWaveform(GO_TIME_PATTERN, -1),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        // The first version had a silent channel; drop it so the app's
        // notification settings do not list two "Rest finished" entries.
        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Rest finished",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "A short buzz when your rest between sets is over"
                enableVibration(true)
                vibrationPattern = GO_TIME_PATTERN
                setSound(null, null)
            },
        )
    }

    private fun postGoTimeNotification(context: Context, label: String?) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureChannel(context)
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
            // Long enough to still be there when the wrist is raised after a
            // set; the old 6 s meant a missed buzz left nothing to find.
            .setTimeoutAfter(NOTIFICATION_TIMEOUT_MS)
            .build()
        runCatching { manager.notify(NOTIFICATION_ID, notification) }
            .onFailure { Log.w(TAG, "Could not post go-time notification", it) }
    }
}

class RestTimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        RestTimerStore.onRestFinished(context.applicationContext)
    }
}
