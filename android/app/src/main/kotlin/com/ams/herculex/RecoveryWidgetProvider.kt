package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/**
 * 2×2 Recovery widget: average recovery score plus the two most fatigued
 * muscle groups. Data arrives through `syncRecovery`; tapping opens Recovery.
 */
class RecoveryWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 176f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.recovery(w, h, recovery(CnsWidgetProvider.getPrefs(context)))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 211, "/recovery"))
    }

    companion object {
        const val KEY_RECOVERY_SCORE = "widget_recovery_score"

        /** JSON array of `{name, score}`, most fatigued first. */
        const val KEY_RECOVERY_MUSCLES = "widget_recovery_muscles"
    }
}
