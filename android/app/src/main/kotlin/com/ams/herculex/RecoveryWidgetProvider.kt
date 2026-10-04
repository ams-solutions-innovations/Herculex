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
        val score = if (isWidgetDataStale(prefs)) -1 else prefs.getInt(KEY_RECOVERY_SCORE, -1)

        for (id in appWidgetIds) {
            val views = buildViews(context, score)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, score: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_recovery)

        if (score < 0) {
            views.setTextViewText(R.id.recovery_score, "—")
            views.setViewVisibility(R.id.recovery_progress_green, android.view.View.VISIBLE)
            views.setViewVisibility(R.id.recovery_progress_amber, android.view.View.GONE)
            views.setViewVisibility(R.id.recovery_progress_red, android.view.View.GONE)
            views.setProgressBar(R.id.recovery_progress_green, 100, 0, false)
        } else {
            views.setTextViewText(R.id.recovery_score, "$score%")
            
            views.setViewVisibility(R.id.recovery_progress_green, android.view.View.GONE)
            views.setViewVisibility(R.id.recovery_progress_amber, android.view.View.GONE)
            views.setViewVisibility(R.id.recovery_progress_red, android.view.View.GONE)
            
            val activeId = when {
                score >= 70 -> R.id.recovery_progress_green
                score >= 30 -> R.id.recovery_progress_amber
                else -> R.id.recovery_progress_red
            }
            views.setViewVisibility(activeId, android.view.View.VISIBLE)
            views.setProgressBar(activeId, 100, score, false)
        }

        views.setOnClickPendingIntent(R.id.widget_root, launchAppIntent(context))
        return views
    }

    companion object {
        const val KEY_RECOVERY_SCORE = "widget_recovery_score"
    }
}
