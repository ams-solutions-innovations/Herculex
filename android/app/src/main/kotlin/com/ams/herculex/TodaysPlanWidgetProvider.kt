package com.ams.herculex

import android.content.Context
import android.widget.RemoteViews

/** 4×2 Today's Plan: the scheduled program day with a Start button. Data arrives through `syncWidgetData("plan")`. */
class TodaysPlanWidgetProvider : HxWidgetProvider() {

    override val defaultSize = 364f to 176f

    override val layoutId: Int get() = R.layout.widget_hx_plan

    override fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered =
        renderer.todaysPlan(w, h, plan(context))

    override fun bindClicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 220, 2))
        val start = when (plan(context).state) {
            HxPlanState.READY -> command(context, 221, "startPlan")
            HxPlanState.ACTIVE -> command(context, 222, "resumeWorkout")
            else -> openTab(context, 220, 2)
        }
        views.setOnClickPendingIntent(R.id.btn_primary, start)
    }

    private fun plan(context: Context): HxPlan {
        val d = data(context, "plan")
        return HxPlan(
            state = when (d?.optString("state")) {
                "ready" -> HxPlanState.READY
                "active" -> HxPlanState.ACTIVE
                "done" -> HxPlanState.DONE
                else -> HxPlanState.NONE
            },
            title = d?.optString("title")?.takeIf { it.isNotEmpty() } ?: "Rest day",
            subtitle = d?.optString("subtitle") ?: "No workout scheduled",
            badge = d?.optStringOrNull("badge"),
            button = d?.optString("button")?.takeIf { it.isNotEmpty() } ?: "Open workouts",
        )
    }
}
