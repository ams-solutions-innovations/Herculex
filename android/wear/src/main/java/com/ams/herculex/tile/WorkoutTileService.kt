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
class WorkoutTileService : HxTileService("5") {

    override val freshnessMs = 30 * 60 * 1000L // keep the resume/start state fresh

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        // Today's scheduled workout(s) first, then the phone's order.
        val workouts = WorkoutStore.getWorkoutsScheduledFirst(this)
        val resume = WorkoutStore.getActiveSessionJson(this) != null
        val pillW = params.deviceConfiguration.screenWidthDp.toFloat() * 0.78f

        val items = mutableListOf<LayoutElement>(
            LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                .addContent(HxTile.icon("ic_hx_dumbbell", 12f, HxTile.Workout.accent))
                .addContent(HxTile.hSpacer(4f))
                .addContent(HxTile.text("Herculex", 10f, HxTile.Workout.accent, bold = true, caps = true)).build().enter(0),
            HxTile.spacer(5f),
        )

        // Every pill on this tile has the same width and height.
        if (resume) {
            items += HxTile.pill(pillW, PILL_H, HxTile.Emerald, "ic_hx_play", "Resume Workout", "In progress",
                clickable = HxTile.launch(this, "tile_resume", "active_workout")).enter(1)
        } else {
            workouts.take(MAX_PILLS).forEachIndexed { i, wo ->
                if (i > 0) items += HxTile.spacer(4f)
                val today = wo.scheduledToday
                items += HxTile.pill(
                    pillW, PILL_H,
                    if (today) HxTile.RoyalBlue else HxTile.SlateNavy,
                    if (today) "ic_hx_play" else "ic_hx_dumbbell",
                    if (today) wo.scheduleTitle ?: wo.name else wo.name,
                    if (today) "Today · ${wo.exercises.size} exercises" else "${wo.exercises.size} exercises",
                    clickable = HxTile.launch(this, "tile_w_${wo.id}", "start_workout/${wo.id}"),
                ).enter(1 + i)
            }
        }
        items += HxTile.spacer(6f)
        items += LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(androidx.wear.protolayout.ModifiersBuilders.Modifiers.Builder()
                .setClickable(HxTile.launch(this, "tile_all", "workout_list")).build())
            .addContent(HxTile.text("All Workouts (${workouts.size})", 10.5f, HxTile.Muted, bold = true))
            .addContent(HxTile.icon("ic_hx_chevron", 11f, HxTile.Muted)).build().enter(4)

        return HxTile.face(HxTile.Workout.glowRes, emptyList(), HxTile.column(*items.toTypedArray()), topInset = TOP_INSET)
    }

    private companion object {
        const val PILL_H = 40f
        const val MAX_PILLS = 3
        const val TOP_INSET = 20f
    }
}
