package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 4×1 Week: this week's days with done and scheduled workouts. Data arrives through `syncWidgetData("week")`. */
class WeekWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val arr = data(context, "week")?.optJSONArray("days")
        val days = if (arr == null) emptyList() else (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            HxWeekDay(
                label = o.getString("label"),
                day = o.getInt("day"),
                today = o.optBoolean("today"),
                done = o.optBoolean("done"),
                scheduled = o.optBoolean("scheduled"),
            )
        }
        return renderer.week(w, h, days)
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 220, 2))
    }
}
