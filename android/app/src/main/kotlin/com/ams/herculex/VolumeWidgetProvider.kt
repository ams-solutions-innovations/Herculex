package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 Volume: working sets logged this week. Data arrives through `syncWidgetData("volume")`. */
class VolumeWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "volume")
        return renderer.volume(w, h, if (d == null || d.isNull("sets")) null else d.getInt("sets"))
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 225, "/muscle-volume"))
    }
}
