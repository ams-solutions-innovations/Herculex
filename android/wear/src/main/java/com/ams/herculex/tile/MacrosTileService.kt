package com.ams.herculex.tile

import android.graphics.Color
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders.Resources
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.ChipColors
import androidx.wear.protolayout.material.CompactChip
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.ams.herculex.MainActivity
import com.ams.herculex.sync.MacroStore
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.tiles.SuspendingTileService

@OptIn(ExperimentalHorologistApi::class)
class MacrosTileService : SuspendingTileService() {

    companion object {
        private const val RESOURCES_VERSION = "5"

        // Material 3 / Google Calendar pill button colors
        private val COLOR_PRIMARY_CONTAINER = ColorBuilders.argb(0xFFD3E3FD.toInt()) // Soft light blue
        private val COLOR_ON_PRIMARY_CONTAINER = ColorBuilders.argb(0xFF041E49.toInt()) // Deep navy text
        private val COLOR_HEADER_TEXT = ColorBuilders.argb(0xFFBBDEFB.toInt()) // Soft blue header
    }

    override suspend fun resourcesRequest(requestParams: RequestBuilders.ResourcesRequest): Resources {
        return Resources.Builder()
            .setVersion(requestParams.version)
            .build()
    }

    override suspend fun tileRequest(requestParams: RequestBuilders.TileRequest): TileBuilders.Tile {
        val singleTimelineEntry = TimelineBuilders.TimelineEntry.Builder()
            .setLayout(
                LayoutElementBuilders.Layout.Builder()
                    .setRoot(tileLayout(requestParams.deviceConfiguration))
                    .build()
            )
            .build()

        return TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(singleTimelineEntry)
                    .build()
            )
            .setFreshnessIntervalMillis(0)
            .build()
    }

    private fun buildLaunchClickable(route: String): ModifiersBuilders.Clickable {
        return ModifiersBuilders.Clickable.Builder()
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        ActionBuilders.AndroidActivity.Builder()
                            .setPackageName(packageName)
                            .setClassName(MainActivity::class.java.name)
                            .addKeyToExtraMapping("route", ActionBuilders.stringExtra(route))
                            .build()
                    )
                    .build()
            )
            .build()
    }

    private fun tileLayout(deviceParameters: DeviceParameters): LayoutElementBuilders.LayoutElement {
        val calories = MacroStore.calories(this)
        val protein = MacroStore.protein(this)

        // Google Calendar style "Log food" pill button
        val logFoodClickable = buildLaunchClickable("log_food")
        val chipColors = ChipColors(
            COLOR_PRIMARY_CONTAINER,
            COLOR_ON_PRIMARY_CONTAINER,
            COLOR_ON_PRIMARY_CONTAINER,
            COLOR_ON_PRIMARY_CONTAINER
        )

        val logFoodChip = CompactChip.Builder(this, "Log food", logFoodClickable, deviceParameters)
            .setChipColors(chipColors)
            .build()

        return PrimaryLayout.Builder(deviceParameters)
            .setPrimaryLabelTextContent(
                Text.Builder(this, "Today's Macros")
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(COLOR_HEADER_TEXT)
                    .build()
            )
            .setContent(
                Text.Builder(this, "$calories kcal")
                    .setTypography(Typography.TYPOGRAPHY_DISPLAY1)
                    .setColor(ColorBuilders.argb(Color.WHITE))
                    .build()
            )
            .setSecondaryLabelTextContent(
                Text.Builder(this, "${protein}g protein")
                    .setTypography(Typography.TYPOGRAPHY_BODY1)
                    .setColor(ColorBuilders.argb(Color.LTGRAY))
                    .build()
            )
            .setPrimaryChipContent(logFoodChip)
            .build()
    }
}
