package com.ams.herculex.tile

import android.content.Context
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService

/**
 * NEW tile. Water ring + two quick-add chips that run INSIDE the tile
 * (LoadAction → tileRequest with `currentState.lastClickableId`), so a tap
 * logs water without launching the app and the ring animates from the old
 * fill to the new one.
 */
class WaterTileService : HxTileService("1") {

    private companion object {
        const val ADD_250 = "water_250"
        const val ADD_500 = "water_500"
        const val PREFS = "hx_water_tile"
        const val KEY_PREV = "prev_frac"
    }

    override suspend fun tileRequest(requestParams: RequestBuilders.TileRequest): TileBuilders.Tile {
        when (requestParams.currentState.lastClickableId) {
            ADD_250 -> logWater(250)
            ADD_500 -> logWater(500)
        }
        return super.tileRequest(requestParams)
    }

    /** Same path as NutritionViewModel.addWater: local store first, then the phone command. */
    private fun logWater(ml: Int) {
        MacroStore.addWater(this, ml)
        // TODO: extract NutritionViewModel.sendMacroCommand into a small MacroCommandSender
        //       and call MacroStore.createCommand(kind = "water", waterMl = ml) through it here.
        TileService.getUpdater(this).requestUpdate(MacrosTileService::class.java)
    }

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val ml = MacroStore.water(this)
        val goal = MacroStore.waterGoal(this).coerceAtLeast(1)
        val frac = (ml.toFloat() / goal).coerceIn(0f, 1f)
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val prev = prefs.getFloat(KEY_PREV, 0f)
        prefs.edit().putFloat(KEY_PREV, frac).apply()

        val bezel = listOf(
            HxTile.track(HxTile.Water.track),
            HxTile.arc(HxTile.Water.accent, HxTile.animDegrees(360f * prev, 360f * frac, ms = if (prev == 0f) 1100 else 700)),
        )
        val reached = ml >= goal
        val chips = LayoutElementBuilders.Row.Builder()
            .addContent(chip("+250", ADD_250)).addContent(HxTile.hSpacer(6f)).addContent(chip("+500", ADD_500)).build()

        return HxTile.face(
            HxTile.Water.glowRes, bezel,
            HxTile.column(
                HxTile.label("ic_hx_drop", "Water", HxTile.Water.label).enter(0),
                HxTile.countUp(ml, 42f, HxTile.White).enter(1),
                HxTile.text(if (reached) "Goal reached" else "of ${"%,d".format(goal)} ml", 11f,
                    if (reached) HxTile.Water.accent else HxTile.Muted, bold = reached).enter(2),
                HxTile.spacer(12f),
                chips.enter(4),
            )
        )
    }

    private fun chip(label: String, id: String): LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(68f)).setHeight(DimensionBuilders.dp(34f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder().setColor(HxTile.c(0xFF142B66))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(17f)).build()).build()
                    )
                    .setClickable(HxTile.load(id)).build()
            )
            .addContent(HxTile.text(label, 13f, HxTile.Water.accent, bold = true))
            .build()
}
