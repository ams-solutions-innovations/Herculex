package com.ams.herculex.complication

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.sync.SyncService
import java.util.Calendar

object MidnightAlarmScheduler {
    private const val TAG = "MidnightAlarmScheduler"
    const val ACTION_MIDNIGHT_ROLLOVER = "com.ams.herculex.action.MIDNIGHT_ROLLOVER"
    private const val REQUEST_CODE_MIDNIGHT = 1005

    fun scheduleMidnightAlarm(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, DayChangeReceiver::class.java).apply {
            action = ACTION_MIDNIGHT_ROLLOVER
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE_MIDNIGHT,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val cal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 2)
            set(Calendar.MILLISECOND, 0)
        }
        val triggerAtMillis = cal.timeInMillis

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent,
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent,
                )
            }
            Log.d(TAG, "Scheduled next midnight rollover alarm for ${cal.time}")
        } catch (e: SecurityException) {
            // If exact alarm permission is missing on Android 12+, fall back to setAndAllowWhileIdle
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent,
                )
            }
            Log.w(TAG, "Scheduled inexact midnight rollover alarm due to SecurityException")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule midnight alarm", e)
        }
    }
}

/// Redraws complications and tiles when the calendar day changes.
///
/// `MacroStore` zeroes yesterday's totals on read once the day key moves on,
/// but complications and tiles also need to be explicitly told to redraw.
/// Triggered at midnight via [MidnightAlarmScheduler], or on system events
/// (time set, timezone change, device boot).
class DayChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("DayChangeReceiver", "Day rollover triggered via action=${intent.action}")

        // 1. Force day rollover in MacroStore
        MacroStore.rolloverIfNeeded(context)

        // 2. Refresh active UI if in foreground
        SyncService.activeNutritionViewModel?.refresh()

        // 3. Redraw complications & tiles (showing 0/empty for new day)
        WearComplicationHelper.requestAllComplicationsUpdate(context)

        // 4. Request latest targets/data from phone for the new day
        SyncService.requestSyncFromPhone(context)

        // 5. Schedule next midnight rollover alarm
        MidnightAlarmScheduler.scheduleMidnightAlarm(context)
    }
}
