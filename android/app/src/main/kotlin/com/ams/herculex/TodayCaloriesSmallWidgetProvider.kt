package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Small 2x2 "Today's Calories" widget.
 *
 * Displays circular calorie gauge with remaining calories, food consumed,
 * and exercise calories burned.
 */
class TodayCaloriesSmallWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val baseGoal = prefs.getInt(KEY_CALORIES_BASE_GOAL, 0)
        val food = prefs.getInt(KEY_CALORIES_FOOD, 0)
        val exercise = prefs.getInt(KEY_CALORIES_EXERCISE, 0)
        val remaining = prefs.getInt(KEY_CALORIES_REMAINING, if (baseGoal > 0) baseGoal - food + exercise else -1)

        for (id in appWidgetIds) {
            val views = buildViews(context, baseGoal, food, exercise, remaining)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(
        context: Context,
        baseGoal: Int,
        food: Int,
        exercise: Int,
        remaining: Int
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_calories_small)

        if (baseGoal <= 0 && remaining < 0) {
            views.setTextViewText(R.id.calories_remaining_value, "—")
            views.setTextViewText(R.id.calories_food_value, "0")
            views.setTextViewText(R.id.calories_exercise_value, "0")
            val emptyRing = WidgetRingRenderer.drawRing(
                sizePx = 220,
                strokeWidthPx = 16f,
                progress = 0f,
                progressColor = Color.parseColor("#E5E5EA"),
                trackColor = Color.parseColor("#2C2C32")
            )
            views.setImageViewBitmap(R.id.calories_ring_image, emptyRing)
        } else {
            val totalAllowance = (baseGoal + exercise).coerceAtLeast(1)
            val progress = (food.toFloat() / totalAllowance).coerceIn(0f, 1f)

            val ringColor = when {
                remaining < 0 -> Color.parseColor("#FF453A") // Over goal
                food > 0 -> Color.parseColor("#E5E5EA") // Active progress
                else -> Color.parseColor("#E5E5EA")
            }

            val ringBitmap = WidgetRingRenderer.drawRing(
                sizePx = 220,
                strokeWidthPx = 16f,
                progress = progress,
                progressColor = ringColor,
                trackColor = Color.parseColor("#2C2C32")
            )
            views.setImageViewBitmap(R.id.calories_ring_image, ringBitmap)

            views.setTextViewText(R.id.calories_remaining_value, String.format("%,d", remaining.coerceAtLeast(0)))
            views.setTextViewText(R.id.calories_food_value, String.format("%,d", food))
            views.setTextViewText(R.id.calories_exercise_value, String.format("%,d", exercise))
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
