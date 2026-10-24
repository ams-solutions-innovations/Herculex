package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 sleep summary; taps open the Sleep & Recovery page. */
class SleepWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 86f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "sleep")?.takeIf {
            it.optLong("epochDay", -1L) == currentEpochDay()
        }
        return renderer.healthMetric(
            w = w,
            h = h,
            accent = renderer.p.recovery,
            icon = HxIcon.SPA,
            caption = "SLEEP",
            value = d?.optStringOrNull("value"),
            unit = d?.optStringOrNull("unit"),
            description = d?.optStringOrNull("description") ?: "Sleep not synced today",
        )
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 231, "/sleep"))
    }
}
