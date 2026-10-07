package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Medium 4x2 "Today's Calories" widget.
 *
 * Displays a circular calorie gauge with remaining calories, per-macro
 * progress bars (Protein / Carbs / Fat), and quick-action shortcuts (Food
 * Search, Barcode Scanner, AI Photo/Camera).
 * Adapts dynamically between device Light and Dark mode.
 */
class TodayCaloriesMediumWidgetProvider : AppWidgetProvider() {

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

        val baseGoal =
            if (stale) 0 else prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_BASE_GOAL, 0)
        val food =
            if (stale) 0 else prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_FOOD, 0)
        val exercise =
            if (stale) 0 else prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_EXERCISE, 0)
        val remaining = if (stale) -1 else prefs.getInt(
            TodayCaloriesSmallWidgetProvider.KEY_CALORIES_REMAINING,
            if (baseGoal > 0) baseGoal - food + exercise else -1
        )

        val proteinCurrent =
            if (stale) -1 else prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_CURRENT, -1)
        val proteinTarget =
            if (stale) 0 else prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_TARGET, 0)
        val carbsCurrent =
            if (stale) -1 else prefs.getInt(CarbsWidgetProvider.KEY_CARBS_CURRENT, -1)
        val carbsTarget =
            if (stale) 0 else prefs.getInt(CarbsWidgetProvider.KEY_CARBS_TARGET, 0)
        val fatCurrent =
            if (stale) -1 else prefs.getInt(FatWidgetProvider.KEY_FAT_CURRENT, -1)
        val fatTarget =
            if (stale) 0 else prefs.getInt(FatWidgetProvider.KEY_FAT_TARGET, 0)

        for (id in appWidgetIds) {
            val views = buildViews(
                context,
                baseGoal,
                food,
                exercise,
                remaining,
                proteinCurrent,
                proteinTarget,
                carbsCurrent,
                carbsTarget,
                fatCurrent,
                fatTarget,
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(
        context: Context,
        baseGoal: Int,
        food: Int,
        exercise: Int,
        remaining: Int,
        proteinCurrent: Int,
        proteinTarget: Int,
        carbsCurrent: Int,
        carbsTarget: Int,
        fatCurrent: Int,
        fatTarget: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_calories_medium)
        val trackColor = context.getColor(R.color.widget_ring_track)

        if (baseGoal <= 0 && remaining < 0) {
            views.setTextViewText(R.id.calories_remaining_value, "—")
            val emptyRing = WidgetRingRenderer.drawRing(
                sizePx = 288,
                strokeWidthPx = 20f,
                progress = 0f,
                progressColor = context.getColor(R.color.widget_ring_progress),
                trackColor = trackColor
            )
            views.setImageViewBitmap(R.id.calories_ring_image, emptyRing)
        } else {
            val totalAllowance = (baseGoal + exercise).coerceAtLeast(1)
            val progress = (food.toFloat() / totalAllowance).coerceIn(0f, 1f)

            val ringColor = when {
                remaining < 0 -> context.getColor(R.color.widget_ring_danger)
                else -> context.getColor(R.color.widget_ring_progress)
            }

            val ringBitmap = WidgetRingRenderer.drawRing(
                sizePx = 288,
                strokeWidthPx = 20f,
                progress = progress,
                progressColor = ringColor,
                trackColor = trackColor
            )
            views.setImageViewBitmap(R.id.calories_ring_image, ringBitmap)
            views.setTextViewText(R.id.calories_remaining_value, String.format("%,d", remaining.coerceAtLeast(0)))
        }

        bindMacroRow(views, R.id.macro_progress_protein, R.id.macro_text_protein, proteinCurrent, proteinTarget)
        bindMacroRow(views, R.id.macro_progress_carbs, R.id.macro_text_carbs, carbsCurrent, carbsTarget)
        bindMacroRow(views, R.id.macro_progress_fat, R.id.macro_text_fat, fatCurrent, fatTarget)

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
        views.setOnClickPendingIntent(R.id.col_search_food, searchPendingIntent)
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
        views.setOnClickPendingIntent(R.id.col_scan_food, scanPendingIntent)
        views.setOnClickPendingIntent(R.id.btn_scan_food, scanPendingIntent)

        // Action: Camera button opens AI food-photo camera capture directly
        val cameraIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_CAMERA_FOOD_LOG
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val cameraPendingIntent = PendingIntent.getActivity(
            context,
            205,
            cameraIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.col_camera_food, cameraPendingIntent)
        views.setOnClickPendingIntent(R.id.btn_camera_food, cameraPendingIntent)

        return views
    }

    private fun bindMacroRow(
        views: RemoteViews,
        progressId: Int,
        textId: Int,
        current: Int,
        target: Int,
    ) {
        if (current < 0) {
            views.setProgressBar(progressId, 100, 0, false)
            views.setTextViewText(textId, "—")
            return
        }
        val pct = if (target > 0) ((current.toFloat() / target) * 100).toInt().coerceIn(0, 100) else 0
        views.setProgressBar(progressId, 100, pct, false)
        views.setTextViewText(textId, "${current}/${if (target > 0) "${target}g" else "—"}")
    }

    companion object {
        const val ACTION_SEARCH_FOOD = "com.ams.herculex.ACTION_SEARCH_FOOD"
        const val ACTION_OPEN_CAMERA_FOOD_LOG = "com.ams.herculex.ACTION_OPEN_CAMERA_FOOD_LOG"
    }
}
