package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 4×1 Mini workout: the next unfinished micro workout with a +1 Done button. Data arrives through `syncWidgetData("mini")`. */
class MiniWorkoutWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 80f

    override val layoutId: Int get() = R.layout.widget_hx_mini

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.miniWorkout(w, h, mini(context))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openRoute(context, 227, "/micro-workouts"))
        val d = data(context, "mini")
        val m = mini(context)
        // Logging a round opens the app, which records it (no background writes).
        val tap = if (m != null && m.done < m.total) {
            command(context, 228, "logMiniWorkout", d?.optString("id"))
        } else {
            openRoute(context, 227, "/micro-workouts")
        }
        views.setOnClickPendingIntent(R.id.btn_primary, tap)
    }

    private fun mini(context: Context): HxMiniWorkout? {
        val d = data(context, "mini") ?: return null
        if (d.isNull("id")) return null
        return HxMiniWorkout(d.getString("name"), d.getInt("done"), d.getInt("total"))
    }
}
