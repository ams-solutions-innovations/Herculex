package com.ams.herculex.tile

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
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
import com.ams.herculex.R
import com.ams.herculex.workout.WorkoutStore
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.tiles.SuspendingTileService

@OptIn(ExperimentalHorologistApi::class)
class WorkoutTileService : SuspendingTileService() {

    companion object {
        private const val RESOURCES_VERSION = "3"
        private const val ID_IMAGE_LOGO = "ic_tile_logo"

        // Herculex One UI Color Palette
        private val COLOR_PRIMARY_BLUE = ColorBuilders.argb(0xFF1E44AA.toInt())    // Royal Blue container
        private val COLOR_ACCENT_BLUE  = ColorBuilders.argb(0xFF42A5F5.toInt())    // Brand Light Blue
        private val COLOR_SLATE_NAVY   = ColorBuilders.argb(0xFF202636.toInt())    // Slate Navy container
        private val COLOR_SLATE_BORDER = ColorBuilders.argb(0xFF323B52.toInt())    // Slate border
        private val COLOR_TEXT_WHITE   = ColorBuilders.argb(0xFFFFFFFF.toInt())    // White text
        private val COLOR_TEXT_MUTED   = ColorBuilders.argb(0xFFA0AABF.toInt())    // Muted slate text
        private val COLOR_TEXT_BLUE    = ColorBuilders.argb(0xFFBBDEFB.toInt())    // Soft blue text
        private val COLOR_ACTIVE_GREEN = ColorBuilders.argb(0xFF1B4D3E.toInt())    // Emerald Green container
        private val COLOR_TEXT_GREEN   = ColorBuilders.argb(0xFFA5D6A7.toInt())    // Soft green text
    }

    override suspend fun resourcesRequest(requestParams: RequestBuilders.ResourcesRequest): Resources {
        return Resources.Builder()
            .setVersion(requestParams.version)
            .addIdToImageMapping(
                ID_IMAGE_LOGO,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(
                        ResourceBuilders.AndroidImageResourceByResId.Builder()
                            .setResourceId(R.drawable.ic_tile_logo)
                            .build()
                    )
                    .build()
            )
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
        val workouts = WorkoutStore.getWorkouts(this)
        val hasActiveSession = WorkoutStore.getActiveSessionJson(this) != null

        // 1. Top Header: "HERCULEX"
        val headerTitle = Text.Builder(this, "HERCULEX")
            .setTypography(Typography.TYPOGRAPHY_CAPTION1)
            .setColor(COLOR_ACCENT_BLUE)
            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
            .build()

        val contentColumn = LayoutElementBuilders.Column.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)

        if (hasActiveSession) {
            // Active workout chip (Emerald green)
            val resumeClickable = buildLaunchClickable("active_workout")
            val resumeChip = Chip.Builder(this, resumeClickable, deviceParameters)
                .setPrimaryLabelContent("Resume Workout")
                .setSecondaryLabelContent("In Progress")
                .setChipColors(
                    ChipColors(
                        COLOR_ACTIVE_GREEN,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_GREEN
                    )
                )
                .setWidth(DimensionBuilders.expand())
                .build()

            contentColumn.addContent(resumeChip)
            contentColumn.addContent(
                LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(6f)).build()
            )

            // Quick workout pill
            val quickClickable = buildLaunchClickable("quick_workout")
            val quickChip = Chip.Builder(this, quickClickable, deviceParameters)
                .setPrimaryLabelContent("Quick Workout")
                .setChipColors(
                    ChipColors(
                        COLOR_PRIMARY_BLUE,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_BLUE
                    )
                )
                .setWidth(DimensionBuilders.expand())
                .build()

            contentColumn.addContent(quickChip)
        } else {
            // 1. Primary Action Pill: "Quick Workout"
            val quickWorkoutClickable = buildLaunchClickable("quick_workout")
            val quickWorkoutChip = Chip.Builder(this, quickWorkoutClickable, deviceParameters)
                .setPrimaryLabelContent("Quick Workout")
                .setSecondaryLabelContent("Start empty session")
                .setChipColors(
                    ChipColors(
                        COLOR_PRIMARY_BLUE,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_WHITE,
                        COLOR_TEXT_BLUE
                    )
                )
                .setWidth(DimensionBuilders.expand())
                .build()

            contentColumn.addContent(quickWorkoutChip)
            contentColumn.addContent(
                LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(6f)).build()
            )

            // 2. Secondary Action Pill: First Routine / Template or "Open Routines"
            val primaryTemplate = workouts.firstOrNull()
            if (primaryTemplate != null) {
                val templateClickable = buildLaunchClickable("workout_detail/${primaryTemplate.id}")
                val templateChip = Chip.Builder(this, templateClickable, deviceParameters)
                    .setPrimaryLabelContent(primaryTemplate.name)
                    .setSecondaryLabelContent("${primaryTemplate.exercises.size} exercises • Routine")
                    .setChipColors(
                        ChipColors(
                            COLOR_SLATE_NAVY,
                            COLOR_TEXT_WHITE,
                            COLOR_TEXT_WHITE,
                            COLOR_TEXT_MUTED
                        )
                    )
                    .setWidth(DimensionBuilders.expand())
                    .build()

                contentColumn.addContent(templateChip)
            } else {
                val routinesClickable = buildLaunchClickable("workout_list")
                val routinesChip = Chip.Builder(this, routinesClickable, deviceParameters)
                    .setPrimaryLabelContent("Open Routines")
                    .setSecondaryLabelContent("Browse workout plans")
                    .setChipColors(
                        ChipColors(
                            COLOR_SLATE_NAVY,
                            COLOR_TEXT_WHITE,
                            COLOR_TEXT_WHITE,
                            COLOR_TEXT_MUTED
                        )
                    )
                    .setWidth(DimensionBuilders.expand())
                    .build()

                contentColumn.addContent(routinesChip)
            }
        }

        val centeredContent = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(contentColumn.build())
            .build()

        // Bottom chip for "All Routines" if multiple workouts exist
        val layoutBuilder = PrimaryLayout.Builder(deviceParameters)
            .setPrimaryLabelTextContent(headerTitle)
            .setContent(centeredContent)

        if (workouts.size > 1 && !hasActiveSession) {
            val allRoutinesClickable = buildLaunchClickable("workout_list")
            val allRoutinesChip = CompactChip.Builder(
                this,
                "All Routines (${workouts.size})",
                allRoutinesClickable,
                deviceParameters
            ).setChipColors(
                ChipColors(
                    COLOR_SLATE_NAVY,
                    COLOR_TEXT_WHITE,
                    COLOR_TEXT_WHITE,
                    COLOR_TEXT_MUTED
                )
            ).build()
            layoutBuilder.setPrimaryChipContent(allRoutinesChip)
        }

        return layoutBuilder.build()
    }
}
