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
        val carbsCurrent = prefs.getInt(CarbsWidgetProvider.KEY_CARBS_CURRENT, 0)
        val carbsTarget = prefs.getInt(CarbsWidgetProvider.KEY_CARBS_TARGET, 0)
        val fatCurrent = prefs.getInt(FatWidgetProvider.KEY_FAT_CURRENT, 0)
        val fatTarget = prefs.getInt(FatWidgetProvider.KEY_FAT_TARGET, 0)
        val proteinCurrent = prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_CURRENT, 0)
        val proteinTarget = prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_TARGET, 0)

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

        val carbsColor = Color.parseColor("#64D2FF") // Cyan / Teal
        val fatColor = Color.parseColor("#BF5AF2")   // Purple
        val proteinColor = Color.parseColor("#FF9F0A") // Orange
        val trackColor = Color.parseColor("#2C2C32")

        // 1. Carbs
        val carbsProgress = if (carbsTarget > 0) (carbsCurrent.toFloat() / carbsTarget).coerceIn(0f, 1f) else 0f
        val carbsRing = WidgetRingRenderer.drawRing(
            sizePx = 160,
            strokeWidthPx = 14f,
            progress = carbsProgress,
            progressColor = carbsColor,
            trackColor = trackColor
        )
        views.setImageViewBitmap(R.id.carbs_ring_image, carbsRing)
        views.setTextViewText(R.id.carbs_current_value, "$carbsCurrent")
        views.setTextViewText(R.id.carbs_target_value, if (carbsTarget > 0) "/${carbsTarget}g" else "/—")
        val carbsRemaining = carbsTarget - carbsCurrent
        views.setTextViewText(
            R.id.carbs_remaining_value,
            if (carbsTarget <= 0) "—" else if (carbsRemaining >= 0) "$carbsRemaining g left" else "Over ${-carbsRemaining}g"
        )

        // 2. Fat
        val fatProgress = if (fatTarget > 0) (fatCurrent.toFloat() / fatTarget).coerceIn(0f, 1f) else 0f
        val fatRing = WidgetRingRenderer.drawRing(
            sizePx = 160,
            strokeWidthPx = 14f,
            progress = fatProgress,
            progressColor = fatColor,
            trackColor = trackColor
        )
        views.setImageViewBitmap(R.id.fat_ring_image, fatRing)
        views.setTextViewText(R.id.fat_current_value, "$fatCurrent")
        views.setTextViewText(R.id.fat_target_value, if (fatTarget > 0) "/${fatTarget}g" else "/—")
        val fatRemaining = fatTarget - fatCurrent
        views.setTextViewText(
            R.id.fat_remaining_value,
            if (fatTarget <= 0) "—" else if (fatRemaining >= 0) "$fatRemaining g left" else "Over ${-fatRemaining}g"
        )

        // 3. Protein
        val proteinProgress = if (proteinTarget > 0) (proteinCurrent.toFloat() / proteinTarget).coerceIn(0f, 1f) else 0f
        val proteinRing = WidgetRingRenderer.drawRing(
            sizePx = 160,
            strokeWidthPx = 14f,
            progress = proteinProgress,
            progressColor = proteinColor,
            trackColor = trackColor
        )
        views.setImageViewBitmap(R.id.protein_ring_image, proteinRing)
        views.setTextViewText(R.id.protein_current_value, "$proteinCurrent")
        views.setTextViewText(R.id.protein_target_value, if (proteinTarget > 0) "/${proteinTarget}g" else "/—")
        val proteinRemaining = proteinTarget - proteinCurrent
        views.setTextViewText(
            R.id.protein_remaining_value,
            if (proteinTarget <= 0) "—" else if (proteinRemaining >= 0) "$proteinRemaining g left" else "Over ${-proteinRemaining}g"
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
}
