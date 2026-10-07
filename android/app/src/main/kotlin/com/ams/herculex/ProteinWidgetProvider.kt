package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 Protein widget: today's grams against target. Tapping opens Nutrition. */
class ProteinWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered {
        val n = nutrition(CnsWidgetProvider.getPrefs(context))
        return renderer.macro(w, h, HxMacroKind.PROTEIN, n.protein)
    }

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openNutrition(context))
    }

    companion object {
        const val KEY_PROTEIN_CURRENT = "widget_protein_current"
        const val KEY_PROTEIN_TARGET = "widget_protein_target"
    }
}
