package com.ams.herculex

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

/**
 * 2×1 CNS Load widget: readiness % and FRESH/MODERATE/HIGH badge, tinted by
 * status. Data arrives through `syncCns`; tapping opens the CNS screen.
 */
class CnsWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val prefs = getPrefs(context)
        val readiness = prefs.getInt(KEY_CNS_READINESS, -1)
        val status = prefs.getString(KEY_CNS_STATUS, null)
        val known = !isWidgetDataStale(prefs) && readiness >= 0 && status != null
        return renderer.cns(w, h, HxCns(readiness.takeIf { known }, status.takeIf { known }))
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 210, "/cns"))
    }

    companion object {
        const val KEY_CNS_READINESS = "widget_cns_readiness"
        const val KEY_CNS_STATUS = "widget_cns_status"

        fun getPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /** Push fresh data and trigger a redraw for all active instances. */
        fun updateAll(context: Context, appWidgetManager: AppWidgetManager, ids: IntArray) {
            CnsWidgetProvider().onUpdate(context, appWidgetManager, ids)
        }
    }
}

const val PREFS_NAME = "FlutterSharedPreferences"
