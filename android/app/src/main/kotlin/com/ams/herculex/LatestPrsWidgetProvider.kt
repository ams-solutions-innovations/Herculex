package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×2 Latest PRs: top three estimated 1RMs. Data arrives through `syncWidgetData("prs")`. */
class LatestPrsWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "prs")
        val arr = d?.optJSONArray("items")
        val items = if (arr == null) emptyList() else (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            HxPr(o.getString("name"), o.getString("value"))
        }
        return renderer.latestPrs(w, h, HxPrs(d?.optString("unit")?.takeIf { it.isNotEmpty() } ?: "kg", items))
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 220, 2))
    }
}
