package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * "KCAL LEFT" pill widget (2x1).
 *
 * Restyled to the rounded-pill visual language: shows remaining calories for
 * the day next to a flame icon.
 */
class TodayCaloriesSmallWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val stale = isWidgetDataStale(prefs)
        val baseGoal = if (stale) 0 else prefs.getInt(KEY_CALORIES_BASE_GOAL, 0)
        val food = if (stale) 0 else prefs.getInt(KEY_CALORIES_FOOD, 0)
        val exercise = if (stale) 0 else prefs.getInt(KEY_CALORIES_EXERCISE, 0)
        val remaining = if (stale) -1 else prefs.getInt(
            KEY_CALORIES_REMAINING,
            if (baseGoal > 0) baseGoal - food + exercise else -1
        )

        for (id in appWidgetIds) {
            val views = buildViews(context, baseGoal, remaining)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(
        context: Context,
        baseGoal: Int,
        remaining: Int
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_calories_small)

        if (baseGoal <= 0 && remaining < 0) {
            views.setTextViewText(R.id.calories_remaining_value, "—")
        } else {
            views.setTextViewText(R.id.calories_remaining_value, String.format("%,d", remaining.coerceAtLeast(0)))
        }

        // Tap on widget opens Nutrition in Herculex
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_NUTRITION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            201,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        return views
    }

    companion object {
        const val KEY_CALORIES_BASE_GOAL = "widget_calories_base_goal"
        const val KEY_CALORIES_FOOD = "widget_calories_food"
        const val KEY_CALORIES_EXERCISE = "widget_calories_exercise"
        const val KEY_CALORIES_REMAINING = "widget_calories_remaining"
        const val ACTION_OPEN_NUTRITION = "com.ams.herculex.ACTION_OPEN_NUTRITION"
    }
}
