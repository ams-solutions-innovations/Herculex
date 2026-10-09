package com.ams.herculex.tile

import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.tiles.RequestBuilders
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService

/**
 * Macros tile v2: calories on the bezel (vs. goal), P / C / F as three
 * mini bars, "Log food" pill = the same SlateNavy + utensils pill as the
 * watch's Nutrition menu. All values + goals already live in MacroStore.
 */
class MacrosTileService : HxTileService("6") {

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val kcal = MacroStore.calories(this)
        val kcalGoal = MacroStore.calorieGoal(this).coerceAtLeast(1)
        val frac = (kcal.toFloat() / kcalGoal).coerceIn(0f, 1f)

        val bezel = listOf(
            HxTile.track(HxTile.Macros.track),
            HxTile.arc(HxTile.Macros.accent, HxTile.animDegrees(0f, 360f * frac)),
        )

        val cols = listOf(
            Triple("Protein", MacroStore.protein(this) to MacroStore.proteinGoal(this), HxTile.c(0xFFFFA726)),
            Triple("Carbs", MacroStore.carbs(this) to MacroStore.carbsGoal(this), HxTile.c(0xFF34C759)),
            Triple("Fat", MacroStore.fats(this) to MacroStore.fatGoal(this), HxTile.c(0xFFFFD60A)),
        ).map { (name, vg, color) -> macroColumn(name, vg.first, vg.second, color) }

        val row = LayoutElementBuilders.Row.Builder()
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_TOP)
        cols.forEachIndexed { i, c -> if (i > 0) row.addContent(HxTile.hSpacer(8f)); row.addContent(c) }

        val cta = HxTile.pill(126f, 34f, HxTile.SlateNavy, "ic_hx_utensils", "Log food",
            clickable = HxTile.launch(this, "tile_log_food", "log_food"))

        return HxTile.face(
            HxTile.Macros.glowRes, bezel,
            HxTile.column(
                HxTile.label("ic_hx_flame", "Today", HxTile.Macros.label).enter(0),
                HxTile.countUp(kcal, 42f, HxTile.White).enter(1),
                HxTile.text("of ${"%,d".format(kcalGoal)} kcal", 11f, HxTile.Muted).enter(2),
                HxTile.spacer(6f),
                row.build().enter(3),
                HxTile.spacer(6f),
                cta.enter(4),
            )
        )
    }

    private fun macroColumn(name: String, value: Int, goal: Int, color: androidx.wear.protolayout.ColorBuilders.ColorProp): LayoutElement {
        val barW = 38f
        val fill = (value.toFloat() / goal.coerceAtLeast(1)).coerceIn(0f, 1f)
        fun bar(w: Float, c: androidx.wear.protolayout.ColorBuilders.ColorProp) = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(w)).setHeight(DimensionBuilders.dp(3.5f))
            .setModifiers(ModifiersBuilders.Modifiers.Builder().setBackground(
                ModifiersBuilders.Background.Builder().setColor(c)
                    .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(2f)).build()).build()).build())
            .build()
        return LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(HxTile.text("${value}g", 13f, HxTile.White, bold = true, tabular = true))
            .addContent(
                LayoutElementBuilders.Box.Builder()
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
                    .addContent(bar(barW, HxTile.c(0xFF1F2638)))
                    .addContent(bar((barW * fill).coerceAtLeast(2f), color))
                    .build()
            )
            .addContent(HxTile.text(name, 10f, HxTile.Muted))
            .build()
    }
}
