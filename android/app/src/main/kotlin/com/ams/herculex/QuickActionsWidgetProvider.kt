package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Quick Actions row widget (4x1).
 *
 * Four static tap targets: add 250 ml of water, scan a barcode, log food, and
 * jump to the active/today workout. Has no dynamic data — it never needs an
 * `AppWidgetManager.updateAppWidget` sync call beyond the initial bind.
 */
class QuickActionsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            val views = buildViews(context)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_quick_actions)

        // Water: forwarded through MainActivity to Dart's "addWater" handler,
        // which calls NutritionRepository.addWaterMl(now, 250) — see
        // app.dart's widgetChannel.setMethodCallHandler.
        val waterIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_ADD_WATER
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        views.setOnClickPendingIntent(
            R.id.btn_quick_water,
            PendingIntent.getActivity(
                context, 501, waterIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        // Scan: reuses the Scanner widget's existing deep link.
        val scanIntent = Intent(context, MainActivity::class.java).apply {
            action = ScannerWidgetProvider.ACTION_SCAN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        views.setOnClickPendingIntent(
            R.id.btn_quick_scan,
            PendingIntent.getActivity(
                context, 502, scanIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        // Log food: reuses the Today's Calories (Medium) search-food deep
        // link — closer to "log food" intent than the plain nutrition-tab one.
        val logFoodIntent = Intent(context, MainActivity::class.java).apply {
            action = TodayCaloriesMediumWidgetProvider.ACTION_SEARCH_FOOD
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        views.setOnClickPendingIntent(
            R.id.btn_quick_log_food,
            PendingIntent.getActivity(
                context, 503, logFoodIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        // Workout: same "open_active_workout" deep link the Training card's
        // Start button and the Workout Bubble already use.
        val workoutIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("open_active_workout", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        views.setOnClickPendingIntent(
            R.id.btn_quick_workout,
            PendingIntent.getActivity(
                context, 504, workoutIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        return views
    }

    companion object {
        const val ACTION_ADD_WATER = "com.ams.herculex.ACTION_ADD_WATER"
    }
}
