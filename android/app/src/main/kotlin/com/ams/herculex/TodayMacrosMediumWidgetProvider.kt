package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Medium 4x2 "Today's Macros" widget.
 *
 * Displays 3-column breakdown for Carbs, Fat, and Protein with individual
 * circular gauge rings, current/target amounts, and remaining gram labels.
 */
class TodayMacrosMediumWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)

        // Never present another day's macros as today's: on a stale (or not yet
        // synced) store, feed the placeholder sentinels through instead. -1,
        // not 0, so an empty state is distinguishable from a real zero.
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
            views,
            ringId = R.id.carbs_ring_image,
            currentId = R.id.carbs_current_value,
            targetId = R.id.carbs_target_value,
            remainingId = R.id.carbs_remaining_value,
            current = carbsCurrent,
            target = carbsTarget,
            color = Color.parseColor("#34C759"), // Green
        )
        bindColumn(
            views,
            ringId = R.id.fat_ring_image,
            currentId = R.id.fat_current_value,
            targetId = R.id.fat_target_value,
            remainingId = R.id.fat_remaining_value,
            current = fatCurrent,
            target = fatTarget,
            color = Color.parseColor("#FFD60A"), // Yellow
        )
        bindColumn(
            views,
            ringId = R.id.protein_ring_image,
            currentId = R.id.protein_current_value,
            targetId = R.id.protein_target_value,
            remainingId = R.id.protein_remaining_value,
            current = proteinCurrent,
            target = proteinTarget,
            color = Color.parseColor("#4DA3FF"), // Blue
        )

        // Action: Tap card opens Nutrition tab
        val nutritionIntent = Intent(context, MainActivity::class.java).apply {
            action = TodayCaloriesSmallWidgetProvider.ACTION_OPEN_NUTRITION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val nutritionPendingIntent = PendingIntent.getActivity(
            context,
            205,
            nutritionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_root, nutritionPendingIntent)

        return views
    }

    /**
     * Paints one macro column. A negative [current] means "no data for today"
     * and renders the em-dash placeholder with an empty ring.
     */
    private fun bindColumn(
        views: RemoteViews,
        ringId: Int,
        currentId: Int,
        targetId: Int,
        remainingId: Int,
        current: Int,
        target: Int,
        color: Int,
    ) {
        val trackColor = Color.parseColor("#2B374E")
        val hasData = current >= 0

        val progress =
            if (hasData && target > 0) (current.toFloat() / target).coerceIn(0f, 1f) else 0f
        views.setImageViewBitmap(
            ringId,
            WidgetRingRenderer.drawRing(
                sizePx = 240,
                strokeWidthPx = 21f,
                progress = progress,
                progressColor = if (hasData) color else Color.parseColor("#E5E5EA"),
                trackColor = trackColor,
            )
        )

        views.setTextViewText(currentId, if (hasData) "$current" else "—")
        views.setTextViewText(targetId, if (target > 0) "/${target}g" else "/—")

        val remaining = target - current
        views.setTextViewText(
            remainingId,
            when {
                !hasData || target <= 0 -> "—"
                remaining >= 0 -> "$remaining g left"
                else -> "Over ${-remaining}g"
            }
        )
    }
}
