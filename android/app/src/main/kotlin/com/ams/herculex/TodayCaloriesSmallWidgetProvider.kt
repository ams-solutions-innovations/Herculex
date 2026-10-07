package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/**
 * 2×2 Calories widget: remaining (or over-budget) kcal with a progress bar,
 * food and exercise totals. Tapping opens Nutrition.
 */
class TodayCaloriesSmallWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.calories(w, h, nutrition(CnsWidgetProvider.getPrefs(context)))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openNutrition(context))
    }

    companion object {
        const val KEY_CALORIES_BASE_GOAL = "widget_calories_base_goal"
        const val KEY_CALORIES_FOOD = "widget_calories_food"
        const val KEY_CALORIES_EXERCISE = "widget_calories_exercise"
        const val KEY_CALORIES_REMAINING = "widget_calories_remaining"
        const val ACTION_OPEN_NUTRITION = "com.ams.herculex.ACTION_OPEN_NUTRITION"
    }
}
