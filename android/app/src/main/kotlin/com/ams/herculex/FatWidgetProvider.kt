package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Fat pill widget.
 *
 * Yellow (#FFD60A) accent color matching the app's fat color shown in the
 * Macros Consumed card screenshot.
 */
class FatWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val stale = isWidgetDataStale(prefs)
        val current = if (stale) -1 else prefs.getInt(KEY_FAT_CURRENT, -1)
        val target = if (stale) 0 else prefs.getInt(KEY_FAT_TARGET, 0)

        for (id in appWidgetIds) {
            val views = buildViews(context, current, target)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, current: Int, target: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_fat)

        views.setTextViewText(R.id.macro_label, "FAT")

        if (current < 0) {
            views.setTextViewText(R.id.macro_current, "—")
            views.setTextViewText(R.id.macro_target, "")
            views.setProgressBar(R.id.macro_progress, 100, 0, false)
        } else {
            views.setTextViewText(R.id.macro_current, "${current}g")
            views.setTextViewText(R.id.macro_target, if (target > 0) "/${target}g" else "")
            val pct = if (target > 0) ((current.toFloat() / target) * 100).toInt().coerceIn(0, 100) else 0
            views.setProgressBar(R.id.macro_progress, 100, pct, false)
        }

        views.setOnClickPendingIntent(R.id.widget_root, openNutritionIntent(context))
        return views
    }

    companion object {
        const val KEY_FAT_CURRENT = "widget_fat_current"
        const val KEY_FAT_TARGET = "widget_fat_target"
    }
}
