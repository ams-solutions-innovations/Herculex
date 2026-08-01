package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Recovery Score pill widget.
 *
 * Shows the average muscle recovery score (0–100) with a color-coded
 * horizontal progress bar: green ≥ 70, amber ≥ 30, red < 30.
 */
class RecoveryWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val score = prefs.getInt(KEY_RECOVERY_SCORE, -1)

        for (id in appWidgetIds) {
            val views = buildViews(context, score)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, score: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_recovery)

        if (score < 0) {
            views.setTextViewText(R.id.recovery_score, "—")
            views.setProgressBar(R.id.recovery_progress, 100, 0, false)
        } else {
            views.setTextViewText(R.id.recovery_score, "$score%")
            views.setProgressBar(R.id.recovery_progress, 100, score, false)

            val color = when {
                score >= 70 -> Color.parseColor("#30D158")
                score >= 30 -> Color.parseColor("#FFD60A")
                else -> Color.parseColor("#FF453A")
            }
            views.setInt(R.id.recovery_progress, "setProgressTintList", color)
        }

        views.setOnClickPendingIntent(R.id.recovery_score, launchAppIntent(context))
        return views
    }

    companion object {
        const val KEY_RECOVERY_SCORE = "widget_recovery_score"
    }
}
