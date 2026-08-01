package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews

/**
 * CNS Load pill widget.
 *
 * Displays readiness % and FRESH/MODERATE/HIGH badge. Updated via
 * [AppWidgetManager.updateAppWidget] called from [MainActivity]'s MethodChannel
 * handler whenever Flutter pushes new CNS data.
 */
class CnsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = getPrefs(context)
        val readiness = prefs.getInt(KEY_CNS_READINESS, -1)
        val status = prefs.getString(KEY_CNS_STATUS, null)

        for (id in appWidgetIds) {
            val views = buildViews(context, readiness, status)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, readiness: Int, status: String?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_cns)

        if (readiness < 0 || status == null) {
            views.setTextViewText(R.id.cns_readiness, "—")
            views.setTextViewText(R.id.cns_status, "—")
        } else {
            views.setTextViewText(R.id.cns_readiness, "$readiness%")
            views.setTextViewText(R.id.cns_status, status)

            val (textColor, _) = when (status) {
                "FRESH" -> Pair(Color.parseColor("#30D158"), Color.parseColor("#1A30D158"))
                "MODERATE" -> Pair(Color.parseColor("#FFD60A"), Color.parseColor("#1AFFD60A"))
                else -> Pair(Color.parseColor("#FF453A"), Color.parseColor("#1AFF453A"))
            }
            views.setTextColor(R.id.cns_status, textColor)
        }

        // Tap opens the app
        views.setOnClickPendingIntent(
            R.id.cns_status,
            launchAppIntent(context)
        )

        return views
    }

    companion object {
        const val KEY_CNS_READINESS = "widget_cns_readiness"
        const val KEY_CNS_STATUS = "widget_cns_status"

        fun getPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /** Push fresh data and trigger a redraw for all active instances. */
        fun updateAll(context: Context, appWidgetManager: AppWidgetManager, ids: IntArray) {
            val provider = CnsWidgetProvider()
            provider.onUpdate(context, appWidgetManager, ids)
        }
    }
}

const val PREFS_NAME = "FlutterSharedPreferences"

/** Returns a PendingIntent that launches the main Herculex activity. */
fun launchAppIntent(context: Context): PendingIntent {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: Intent(context, MainActivity::class.java)
    return PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}
