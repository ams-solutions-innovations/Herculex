package com.ams.herculex

import android.content.Context
import android.view.View
import android.widget.RemoteViews

/**
 * 4×2 Supplements: today's checklist and progress. Data arrives through
 * `syncWidgetData("supplements")`. Tapping an item ticks it; anywhere else
 * opens the Supplements screen.
 */
class SupplementsWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 176f

    override val layoutId: Int get() = R.layout.widget_hx_supplements

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "supplements")
        val arr = d?.optJSONArray("items")
        val items = if (arr == null) emptyList() else (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            HxSupplement(o.getString("name"), o.optString("detail"), o.optBoolean("taken"))
        }
        return renderer.supplements(w, h, HxSupplements(d?.optInt("taken") ?: 0, d?.optInt("total") ?: 0, items))
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 226, ROUTE_SUPPLEMENTS))
        val items = data(context, "supplements")?.optJSONArray("items")
        for ((slot, viewId) in ITEM_TARGETS.withIndex()) {
            val id = items?.optJSONObject(slot)?.optString("id")?.takeIf { it.isNotEmpty() }
            if (id == null) {
                // No item here: let the tap fall through to the card.
                views.setViewVisibility(viewId, View.GONE)
            } else {
                views.setViewVisibility(viewId, View.VISIBLE)
                views.setOnClickPendingIntent(viewId, command(context, 240 + slot, "toggleSupplement", id))
            }
        }
    }

    companion object {
        /** `AppRoutes.supplements`. */
        const val ROUTE_SUPPLEMENTS = "/supplements"

        private val ITEM_TARGETS = intArrayOf(
            R.id.btn_item_0, R.id.btn_item_1, R.id.btn_item_2,
            R.id.btn_item_3, R.id.btn_item_4, R.id.btn_item_5,
        )
    }
}
