package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Protein pill widget.
 *
 * Blue accent color matching the app's protein color.
 * Adapts dynamically to light and dark theme changes.
 */
class ProteinWidgetProvider : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_CONFIGURATION_CHANGED) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, javaClass)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            if (appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val stale = isWidgetDataStale(prefs)
        val current = if (stale) -1 else prefs.getInt(KEY_PROTEIN_CURRENT, -1)
        val target = if (stale) 0 else prefs.getInt(KEY_PROTEIN_TARGET, 0)

        for (id in appWidgetIds) {
            val views = buildViews(context, current, target)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, current: Int, target: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_protein)

        views.setTextViewText(R.id.macro_label, "PROTEIN")

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
        const val KEY_PROTEIN_CURRENT = "widget_protein_current"
        const val KEY_PROTEIN_TARGET = "widget_protein_target"
    }
}
