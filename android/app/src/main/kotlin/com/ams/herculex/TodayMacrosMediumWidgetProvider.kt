package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 4×1 Macros widget: protein, carbs and fat against target. Tapping opens Nutrition. */
class TodayMacrosMediumWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.macros(w, h, nutrition(CnsWidgetProvider.getPrefs(context)))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openNutrition(context))
    }
}
