package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 2×1 Workout streak: consecutive training weeks. Data arrives through `syncWidgetData("streak_workouts")`. */
class WorkoutStreakWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 182f to 80f

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.streak(w, h, HxStreakKind.WORKOUTS, streak(data(context, "streak_workouts"), "weeks"))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 220, 2))
    }
}
