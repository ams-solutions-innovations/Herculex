package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 Next focus: the readiest split and how many of its muscles are fresh. Data arrives through `syncWidgetData("next_focus")`. */
class NextFocusWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val d = data(context, "next_focus")
        return renderer.nextFocus(w, h, HxNextFocus(d?.optStringOrNull("category"), d?.optInt("fresh") ?: 0))
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 211, "/recovery"))
    }
}
