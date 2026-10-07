package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×2 Intake trend: average daily calories over the last 7 days. Data arrives through `syncWidgetData("intake")`. */
class IntakeTrendWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.intakeTrend(w, h, trend(data(context, "intake"), "kcal/day"))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 229, "/nutrition/weekly-stats"))
    }
}
