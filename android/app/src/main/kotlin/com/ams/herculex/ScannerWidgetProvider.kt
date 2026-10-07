package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/**
 * 2×1 Quick log widget: a Scan button that opens the barcode scanner and a
 * search button that opens food search.
 *
 * Both open [MainActivity] with an action that Flutter turns into navigation
 * via the widget MethodChannel (see `app.dart`).
 */
class ScannerWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override val layoutId: Int get() = R.layout.widget_hx_quick_log

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.quickLog(w, h)

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.btn_scan_food, scanFood(context))
        views.setOnClickPendingIntent(R.id.btn_search_food, searchFood(context))
    }

    companion object {
        const val ACTION_SCAN = "com.ams.herculex.ACTION_SCAN"
    }
}
