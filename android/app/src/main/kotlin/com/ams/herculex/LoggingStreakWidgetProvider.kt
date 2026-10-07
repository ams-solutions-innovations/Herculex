package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 Logging streak: consecutive days of food logging. Data arrives through `syncWidgetData("streak_logging")`. */
class LoggingStreakWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.streak(w, h, HxStreakKind.LOGGING, streak(data(context, "streak_logging"), "days"))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openNutrition(context))
    }
}
