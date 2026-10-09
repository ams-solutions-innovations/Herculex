package com.ams.herculex.tile.kit

import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.tiles.SuspendingTileService

/**
 * Common plumbing for all Herculex tiles: registers the glow + HxIcons images,
 * wraps [layout] in a single timeline entry and applies [freshnessMs].
 * Bump [resVersion] whenever a drawable changes.
 */
@OptIn(ExperimentalHorologistApi::class)
abstract class HxTileService(private val resVersion: String) : SuspendingTileService() {

    protected open val freshnessMs: Long = 0L
    protected abstract fun layout(params: RequestBuilders.TileRequest): LayoutElementBuilders.LayoutElement

    private val imageNames = listOf(
        "hx_glow_fasting", "hx_glow_macros", "hx_glow_water", "hx_glow_volume", "hx_glow_workout",
        "ic_hx_fasting", "ic_hx_flame", "ic_hx_utensils", "ic_hx_clock", "ic_hx_play",
        "ic_hx_dumbbell", "ic_hx_drop", "ic_hx_barbell", "ic_hx_chevron", "ic_hx_check", "ic_hx_stop",
    )

    override suspend fun resourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ResourceBuilders.Resources {
        val b = ResourceBuilders.Resources.Builder().setVersion(requestParams.version)
        imageNames.forEach { name ->
            val resId = resources.getIdentifier(name, "drawable", packageName)
            if (resId != 0) b.addIdToImageMapping(
                name,
                ResourceBuilders.ImageResource.Builder().setAndroidResourceByResId(
                    ResourceBuilders.AndroidImageResourceByResId.Builder().setResourceId(resId).build()
                ).build()
            )
        }
        return b.build()
    }

    override suspend fun tileRequest(requestParams: RequestBuilders.TileRequest): TileBuilders.Tile =
        TileBuilders.Tile.Builder()
            .setResourcesVersion(resVersion)
            .setFreshnessIntervalMillis(freshnessMs)
            .setTileTimeline(
                TimelineBuilders.Timeline.fromLayoutElement(layout(requestParams))
            ).build()
}
