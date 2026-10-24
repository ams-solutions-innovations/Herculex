package com.ams.herculex.tile

import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.tiles.RequestBuilders
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService
import com.ams.herculex.workout.WorkoutStore

/**
 * Workout quick-start v2. Same data and routes as before; pills are rebuilt
 * on the shared kit (HxIcons instead of emoji / "▶" text, OneUiPill
 * proportions) and enter with a stagger. No bezel: this tile is all actions.
 */
class WorkoutTileService : HxTileService("7") {

    override val freshnessMs = 30 * 60 * 1000L // keep the resume/start state fresh

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        // Today's scheduled workout(s) first, then the phone's order.
        val workouts = WorkoutStore.getWorkoutsScheduledFirst(this)
        val activeJson = WorkoutStore.getActiveSessionJson(this)
        val resume = activeJson != null
        val w = params.deviceConfiguration.screenWidthDp.toFloat()
        // Same pill size as the Workouts screen in the app (OneUiPill: full width
        // minus 14dp side padding, 52dp tall).
        val pillW = w - 28f
        val height = params.deviceConfiguration.screenHeightDp.toFloat()
        val availablePills = ((height - TOP_INSET_DP - 38f) / (PILL_H + 4f)).toInt().coerceAtLeast(1)
        val templatePills = (availablePills - 1).coerceIn(1, MAX_TEMPLATE_PILLS)

        val items = mutableListOf<LayoutElement>(
            LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                .addContent(HxTile.icon("ic_hx_dumbbell", 12f, HxTile.Workout.accent))
                .addContent(HxTile.hSpacer(4f))
                .addContent(HxTile.text("Herculex", 10f, HxTile.Workout.accent, bold = true, caps = true)).build().enter(0),
            HxTile.spacer(4f),
        )

        if (resume) {
            val startMs = WorkoutStore.getActiveSessionStartEpoch(this)
                ?: activeJson?.let { WorkoutStore.startedAtEpochMsFromSessionJson(it) }
            val resumeSub = if (startMs != null && startMs > 0L) {
                val elapsedSec = ((System.currentTimeMillis() - startMs) / 1000L).coerceAtLeast(0L)
                "In progress · %d:%02d".format(elapsedSec / 60, elapsedSec % 60)
            } else {
                "In progress"
            }
            items += HxTile.pill(
                pillW, PILL_H, HxTile.Emerald, "ic_hx_play", "Resume Workout", resumeSub,
                clickable = HxTile.launch(this, "tile_resume", "active_workout"),
                shimmer = true,
            ).enter(1)
        } else {
            workouts.take(templatePills).forEachIndexed { i, wo ->
                val today = wo.scheduledToday
                if (i > 0) items += HxTile.spacer(4f)
                items += HxTile.pill(
                    pillW, PILL_H, if (today) HxTile.RoyalBlue else HxTile.SlateNavy, "ic_hx_dumbbell",
                    if (today) wo.scheduleTitle ?: wo.name else wo.name,
                    if (today) "Today · ${wo.exercises.size} exercises" else "${wo.exercises.size} exercises",
                    clickable = HxTile.launch(this, "tile_w_${wo.id}", "workout_detail/${wo.id}"),
                    shimmer = today,
                ).enter(1 + i)
            }
            // Start Empty Workout, same as the button at the bottom of the Workouts screen.
            if (availablePills > 1 || workouts.isEmpty()) {
            items += HxTile.spacer(4f)
            items += HxTile.pill(
                pillW, PILL_H, HxTile.AccentBlue, "ic_hx_plus", "Empty Workout",
                clickable = HxTile.launch(this, "tile_empty", "quick_workout"),
            ).enter(3)
            }
        }
        items += HxTile.spacer(4f)
        items += LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(androidx.wear.protolayout.ModifiersBuilders.Modifiers.Builder()
                .setClickable(HxTile.launch(this, "tile_all", "workout_list")).build())
            .addContent(HxTile.text(if (resume) "All Workouts" else "All Workouts (${workouts.size})", 10.5f, HxTile.Muted, bold = true))
            .addContent(HxTile.icon("ic_hx_chevron", 11f, HxTile.Muted)).build().enter(4)

        return HxTile.face(HxTile.Workout.glowRes, emptyList(), HxTile.column(*items.toTypedArray()), topInset = TOP_INSET_DP)
    }

    private companion object {
        // OneUiPill on the Workouts screen: heightIn(min = 52dp), 38dp badge.
        const val TOP_INSET_DP = 40f
        const val PILL_H = 52f
        const val MAX_TEMPLATE_PILLS = 2
    }
}
