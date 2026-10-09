package com.ams.herculex.tile

import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.tiles.RequestBuilders
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService
import org.json.JSONArray

/**
 * NEW tile. The bezel is split by muscle (share of weekly tonnage) from the
 * same `weeklyVolumeJson` WeeklyVolumeScreen reads. No goal exists for volume,
 * so the ring shows composition, not progress.
 */
class WeeklyVolumeTileService : HxTileService("1") {

    private val palette = listOf(0xFF4F7BEA, 0xFF42A5F5, 0xFF80CBF5, 0xFF9FB0D4, 0xFFC0CCEC).map { HxTile.c(it) }

    private data class Muscle(val name: String, val tonnage: Double, val sets: Double)

    private fun muscles(): List<Muscle> = runCatching {
        val a = JSONArray(MacroStore.weeklyVolumeJson(this))
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            Muscle(o.getString("muscle"), o.getDouble("tonnage"), o.getDouble("sets"))
        }.sortedByDescending { it.tonnage }
    }.getOrDefault(emptyList())

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val list = muscles().take(5)
        val total = MacroStore.weeklyTonnage(this)
        val sets = MacroStore.weeklySets(this)
        val sum = list.sumOf { it.tonnage }.takeIf { it > 0 } ?: 1.0
        val gap = 4f

        val ring = LayoutElementBuilders.Arc.Builder()
            .setAnchorAngle(DimensionBuilders.degrees(0f))
            .setAnchorType(LayoutElementBuilders.ARC_ANCHOR_START)
        list.forEachIndexed { i, m ->
            val deg = (360f * (m.tonnage / sum).toFloat() - gap).coerceAtLeast(1f)
            // all segments unfold together; later ones slide along as earlier ones grow
            ring.addContent(
                LayoutElementBuilders.ArcLine.Builder()
                    .setLength(HxTile.animDegrees(0f, deg))
                    .setColor(palette[i % palette.size])
                    .setThickness(DimensionBuilders.dp(HxTile.RING_DP)).build()
            )
            ring.addContent(LayoutElementBuilders.ArcSpacer.Builder().setLength(DimensionBuilders.degrees(gap)).build())
        }

        val legend = LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        list.take(3).forEachIndexed { i, m ->
            if (i > 0) legend.addContent(HxTile.hSpacer(8f))
            legend.addContent(HxTile.text("\u25CF", 8f, palette[i])).addContent(HxTile.hSpacer(3f))
                .addContent(HxTile.text(m.name, 10f, HxTile.c(0xFFD5DBE8)))
        }

        val tonnageText = if (total >= 1000f) "%.1f".format(total / 1000f) else "%d".format(total.toInt())
        val unit = if (total >= 1000f) "t" else "kg"

        return HxTile.face(
            HxTile.Volume.glowRes,
            listOf(HxTile.track(HxTile.Volume.track), ring.build()),
            HxTile.column(
                HxTile.label("ic_hx_barbell", "Weekly volume", HxTile.Volume.label).enter(0),
                LayoutElementBuilders.Row.Builder().setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_BOTTOM)
                    .addContent(HxTile.text(tonnageText, 42f, HxTile.White, bold = true, tabular = true))
                    .addContent(HxTile.hSpacer(2f))
                    .addContent(HxTile.text(unit, 20f, HxTile.Muted, bold = true)).build().enter(1),
                HxTile.text("$sets sets \u00B7 this week", 11f, HxTile.Muted).enter(2),
                HxTile.spacer(6f),
                legend.build().enter(3),
                HxTile.spacer(6f),
                HxTile.pill(126f, 34f, HxTile.SlateNavy, "ic_hx_barbell", "Breakdown", trailing = true,
                    clickable = HxTile.launch(this, "tile_volume", "weekly_volume")).enter(4),
            )
        )
    }
}
