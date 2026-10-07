package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import java.util.Calendar

// Which widgets exist, how to repaint them, and whether the numbers they would
// paint are from today. The widgets are drawn from SharedPreferences, so a
// broadcast is all a repaint takes; nothing is recomputed on the native side.

/**
 * Epoch day (UTC-independent local day number) of the last sync from Flutter.
 *
 * The widgets that show today's numbers (calories, macros, recovery, CNS)
 * compare this against today and fall back to their placeholder when it does
 * not match, so a widget never presents yesterday's numbers as if they were
 * current. Written by MainActivity on every sync call that carries an
 * `epochDay`.
 */
const val KEY_SYNCED_EPOCH_DAY = "widget_synced_epoch_day"

/** Every widget provider registered in the manifest. */
val ALL_WIDGET_PROVIDERS: List<Class<*>> = HxWidgetProvider.ALL_PROVIDERS.toList()

/**
 * Broadcasts APPWIDGET_UPDATE for every placed instance of [providerClasses].
 *
 * Providers read SharedPreferences in onUpdate, so this is all that is needed
 * to make them repaint. Shared by MainActivity (after a Flutter sync) and
 * WidgetBootReceiver (after a reboot or app update).
 */
fun broadcastWidgetUpdate(context: Context, providerClasses: List<Class<*>>) {
    val appContext = context.applicationContext
    val manager = AppWidgetManager.getInstance(appContext)
    for (cls in providerClasses) {
        val component = ComponentName(appContext, cls)
        val ids = manager.getAppWidgetIds(component)
        if (ids.isEmpty()) continue
        appContext.sendBroadcast(
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                this.component = component
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
        )
    }
}

/**
 * True when the data in SharedPreferences was synced on a day other than today,
 * i.e. the widget would otherwise show stale numbers. Also true before the very
 * first sync, so an unsynced widget renders its placeholder rather than zeros.
 */
fun isWidgetDataStale(prefs: SharedPreferences): Boolean {
    val syncedDay = prefs.getLong(KEY_SYNCED_EPOCH_DAY, -1L)
    return syncedDay != currentEpochDay()
}

/** Local-time epoch day number, matching Dart's DateTime-based computation. */
fun currentEpochDay(): Long {
    val now = Calendar.getInstance()
    now.set(Calendar.HOUR_OF_DAY, 0)
    now.set(Calendar.MINUTE, 0)
    now.set(Calendar.SECOND, 0)
    now.set(Calendar.MILLISECOND, 0)
    val offsetMs = now.get(Calendar.ZONE_OFFSET) + now.get(Calendar.DST_OFFSET)
    return (now.timeInMillis + offsetMs) / 86_400_000L
}
