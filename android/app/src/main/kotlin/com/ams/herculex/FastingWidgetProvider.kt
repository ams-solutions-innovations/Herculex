package com.ams.herculex

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import android.widget.RemoteViews
import java.util.Date

/**
 * 2×2 Fasting widget: elapsed time of the running fast on a progress ring,
 * with its plan badge and end time. Tapping opens Fasting.
 *
 * Flutter only pushes the session's start and target (`syncFasting`), so the
 * clock is computed at draw time. While a fast runs, a non-waking alarm
 * redraws the widget every minute; it fires only while the device is awake.
 */
class FastingWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        scheduleTick(context, startedAt(context) != null)
    }

    override fun onDisabled(context: Context) {
        scheduleTick(context, false)
    }

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val started = startedAt(context)
        val target = prefs.getLong(KEY_FASTING_TARGET_SECONDS, -1L).takeIf { it > 0 }
        val data = HxFasting(
            elapsedSeconds = started?.let { ((System.currentTimeMillis() - it) / 1000).coerceAtLeast(0) },
            targetSeconds = target,
            planLabel = prefs.getString(KEY_FASTING_PLAN, null),
            endsAt = if (started != null && target != null) {
                DateFormat.getTimeFormat(context).format(Date(started + target * 1000))
            } else {
                null
            },
        )
        return renderer.fasting(w, h, data)
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 212, "/fasting"))
    }

    private fun startedAt(context: Context): Long? =
        CnsWidgetProvider.getPrefs(context).getLong(KEY_FASTING_STARTED_AT, -1L).takeIf { it > 0 }

    private fun scheduleTick(context: Context, active: Boolean) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, FastingWidgetProvider::class.java))
        val intent = Intent(context, FastingWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        val tick = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (active && ids.isNotEmpty()) {
            alarms.set(AlarmManager.RTC, System.currentTimeMillis() + TICK_MS, tick)
        } else {
            alarms.cancel(tick)
        }
    }

    companion object {
        /** Epoch millis the running fast started; absent when none is running. */
        const val KEY_FASTING_STARTED_AT = "widget_fasting_started_at"

        /** Target length in seconds; absent for a Quick Fast. */
        const val KEY_FASTING_TARGET_SECONDS = "widget_fasting_target_seconds"

        /** Plan badge, e.g. "16:8"; absent when there's nothing to show. */
        const val KEY_FASTING_PLAN = "widget_fasting_plan"

        private const val TICK_MS = 60_000L
    }
}
