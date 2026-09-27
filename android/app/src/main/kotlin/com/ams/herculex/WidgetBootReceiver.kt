package com.ams.herculex

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Repaints every placed home-screen widget after a reboot or an app update.
 *
 * All widget providers declare `updatePeriodMillis="0"`, so Android never sends
 * them a periodic APPWIDGET_UPDATE and does not re-dispatch one after boot.
 * Without this receiver a widget stays blank from boot until the user next
 * opens the app and a Riverpod sync controller happens to fire.
 *
 * The values themselves survive in SharedPreferences, so a broadcast is enough
 * — no data has to be recomputed here. Providers apply their own staleness
 * check (see [isWidgetDataStale]) and fall back to a placeholder if the stored
 * data is from an earlier day.
 */
class WidgetBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                broadcastWidgetUpdate(context, ALL_WIDGET_PROVIDERS)
            }
        }
    }
}
