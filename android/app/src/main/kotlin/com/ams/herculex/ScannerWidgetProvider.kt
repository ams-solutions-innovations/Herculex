package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Scanner shortcut pill widget.
 *
 * Tapping opens [MainActivity] with action [ACTION_SCAN] so Flutter can
 * navigate directly to the barcode scanner screen via a route handler in main.dart.
 */
class ScannerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            val views = buildViews(context)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_scanner)

        // Deep-link intent: opens MainActivity with the SCAN action.
        // Flutter's GoRouter checks getIntent().action on startup and pushes /nutrition/scan.
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SCAN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        views.setOnClickPendingIntent(R.id.scanner_label, pendingIntent)
        views.setOnClickPendingIntent(R.id.scanner_icon, pendingIntent)
        return views
    }

    companion object {
        const val ACTION_SCAN = "com.ams.herculex.ACTION_SCAN"
    }
}
