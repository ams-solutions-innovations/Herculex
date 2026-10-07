package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×2 Cycle: today's phase, training tip and volume adjustment. Data arrives through `syncWidgetData("cycle")`. */
class CycleWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "cycle")
        val phase = d?.optStringOrNull("phase")?.let { id ->
            HxCyclePhase.entries.firstOrNull { it.name.equals(id, ignoreCase = true) }
        }
        val cycle = if (d == null || phase == null) {
            HxCycle(null, "Cycle", null, "Track your cycle to adapt training to each phase.", "Tap to set up", null)
        } else {
            HxCycle(
                phase = phase,
                title = d.getString("title"),
                badge = d.optStringOrNull("badge"),
                tip = d.optString("tip"),
                footer = d.optString("footer"),
                color = if (d.isNull("color")) null else d.getLong("color").toInt(),
            )
        }
        return renderer.cycle(w, h, cycle)
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 230, "/cycle"))
    }
}
