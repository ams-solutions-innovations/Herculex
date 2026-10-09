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
class WorkoutTileService : HxTileService("4") {

    override val freshnessMs = 30 * 60 * 1000L // keep the resume/start state fresh

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val workouts = WorkoutStore.getWorkouts(this)
        // The watch has no schedule; the first synced template is the primary action (as in v1).
        val primary = workouts.firstOrNull()
        val resume = WorkoutStore.getActiveSessionJson(this) != null
        val w = params.deviceConfiguration.screenWidthDp.toFloat()
        val bigW = w * 0.78f
        val smallW = w * 0.74f

        val items = mutableListOf<LayoutElement>(
            LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                .addContent(HxTile.icon("ic_hx_dumbbell", 12f, HxTile.Workout.accent))
                .addContent(HxTile.hSpacer(4f))
                .addContent(HxTile.text("Herculex", 10f, HxTile.Workout.accent, bold = true, caps = true)).build().enter(0),
            HxTile.spacer(4f),
        )

        if (resume) {
            items += HxTile.pill(bigW, 50f, HxTile.Emerald, "ic_hx_play", "Resume Workout", "In progress",
                clickable = HxTile.launch(this, "tile_resume", "active_workout")).enter(1)
        } else {
            if (primary != null) {
                items += HxTile.pill(bigW, 50f, HxTile.RoyalBlue, "ic_hx_play", primary.name,
                    "${primary.exercises.size} exercises",
                    clickable = HxTile.launch(this, "tile_primary", "start_workout/${primary.id}")).enter(1)
            }
            workouts.filter { it.id != primary?.id }.take(if (primary != null) 2 else 3)
                .forEachIndexed { i, wo ->
                    items += HxTile.spacer(4f)
                    items += HxTile.pill(smallW, 36f, HxTile.SlateNavy, "ic_hx_dumbbell", wo.name,
                        "${wo.exercises.size} exercises",
                        clickable = HxTile.launch(this, "tile_w_${wo.id}", "start_workout/${wo.id}")).enter(2 + i)
                }
        }
        items += HxTile.spacer(6f)
        items += LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(androidx.wear.protolayout.ModifiersBuilders.Modifiers.Builder()
                .setClickable(HxTile.launch(this, "tile_all", "workout_list")).build())
            .addContent(HxTile.text("All Workouts (${workouts.size})", 10.5f, HxTile.Muted, bold = true))
            .addContent(HxTile.icon("ic_hx_chevron", 11f, HxTile.Muted)).build().enter(4)

        return HxTile.face(HxTile.Workout.glowRes, emptyList(), HxTile.column(*items.toTypedArray()))
    }
}
