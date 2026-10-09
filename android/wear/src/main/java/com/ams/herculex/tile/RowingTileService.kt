package com.ams.herculex.tile

import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.ams.herculex.tile.SetTimerStore.Mode
import com.ams.herculex.workout.WorkoutStore
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService

/**
 * NEW tile: `time_distance` exercises (rowing erg, ski erg, sled). Time ticks
 * (same host-driven stopwatch as TimedSetTileService); metres are synced from
 * the erg with -100 / +100 chips (LoadAction); pace /500 m is derived at render.
 * Ring = metres vs. the planned distance; distance is blue (rotary DISTANCE
 * colour in SetLoggerScreen), time/pace teal (Time colour).
 *
 * Re-render on every chip tap already gives a fresh pace. While running, ask
 * for a refresh each 15 s (freshnessMs) so pace drifts correctly if the user
 * stops tapping. The hero time itself is host-ticked like in TimedSetTileService
 * (copy `running()` from there; omitted here to keep the sketch short).
 */
class RowingTileService : HxTileService("1") {

    // Current set of the active session; falls back to 2,000 m when no workout is running.
    private val active get() = WorkoutStore.activeSetSummary(this)
    private val targetM get() = active?.targetMeters ?: 2000
    private val title get() = active?.let { "${it.exerciseName} \u00B7 Set ${it.setNumber}" } ?: "Rowing"
    private val logRoute get() = active?.let { "set_logger/${it.exerciseIndex}" } ?: "active_workout"
    private val blue = HxTile.c(0xFF42A5F5)
    private val tealLight = HxTile.c(0xFF80CBC4)

    override val freshnessMs = 15_000L

    override suspend fun tileRequest(r: RequestBuilders.TileRequest): TileBuilders.Tile {
        val store = SetTimerStore(this, "rowing")
        when (r.currentState.lastClickableId) {
            "rw_start" -> store.start()
            "rw_stop" -> store.stop()
            "rw_minus" -> store.nudgeDistance(-100)
            "rw_plus" -> store.nudgeDistance(+100)
        }
        return super.tileRequest(r)
    }

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val s = SetTimerStore(this, "rowing")
        val sec = (s.elapsedNow() / 1000).toInt()
        val d = s.distanceM
        val frac = (d.toFloat() / targetM).coerceIn(0f, 1f)
        val pace = if (d > 0 && sec > 0) (sec / (d / 500f)).toInt() else 0
        val active = s.mode != Mode.IDLE

        val stepper = LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(chip("\u2212", "rw_minus", active)).addContent(HxTile.hSpacer(6f))
            .addContent(HxTile.countUp(d, 24f, blue, delayMs = 0, maxChars = "00,000"))
            .addContent(HxTile.text(" m", 11f, HxTile.Muted))
            .addContent(HxTile.hSpacer(6f)).addContent(chip("+", "rw_plus", active)).build()

        val cta = when (s.mode) {
            Mode.IDLE -> HxTile.pill(98f, 36f, HxTile.PillStyle(HxTile.c(0xFF0E4B46), HxTile.c(0xFF082F2C), HxTile.c(0xFFA5E0DA)),
                "ic_hx_play", "Start row", clickable = HxTile.load("rw_start"))
            Mode.RUN -> HxTile.pill(98f, 36f, HxTile.PillStyle(HxTile.c(0xFF7A2434), HxTile.c(0xFF4F1520), HxTile.c(0xFFFFC1C9)),
                "ic_hx_stop", "Finish", clickable = HxTile.load("rw_stop"))
            Mode.DONE -> HxTile.pill(98f, 36f, HxTile.RoyalBlue, "ic_hx_check", "Log set",
                clickable = HxTile.launch(this, "rw_log", logRoute)) // opens the set logger; time/metres are not prefilled yet
        }

        return HxTile.face(
            "hx_glow_workout",
            listOf(HxTile.track(HxTile.c(0xFF14263D)), HxTile.arc(blue, HxTile.animDegrees(0f, 360f * frac, ms = 600))),
            HxTile.column(
                HxTile.label("ic_hx_clock", title, HxTile.c(0xFF80C4FA)).enter(0),
                HxTile.text("%d:%02d".format(sec / 60, sec % 60), 40f, HxTile.White, bold = true, tabular = true).enter(1),
                stepper.enter(2),
                HxTile.text(
                    if (pace > 0) "%d:%02d /500 m".format(pace / 60, pace % 60) else if (s.mode == Mode.RUN) "tap \u00B1 to sync with erg" else "target ${"%,d".format(targetM)} m",
                    11f, if (pace > 0) tealLight else HxTile.Muted, bold = pace > 0, tabular = true
                ).enter(3),
                HxTile.spacer(4f),
                cta.enter(4),
            )
        )
    }

    private fun chip(label: String, id: String, enabled: Boolean): LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(30f)).setHeight(DimensionBuilders.dp(30f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder().setColor(HxTile.c(if (enabled) 0xFF142B66 else 0xFF0B1636))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(15f)).build()).build()
                    )
                    .also { if (enabled) it.setClickable(HxTile.load(id)) }.build()
            )
            .addContent(HxTile.text(label, 16f, HxTile.c(if (enabled) 0xFF80C4FA else 0xFF4A5875), bold = true))
            .build()
}
