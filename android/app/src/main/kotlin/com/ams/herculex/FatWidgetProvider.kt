package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 Fat widget: today's grams against target. Tapping opens Nutrition. */
class FatWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val n = nutrition(CnsWidgetProvider.getPrefs(context))
        return renderer.macro(w, h, HxMacroKind.FAT, n.fat)
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openNutrition(context))
    }

    companion object {
        const val KEY_FAT_CURRENT = "widget_fat_current"
        const val KEY_FAT_TARGET = "widget_fat_target"
    }
}
