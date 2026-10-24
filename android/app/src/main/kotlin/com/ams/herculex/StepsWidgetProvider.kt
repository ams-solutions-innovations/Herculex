package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 step summary; taps open the Daily Steps & NEAT page. */
class StepsWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 86f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "steps")?.takeIf {
            it.optLong("epochDay", -1L) == currentEpochDay()
        }
        return renderer.healthMetric(
            w = w,
            h = h,
            accent = renderer.p.success,
            icon = HxIcon.DIRECTIONS_RUN,
            caption = "STEPS TODAY",
            value = d?.optStringOrNull("value"),
            unit = d?.optStringOrNull("unit"),
            description = d?.optStringOrNull("description") ?: "Steps not synced today",
        )
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 232, "/steps"))
    }
}
