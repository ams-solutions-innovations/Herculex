package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×2 Bodyweight: latest weigh-in, trend toward the goal, and a quick-log button. Data arrives through `syncWidgetData("bodyweight")`. */
class BodyweightWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override val layoutId: Int get() = R.layout.widget_hx_add

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.bodyweight(w, h, trend(data(context, "bodyweight"), "Tap + to log"))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 223, "/measurements/bodyweight"))
        views.setOnClickPendingIntent(R.id.btn_add, command(context, 224, "logWeight"))
    }
}
