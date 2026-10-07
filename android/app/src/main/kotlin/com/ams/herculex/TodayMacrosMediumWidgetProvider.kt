package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Medium 4x2 "Today's Macros" widget.
 *
 * Displays 3-column breakdown for Carbs, Fat, and Protein with individual
 * circular gauge rings, current/target amounts, and remaining gram labels.
 * Adapts dynamically to light and dark theme changes.
 */
class TodayMacrosMediumWidgetProvider : AppWidgetProvider() {

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

        val carbsCurrent =
            if (stale) -1 else prefs.getInt(CarbsWidgetProvider.KEY_CARBS_CURRENT, -1)
        val carbsTarget =
            if (stale) 0 else prefs.getInt(CarbsWidgetProvider.KEY_CARBS_TARGET, 0)
        val fatCurrent =
            if (stale) -1 else prefs.getInt(FatWidgetProvider.KEY_FAT_CURRENT, -1)
        val fatTarget =
            if (stale) 0 else prefs.getInt(FatWidgetProvider.KEY_FAT_TARGET, 0)
        val proteinCurrent =
            if (stale) -1 else prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_CURRENT, -1)
        val proteinTarget =
            if (stale) 0 else prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_TARGET, 0)

        for (id in appWidgetIds) {
            val views = buildViews(
                context,
                carbsCurrent,
                carbsTarget,
                fatCurrent,
                fatTarget,
                proteinCurrent,
                proteinTarget
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(
        context: Context,
        carbsCurrent: Int,
        carbsTarget: Int,
        fatCurrent: Int,
        fatTarget: Int,
        proteinCurrent: Int,
        proteinTarget: Int
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_macros_medium)

        bindColumn(
            context = context,
            views = views,
            ringId = R.id.carbs_ring_image,
            currentId = R.id.carbs_current_value,
            targetId = R.id.carbs_target_value,
            remainingId = R.id.carbs_remaining_value,
            current = carbsCurrent,
            target = carbsTarget,
            color = context.getColor(R.color.widget_macro_carbs),
        )
        bindColumn(
            context = context,
            views = views,
            ringId = R.id.fat_ring_image,
            currentId = R.id.fat_current_value,
            targetId = R.id.fat_target_value,
            remainingId = R.id.fat_remaining_value,
            current = fatCurrent,
            target = fatTarget,
            color = context.getColor(R.color.widget_macro_fat),
        )
        bindColumn(
            context = context,
            views = views,
            ringId = R.id.protein_ring_image,
            currentId = R.id.protein_current_value,
            targetId = R.id.protein_target_value,
            remainingId = R.id.protein_remaining_value,
            current = proteinCurrent,
            target = proteinTarget,
            color = context.getColor(R.color.widget_macro_protein),
        )

        // Action: Tap card opens Nutrition tab
        val intent = Intent(context, MainActivity::class.java).apply {
            action = TodayCaloriesSmallWidgetProvider.ACTION_OPEN_NUTRITION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            207,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        return views
    }

    private fun bindColumn(
        context: Context,
        views: RemoteViews,
        ringId: Int,
        currentId: Int,
        targetId: Int,
        remainingId: Int,
        current: Int,
        target: Int,
        color: Int,
    ) {
        val trackColor = context.getColor(R.color.widget_ring_track)
        if (current < 0) {
            views.setTextViewText(currentId, "—")
            views.setTextViewText(targetId, "")
            views.setTextViewText(remainingId, "—")

            val emptyRing = WidgetRingRenderer.drawRing(
                sizePx = 200,
                strokeWidthPx = 16f,
                progress = 0f,
                progressColor = color,
                trackColor = trackColor
            )
            views.setImageViewBitmap(ringId, emptyRing)
            return
        }

        views.setTextViewText(currentId, "${current}")
        views.setTextViewText(targetId, if (target > 0) "/${target}g" else "")

        val left = if (target > 0) target - current else 0
        val remainingText = when {
            target <= 0 -> ""
            left >= 0 -> "${left}g left"
            else -> "+${-left}g over"
        }
        views.setTextViewText(remainingId, remainingText)

        val progress = if (target > 0) (current.toFloat() / target).coerceIn(0f, 1f) else 0f
        val ringBitmap = WidgetRingRenderer.drawRing(
            sizePx = 200,
            strokeWidthPx = 16f,
            progress = progress,
            progressColor = color,
            trackColor = trackColor
        )
        views.setImageViewBitmap(ringId, ringBitmap)
    }
}
