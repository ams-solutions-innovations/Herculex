package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 4×2 Supplements: today's checklist and progress. Data arrives through `syncWidgetData("supplements")`. */
class SupplementsWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 176f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "supplements")
        val arr = d?.optJSONArray("items")
        val items = if (arr == null) emptyList() else (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            HxSupplement(o.getString("name"), o.optString("detail"), o.optBoolean("taken"))
        }
        return renderer.supplements(w, h, HxSupplements(d?.optInt("taken") ?: 0, d?.optInt("total") ?: 0, items))
    }

    // The checklist lives on the dashboard; ticking happens there.
    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 226, 0))
    }
}
