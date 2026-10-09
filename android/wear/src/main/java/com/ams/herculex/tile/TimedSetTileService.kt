package com.ams.herculex.tile

import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.TypeBuilders.StringProp
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicDuration
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicInstant
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicString
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.ams.herculex.tile.SetTimerStore.Mode
import com.ams.herculex.workout.WorkoutStore
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService
import java.time.Instant

/**
 * NEW tile: stopwatch for `time` exercises (plank, wall sit, hollow hold).
 * Teal = the Time column colour in SetLoggerScreen (0xFF26A69A).
 *
 * Ticking is done by the host: the elapsed text and the ring are DynamicFloat /
 * DynamicString derived from `DynamicInstant.platformTimeWithSecondsPrecision()`,
 * so no 1 s refresh is needed. The "goal reached" look is a SECOND timeline entry
 * valid from startedAt + target, so the swap happens on time even if the tile
 * is never re-requested.
 *
 * Exact DynamicDuration / formatter member names: verify against protolayout 1.2.
 */
class TimedSetTileService : HxTileService("1") {

    private val teal = HxTile.c(0xFF26A69A)
    private val tealLight = HxTile.c(0xFF80CBC4)
    private val track = HxTile.c(0xFF0F2E2B)
    private val TealPill = HxTile.PillStyle(HxTile.c(0xFF0E4B46), HxTile.c(0xFF082F2C), HxTile.c(0xFFA5E0DA))
    private val StopPill = HxTile.PillStyle(HxTile.c(0xFF7A2434), HxTile.c(0xFF4F1520), HxTile.c(0xFFFFC1C9)) // = FastingScreen "Stop"

    // Current set of the active session; falls back to a 60 s plank when no workout is running.
    private val active get() = WorkoutStore.activeSetSummary(this)
    private val targetSec get() = active?.targetSeconds ?: 60
    private val title get() = active?.let { "${it.exerciseName} \u00B7 Set ${it.setNumber}/${it.setTotal}" } ?: "Timed set"
    private val logRoute get() = active?.let { "set_logger/${it.exerciseIndex}" } ?: "active_workout"

    override suspend fun tileRequest(r: RequestBuilders.TileRequest): TileBuilders.Tile {
        val store = SetTimerStore(this, "timed")
        when (r.currentState.lastClickableId) {
            "ts_start" -> store.start()
            "ts_stop" -> store.stop()
            "ts_reset" -> store.reset()
        }
        val timeline = TimelineBuilders.Timeline.Builder()
        if (store.mode == Mode.RUN) {
            val goalAt = store.startedAtMs + targetSec * 1000L
            val now = System.currentTimeMillis()
            if (goalAt > now) {
                timeline.addTimelineEntry(entry(running(store, reached = false), now, goalAt))
                timeline.addTimelineEntry(entry(running(store, reached = true), goalAt, null))
            } else timeline.addTimelineEntry(entry(running(store, reached = true), null, null))
        } else {
            timeline.addTimelineEntry(entry(settled(store), null, null))
        }
        return TileBuilders.Tile.Builder().setResourcesVersion("1").setTileTimeline(timeline.build()).build()
    }

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement = settled(SetTimerStore(this, "timed"))

    private fun entry(layout: LayoutElement, from: Long?, until: Long?): TimelineBuilders.TimelineEntry =
        TimelineBuilders.TimelineEntry.Builder()
            .setLayout(LayoutElementBuilders.Layout.Builder().setRoot(layout).build())
            .also { b ->
                if (from != null || until != null) b.setValidity(
                    TimelineBuilders.TimeInterval.Builder().setStartMillis(from ?: 0L).setEndMillis(until ?: Long.MAX_VALUE).build()
                )
            }.build()

    /** IDLE and DONE: static text, no ticking. */
    private fun settled(store: SetTimerStore): LayoutElement {
        val el = (store.elapsedNow() / 1000).toInt()
        val idle = store.mode == Mode.IDLE
        val frac = if (idle) 0f else (el.toFloat() / targetSec).coerceIn(0f, 1f)
        val over = !idle && el >= targetSec
        val caption = when {
            idle -> "target ${mmss(targetSec)}"
            over -> "+${mmss(el - targetSec)} over target"
            else -> "${mmss(targetSec - el)} short of target"
        }
        val cta = if (idle) HxTile.pill(98f, 38f, TealPill, "ic_hx_play", "Start set", clickable = HxTile.load("ts_start"))
        else HxTile.pill(98f, 38f, HxTile.RoyalBlue, "ic_hx_check", "Log set",
            clickable = HxTile.launch(this, "ts_log", logRoute)) // opens the set logger; time is not prefilled yet
        return frame(
            ring = HxTile.arc(if (over) tealLight else teal, HxTile.animDegrees(0f, 360f * frac)),
            hero = HxTile.text(mmss(el), 44f, HxTile.White, bold = true, tabular = true),
            caption = HxTile.text(caption, 11f, if (over) tealLight else HxTile.Muted, bold = over),
            cta = cta,
            discard = !idle,
        )
    }

    /** RUN: host-ticked stopwatch. [reached] = entry valid after startedAt + target. */
    private fun running(store: SetTimerStore, reached: Boolean): LayoutElement {
        val start = DynamicInstant.withSecondsPrecision(Instant.ofEpochMilli(store.startedAtMs))
        val elapsed: DynamicDuration = start.durationUntil(DynamicInstant.platformTimeWithSecondsPrecision())
        val hero = LayoutElementBuilders.Text.Builder()
            .setText(StringProp.Builder("0:00").setDynamicValue(mmssDynamic(elapsed)).build())
            .setLayoutConstraintsForDynamicText(
                androidx.wear.protolayout.TypeBuilders.StringLayoutConstraint.Builder("00:00").build()
            )
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder().setSize(DimensionBuilders.sp(44f)).setColor(HxTile.White)
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD).setSettings(LayoutElementBuilders.FontSetting.tnum()).build()
            ).build()
        // sweep: arc length follows elapsed seconds (verify clamp; the 2nd entry pins it at 360 once reached)
        val sweep = if (reached) HxTile.animDegrees(360f, 360f)
        else androidx.wear.protolayout.DimensionBuilders.DegreesProp.Builder(0f)
            .setDynamicValue(elapsed.toIntSeconds().asFloat().times(360f / targetSec)).build()
        return frame(
            ring = HxTile.arc(if (reached) tealLight else teal, sweep),
            hero = hero,
            caption = HxTile.text(if (reached) "Goal reached \u2713" else "target ${mmss(targetSec)}", 11f,
                if (reached) tealLight else HxTile.Muted, bold = reached),
            cta = HxTile.pill(98f, 38f, StopPill, "ic_hx_stop", "Stop", clickable = HxTile.load("ts_stop")),
            discard = false,
        )
    }

    private fun frame(ring: LayoutElement, hero: LayoutElement, caption: LayoutElement, cta: LayoutElement, discard: Boolean): LayoutElement =
        HxTile.face(
            "hx_glow_workout",
            listOf(HxTile.track(track), ring),
            HxTile.column(
                HxTile.label("ic_hx_clock", title, tealLight).enter(0),
                hero.enter(1), caption.enter(2), HxTile.spacer(6f), cta.enter(4),
                if (discard) HxTile.text("Discard", 10.5f, HxTile.Muted, bold = true).also { /* clickable: ts_reset */ }
                else HxTile.spacer(14f),
            )
        )

    private fun mmss(s: Int) = "%d:%02d".format(s / 60, s % 60)

    private fun mmssDynamic(d: DynamicDuration): DynamicString =
        d.minutesPart.format().concat(DynamicString.constant(":")).concat(
            d.secondsPart.format(
                androidx.wear.protolayout.expression.DynamicBuilders.DynamicInt32.IntFormatter.Builder().setMinIntegerDigits(2).build()
            )
        )
}
