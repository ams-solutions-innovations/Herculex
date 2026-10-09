package com.ams.herculex.tile

import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.tiles.RequestBuilders
import com.ams.herculex.sync.FastingStore
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService

/**
 * Fasting tile v2. Same state machine as before (active / scheduled / idle),
 * new anatomy: bezel arc with 25/50/75 % notches → label → hero → caption →
 * stage chip → pill. Hero is white; the ring carries the colour.
 */
class FastingTileService : HxTileService("3") {

    override val freshnessMs = 60_000L // active fast: keep H:MM current

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val snap = FastingStore.snapshot(this)
        val now = System.currentTimeMillis()
        val active = snap.hasActiveFast
        val scheduled = !active && snap.nextFastEpochMs != null

        val frac = when { active -> snap.progress(now); scheduled -> 0.06f; else -> 0f }
        val accent = if (active) HxTile.Fasting.accent else HxTile.StartFast.container
        val bezel = listOf(
            HxTile.track(HxTile.Fasting.track),
            HxTile.arc(accent, HxTile.animDegrees(0f, 360f * frac)),
            HxTile.notch(90f), HxTile.notch(180f), HxTile.notch(270f),
        )

        val el = snap.elapsedSeconds(now)
        val hero = when {
            active -> "%d:%02d".format(el / 3600, (el % 3600) / 60)
            scheduled -> snap.timeUntilNextFast(now) ?: "soon"
            else -> "16:8"
        }
        val caption = when {
            active -> "elapsed · ${(snap.progress(now) * 100).toInt()}%"
            scheduled -> "${snap.nextFastFormatted(now)} · ${snap.nextFastPlanName ?: "16:8"}"
            else -> snap.lastFastDurationSeconds?.let { "Last: ${it / 3600}h ${(it % 3600) / 60}m" } ?: "Ready to fast"
        }
        val captionColor = if (scheduled) HxTile.Fasting.accent else HxTile.Muted

        val cta = if (active) {
            HxTile.pill(98f, 36f, HxTile.Violet, "ic_hx_clock", "Open timer",
                clickable = HxTile.launch(this, "tile_fasting", "fasting"))
        } else {
            HxTile.pill(98f, 36f, HxTile.StartFast, "ic_hx_play", "Start fast",
                clickable = HxTile.launch(this, "tile_fasting", "fasting"))
        }

        val items = mutableListOf<LayoutElement>(
            HxTile.label("ic_hx_fasting", if (scheduled) "Next fast" else "Fasting", HxTile.Fasting.label).enter(0),
            HxTile.text(hero, if (scheduled) 37f else 42f, HxTile.White, bold = true, tabular = true).enter(1),
            HxTile.text(caption, 11f, captionColor).enter(2),
        )
        if (active) snap.currentStageMessage?.let { stage ->
            items += stageChip(stage).enter(3)
        }
        items += HxTile.spacer(6f)
        items += cta.enter(4)

        return HxTile.face(HxTile.Fasting.glowRes, bezel, HxTile.column(*items.toTypedArray()))
    }

    private fun stageChip(stage: String): LayoutElement =
        androidx.wear.protolayout.LayoutElementBuilders.Row.Builder()
            .setVerticalAlignment(androidx.wear.protolayout.LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder().setColor(HxTile.c(0x2164D2FF))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(10f)).build()).build()
                    )
                    .setPadding(ModifiersBuilders.Padding.Builder().setStart(DimensionBuilders.dp(6f)).setEnd(DimensionBuilders.dp(8f))
                        .setTop(DimensionBuilders.dp(2f)).setBottom(DimensionBuilders.dp(2f)).build())
                    .build()
            )
            .addContent(HxTile.icon("ic_hx_flame", 11f, HxTile.Fasting.accent))
            .addContent(HxTile.hSpacer(3f))
            .addContent(HxTile.text(stage, 10f, HxTile.Fasting.accent, bold = true))
            .build()
}
