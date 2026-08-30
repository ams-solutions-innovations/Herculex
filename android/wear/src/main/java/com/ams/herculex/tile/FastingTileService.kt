package com.ams.herculex.tile

import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders.Resources
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.Chip
import androidx.wear.protolayout.material.ChipColors
import androidx.wear.protolayout.material.CompactChip
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.ams.herculex.MainActivity
import com.ams.herculex.sync.FastingStore
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.tiles.SuspendingTileService

@OptIn(ExperimentalHorologistApi::class)
class FastingTileService : SuspendingTileService() {

    companion object {
        private const val RESOURCES_VERSION = "1"

        // Herculex Fasting Violet / Indigo & Emerald Color Palette
        private val COLOR_HEADER_VIOLET    = ColorBuilders.argb(0xFFD1C4E9.toInt()) // Soft light violet header
        private val COLOR_PRIMARY_EMERALD  = ColorBuilders.argb(0xFF0B6E4F.toInt()) // Emerald Green for Start Fast
        private val COLOR_ACTIVE_CONTAINER = ColorBuilders.argb(0xFF2C1E4A.toInt()) // Deep violet container
        private val COLOR_ACCENT_CYAN      = ColorBuilders.argb(0xFF64D2FF.toInt()) // Cyan accent text
        private val COLOR_TEXT_WHITE       = ColorBuilders.argb(0xFFFFFFFF.toInt()) // Pure white
        private val COLOR_TEXT_MUTED       = ColorBuilders.argb(0xFFA0AABF.toInt()) // Muted slate text
    }

    override suspend fun resourcesRequest(requestParams: RequestBuilders.ResourcesRequest): Resources {
        return Resources.Builder()
            .setVersion(requestParams.version)
            .build()
    }

    override suspend fun tileRequest(requestParams: RequestBuilders.TileRequest): TileBuilders.Tile {
        val snapshot = FastingStore.snapshot(this)
        val singleTimelineEntry = TimelineBuilders.TimelineEntry.Builder()
            .setLayout(
                LayoutElementBuilders.Layout.Builder()
                    .setRoot(tileLayout(requestParams.deviceConfiguration, snapshot))
                    .build()
            )
            .build()

        val tileBuilder = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(singleTimelineEntry)
                    .build()
            )

        // When fast is active, refresh every 60 seconds so the timer stays current
        if (snapshot.hasActiveFast) {
            tileBuilder.setFreshnessIntervalMillis(60_000L)
        } else {
            tileBuilder.setFreshnessIntervalMillis(0L)
        }

        return tileBuilder.build()
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

    private fun tileLayout(
        deviceParameters: DeviceParameters,
        snapshot: com.ams.herculex.sync.FastingSnapshot,
    ): LayoutElementBuilders.LayoutElement {
        val now = System.currentTimeMillis()
        val openFastingClickable = buildLaunchClickable("fasting")

        return if (snapshot.hasActiveFast) {
            val elapsedText = snapshot.elapsedText(now)
            val progressPercent = (snapshot.progress(now) * 100).toInt()
            val targetHours = snapshot.targetSeconds / 3600L

            val headerText = Text.Builder(this, "FASTING TIMER")
                .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                .setColor(COLOR_HEADER_VIOLET)
                .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                .build()

            val timerValue = Text.Builder(this, elapsedText)
                .setTypography(Typography.TYPOGRAPHY_DISPLAY2)
                .setColor(COLOR_ACCENT_CYAN)
                .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                .build()

            val subText = Text.Builder(this, "Target: ${targetHours}h • $progressPercent%")
                .setTypography(Typography.TYPOGRAPHY_BODY2)
                .setColor(COLOR_TEXT_MUTED)
                .build()

            val centerContent = LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                .addContent(timerValue)
                .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(2f)).build())
                .addContent(subText)
                .build()

            val manageChip = CompactChip.Builder(
                this,
                "Open Timer",
                openFastingClickable,
                deviceParameters,
            ).setChipColors(
                ChipColors(
                    COLOR_ACTIVE_CONTAINER,
                    COLOR_TEXT_WHITE,
                    COLOR_TEXT_WHITE,
                    COLOR_HEADER_VIOLET,
                )
            ).build()

            PrimaryLayout.Builder(deviceParameters)
                .setPrimaryLabelTextContent(headerText)
                .setContent(centerContent)
                .setPrimaryChipContent(manageChip)
                .build()
        } else {
            val headerText = Text.Builder(this, "FASTING")
                .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                .setColor(COLOR_HEADER_VIOLET)
                .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                .build()

            val quickFastClickable = buildLaunchClickable("fasting")
            val lastFastSecs = snapshot.lastFastDurationSeconds
            val quickFastSubtitle = if (lastFastSecs != null) {
                val h = lastFastSecs / 3600L
                val m = (lastFastSecs % 3600L) / 60L
                "Last fast: ${h}h ${m}m"
            } else {
                "Quick start"
            }

            val quickFastChip = Chip.Builder(this, quickFastClickable, deviceParameters)
                .setPrimaryLabelContent("16:8 Fast")
                .setSecondaryLabelContent(quickFastSubtitle)
                .setChipColors(
                    ChipColors(
                        COLOR_PRIMARY_EMERALD,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_WHITE,
                        COLOR_HEADER_VIOLET,
                    )
                )
                .setWidth(DimensionBuilders.expand())
                .build()

            val otherFastsClickable = buildLaunchClickable("fasting")
            val otherFastsChip = CompactChip.Builder(
                this,
                "Other Fasts",
                otherFastsClickable,
                deviceParameters
            ).setChipColors(
                ChipColors(
                    COLOR_ACTIVE_CONTAINER,
                    COLOR_TEXT_WHITE,
                    COLOR_TEXT_WHITE,
                    COLOR_TEXT_MUTED,
                )
            ).build()

            PrimaryLayout.Builder(deviceParameters)
                .setPrimaryLabelTextContent(headerText)
                .setContent(quickFastChip)
                .setPrimaryChipContent(otherFastsChip)
                .build()
        }
    }
}
