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
 * Four tactile shortcuts: add 250 ml of water, scan a barcode, AI photo food
 * recognition, and jump to active/today workout.
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

        // Water: forwarded through MainActivity to Dart's "addWater" handler
        val waterIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_ADD_WATER
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val waterPendingIntent = PendingIntent.getActivity(
            context, 501, waterIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.col_quick_water, waterPendingIntent)
        views.setOnClickPendingIntent(R.id.btn_quick_water, waterPendingIntent)

        // Scan barcode: opens Barcode Scanner
        val scanIntent = Intent(context, MainActivity::class.java).apply {
            action = ScannerWidgetProvider.ACTION_SCAN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val scanPendingIntent = PendingIntent.getActivity(
            context, 502, scanIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.col_quick_scan, scanPendingIntent)
        views.setOnClickPendingIntent(R.id.btn_quick_scan, scanPendingIntent)

        // AI Camera: opens camera for AI photo food recognition
        val cameraIntent = Intent(context, MainActivity::class.java).apply {
            action = TodayCaloriesMediumWidgetProvider.ACTION_OPEN_CAMERA_FOOD_LOG
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val cameraPendingIntent = PendingIntent.getActivity(
            context, 503, cameraIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.col_quick_camera, cameraPendingIntent)
        views.setOnClickPendingIntent(R.id.btn_quick_camera, cameraPendingIntent)

        // Workout: jump to active / planned workout
        val workoutIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("open_active_workout", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val workoutPendingIntent = PendingIntent.getActivity(
            context, 504, workoutIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.col_quick_workout, workoutPendingIntent)
        views.setOnClickPendingIntent(R.id.btn_quick_workout, workoutPendingIntent)

        return views
    }

    companion object {
        const val ACTION_ADD_WATER = "com.ams.herculex.ACTION_ADD_WATER"
    }
}
