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
import com.ams.herculex.sync.WearDataLayerSyncManager
import com.ams.herculex.tile.kit.HxTile
import com.ams.herculex.tile.kit.HxTile.enter
import com.ams.herculex.tile.kit.HxTileService

/**
 * NEW tile. Water ring + two quick-add chips that run INSIDE the tile
 * (LoadAction → tileRequest with `currentState.lastClickableId`), so a tap
 * logs water without launching the app and the ring animates from the old
 * fill to the new one.
 */
class WaterTileService : HxTileService("2") {

    private companion object {
        const val ADD_250 = "water_250"
        const val ADD_500 = "water_500"
        const val PREFS = "hx_water_tile"
        const val KEY_PREV = "prev_frac"
        const val KEY_SEQ = "render_seq"
        const val KEY_CONSUMED = "consumed_seq"
    }

    /**
     * Every render stamps its chips with a fresh sequence number ("water_250:7").
     * The host re-sends the *last* clickable id on later refreshes (phone sync,
     * freshness), which would otherwise log the same tap again and again — a
     * stamp is acted on once, then ignored.
     */
    override suspend fun tileRequest(requestParams: RequestBuilders.TileRequest): TileBuilders.Tile {
        consumeClick(requestParams.currentState.lastClickableId)
        return super.tileRequest(requestParams)
    }

    /** Swapped out in tests: the real client waits on Play Services, which Robolectric never answers. */
    internal var sendToPhone: suspend (String) -> Unit = {
        WearDataLayerSyncManager(applicationContext).sendMacroCommand(it)
    }

    internal suspend fun consumeClick(clicked: String) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val seq = clicked.substringAfter(':', "").toIntOrNull() ?: return
        if (seq <= prefs.getInt(KEY_CONSUMED, 0)) return
        val ml = when (clicked.substringBefore(':')) {
            ADD_250 -> 250
            ADD_500 -> 500
            else -> return
        }
        prefs.edit().putInt(KEY_CONSUMED, seq).apply()
        logWater(ml)
    }

    /** Same path as NutritionViewModel.addWater: local store first, then the phone command. */
    private suspend fun logWater(ml: Int) {
        MacroStore.addWater(this, ml)
        runCatching { sendToPhone(MacroStore.createCommand(kind = "water", waterMl = ml)) }
        TileService.getUpdater(this).requestUpdate(MacrosTileService::class.java)
    }

    override fun layout(params: RequestBuilders.TileRequest): LayoutElement {
        val ml = MacroStore.water(this)
        val goal = MacroStore.waterGoal(this).coerceAtLeast(1)
        val frac = (ml.toFloat() / goal).coerceIn(0f, 1f)
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val prev = prefs.getFloat(KEY_PREV, 0f)
        val seq = prefs.getInt(KEY_SEQ, 0) + 1
        prefs.edit().putFloat(KEY_PREV, frac).putInt(KEY_SEQ, seq).apply()

        val bezel = listOf(
            HxTile.track(HxTile.Water.track),
            HxTile.arc(HxTile.Water.accent, HxTile.animDegrees(360f * prev, 360f * frac, ms = if (prev == 0f) 1100 else 700)),
        )
        val reached = ml >= goal
        val chips = LayoutElementBuilders.Row.Builder()
            .addContent(chip("+250", "$ADD_250:$seq")).addContent(HxTile.hSpacer(6f)).addContent(chip("+500", "$ADD_500:$seq")).build()

        return HxTile.face(
            HxTile.Water.glowRes, bezel,
            HxTile.column(
                HxTile.label("ic_hx_drop", "Water", HxTile.Water.label).enter(0),
                HxTile.countUp(ml, 42f, HxTile.White).enter(1),
                HxTile.text(if (reached) "Goal reached" else "of ${"%,d".format(goal)} ml", 11f,
                    if (reached) HxTile.Water.accent else HxTile.Muted, bold = reached).enter(2),
                HxTile.spacer(14f),
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
