package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Medium 4x2 "Today's Calories" widget.
 *
 * Displays circular calorie gauge with remaining calories, detailed breakdown
 * (Base Goal, Food, Exercise), and quick-action shortcuts (Food Search, Barcode Scanner).
 */
class TodayCaloriesMediumWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)
        val baseGoal = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_BASE_GOAL, 0)
        val food = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_FOOD, 0)
        val exercise = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_EXERCISE, 0)
        val remaining = prefs.getInt(
            TodayCaloriesSmallWidgetProvider.KEY_CALORIES_REMAINING,
            if (baseGoal > 0) baseGoal - food + exercise else -1
        )

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
        val views = RemoteViews(context.packageName, R.layout.widget_today_calories_medium)

        if (baseGoal <= 0 && remaining < 0) {
            views.setTextViewText(R.id.calories_remaining_value, "—")
            views.setTextViewText(R.id.calories_base_goal, "—")
            views.setTextViewText(R.id.calories_food_value, "0")
            views.setTextViewText(R.id.calories_exercise_value, "0")
            val emptyRing = WidgetRingRenderer.drawRing(
                sizePx = 240,
                strokeWidthPx = 18f,
                progress = 0f,
                progressColor = Color.parseColor("#E5E5EA"),
                trackColor = Color.parseColor("#2C2C32")
            )
            views.setImageViewBitmap(R.id.calories_ring_image, emptyRing)
        } else {
            val totalAllowance = (baseGoal + exercise).coerceAtLeast(1)
            val progress = (food.toFloat() / totalAllowance).coerceIn(0f, 1f)

            val ringColor = when {
                remaining < 0 -> Color.parseColor("#FF453A")
                food > 0 -> Color.parseColor("#E5E5EA")
                else -> Color.parseColor("#E5E5EA")
            }

            val ringBitmap = WidgetRingRenderer.drawRing(
                sizePx = 240,
                strokeWidthPx = 18f,
                progress = progress,
                progressColor = ringColor,
                trackColor = Color.parseColor("#2C2C32")
            )
            views.setImageViewBitmap(R.id.calories_ring_image, ringBitmap)

            views.setTextViewText(R.id.calories_remaining_value, String.format("%,d", remaining.coerceAtLeast(0)))
            views.setTextViewText(R.id.calories_base_goal, String.format("%,d", baseGoal))
            views.setTextViewText(R.id.calories_food_value, String.format("%,d", food))
            views.setTextViewText(R.id.calories_exercise_value, String.format("%,d", exercise))
        }

        // Action: Tap card opens Nutrition tab
        val nutritionIntent = Intent(context, MainActivity::class.java).apply {
            action = TodayCaloriesSmallWidgetProvider.ACTION_OPEN_NUTRITION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val nutritionPendingIntent = PendingIntent.getActivity(
            context,
            202,
            nutritionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_root, nutritionPendingIntent)

        // Action: Search button opens Food search
        val searchIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SEARCH_FOOD
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val searchPendingIntent = PendingIntent.getActivity(
            context,
            203,
            searchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_search_food, searchPendingIntent)

        // Action: Scanner button opens Barcode Scanner
        val scanIntent = Intent(context, MainActivity::class.java).apply {
            action = ScannerWidgetProvider.ACTION_SCAN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val scanPendingIntent = PendingIntent.getActivity(
            context,
            204,
            scanIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_scan_food, scanPendingIntent)

        return views
    }

    companion object {
        const val ACTION_SEARCH_FOOD = "com.ams.herculex.ACTION_SEARCH_FOOD"
    }
}
