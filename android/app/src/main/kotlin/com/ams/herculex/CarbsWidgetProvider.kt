package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Net Carbs pill widget.
 *
 * Teal (#64D2FF) accent color matching the app's carb color in the
 * Macros Consumed card (teal / cyan seen in the screenshot).
 */
class CarbsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val current = prefs.getInt(KEY_CARBS_CURRENT, -1)
        val target = prefs.getInt(KEY_CARBS_TARGET, 0)

        for (id in appWidgetIds) {
            val views = buildViews(context, current, target)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, current: Int, target: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_macro)
        val accentColor = Color.parseColor("#64D2FF") // Teal — matches app's carb ring

        views.setTextViewText(R.id.macro_label, "NET CARBS")
        views.setInt(R.id.macro_dot, "setColorFilter", accentColor)
        views.setInt(R.id.macro_progress, "setProgressTintList", accentColor)

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

        views.setOnClickPendingIntent(R.id.macro_current, launchAppIntent(context))
        return views
    }

    companion object {
        const val KEY_CARBS_CURRENT = "widget_carbs_current"
        const val KEY_CARBS_TARGET = "widget_carbs_target"
    }
}
