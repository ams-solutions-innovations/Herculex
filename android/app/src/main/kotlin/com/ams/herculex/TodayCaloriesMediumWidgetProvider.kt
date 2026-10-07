package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/**
 * 4×2 Today widget: remaining-calorie gauge, the three macro bars, and
 * Log food / Scan shortcuts. Tapping elsewhere opens Nutrition.
 */
class TodayCaloriesMediumWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 176f

    override val layoutId: Int get() = R.layout.widget_hx_today

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.today(w, h, nutrition(CnsWidgetProvider.getPrefs(context)))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openNutrition(context))
        views.setOnClickPendingIntent(R.id.btn_search_food, searchFood(context))
        views.setOnClickPendingIntent(R.id.btn_scan_food, scanFood(context))
    }

    companion object {
        const val ACTION_SEARCH_FOOD = "com.ams.herculex.ACTION_SEARCH_FOOD"
    }
}
