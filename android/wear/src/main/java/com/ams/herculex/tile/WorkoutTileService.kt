package com.ams.herculex.tile

import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.ResourceBuilders.Resources
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.ams.herculex.MainActivity
import com.ams.herculex.R
import com.ams.herculex.workout.WorkoutStore
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.tiles.SuspendingTileService

/// Workout quick-start tile. Mirrors the watch app's Workouts list (One UI
/// stadium pills with a round badge, bold title, muted subtitle): today's
/// program workout as the big pill, the other routines as smaller ones below,
/// each a single tap away from a running session.
@OptIn(ExperimentalHorologistApi::class)
class WorkoutTileService : SuspendingTileService() {

    /// Colours of one pill, matching `OneUiPillStyle` in the app.
    private class PillStyle(
        val container: ColorBuilders.ColorProp,
        val badge: ColorBuilders.ColorProp,
        val secondary: ColorBuilders.ColorProp,
        val border: ColorBuilders.ColorProp? = null,
    )

    companion object {
        private const val RESOURCES_VERSION = "3"
        private const val ID_IMAGE_LOGO = "ic_tile_logo"

        private val COLOR_ACCENT_BLUE = ColorBuilders.argb(0xFF42A5F5.toInt())     // Brand Light Blue
        private val COLOR_TEXT_WHITE  = ColorBuilders.argb(0xFFFFFFFF.toInt())
        private val COLOR_TEXT_MUTED  = ColorBuilders.argb(0xFFA0AABF.toInt())

        private val ROYAL_BLUE = PillStyle(
            container = ColorBuilders.argb(0xFF1E44AA.toInt()),
            badge = ColorBuilders.argb(0xFF132E78.toInt()),
            secondary = ColorBuilders.argb(0xFFC0CCEC.toInt()),
        )
        private val SLATE_NAVY = PillStyle(
            container = ColorBuilders.argb(0xFF202636.toInt()),
            badge = ColorBuilders.argb(0xFF141926.toInt()),
            secondary = ColorBuilders.argb(0xFFA0AABF.toInt()),
            border = ColorBuilders.argb(0xFF323B52.toInt()),
        )
        private val EMERALD = PillStyle(
            container = ColorBuilders.argb(0xFF1B4D3E.toInt()),
            badge = ColorBuilders.argb(0xFF113329.toInt()),
            secondary = ColorBuilders.argb(0xFFA5D6A7.toInt()),
        )

        // A tile cannot scroll, so this is the whole vertical budget on a
        // round face: header + big pill + two small pills + a link.
        private const val BIG_HEIGHT_DP = 48f
        private const val BIG_BADGE_DP = 34f
        private const val SMALL_HEIGHT_DP = 32f
        private const val SMALL_BADGE_DP = 24f
        private const val GAP_DP = 3f
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
            // "Today" changes at midnight; re-render so a stale one drops out
            // even if the phone never got to push a replacement.
            .setFreshnessIntervalMillis(30 * 60 * 1000L)
            .setTileTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(singleTimelineEntry)
                    .build()
            )
            .build()
    }

    private fun buildLaunchClickable(id: String, route: String): ModifiersBuilders.Clickable {
        return ModifiersBuilders.Clickable.Builder()
            .setId(id)
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
        val today = WorkoutStore.getToday(this)
        val hasActiveSession = WorkoutStore.getActiveSessionJson(this) != null

        // Narrower than the face: the circle closes in at top and bottom.
        val screenDp = deviceParameters.screenWidthDp.toFloat()
        val bigWidth = screenDp * 0.78f
        val smallWidth = screenDp * 0.72f

        val column = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)

        column.addContent(
            Text.Builder(this, "HERCULEX")
                .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                .setColor(COLOR_ACCENT_BLUE)
                .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                .build()
        )
        column.addContent(gap())

        if (hasActiveSession) {
            column.addContent(
                pill(
                    width = bigWidth,
                    height = BIG_HEIGHT_DP,
                    badgeSize = BIG_BADGE_DP,
                    style = EMERALD,
                    badgeGlyph = "▶",
                    title = "Resume Workout",
                    subtitle = "In progress",
                    clickable = buildLaunchClickable("tile_resume", "active_workout"),
                )
            )
        } else {
            if (today != null) {
                column.addContent(
                    pill(
                        width = bigWidth,
                        height = BIG_HEIGHT_DP,
                        badgeSize = BIG_BADGE_DP,
                        style = ROYAL_BLUE,
                        badgeGlyph = "▶",
                        title = today.title,
                        subtitle = "Today · ${today.workout.exercises.size} exercises",
                        clickable = buildLaunchClickable(
                            "tile_today",
                            "start_workout/${today.workout.id}",
                        ),
                    )
                )
                column.addContent(gap())
            }

            // Today's own entry sits first in [workouts]; skip it rather than
            // listing it twice.
            workouts
                .filter { it.id != today?.workout?.id }
                .take(if (today != null) 2 else 3)
                .forEach { workout ->
                    column.addContent(
                        pill(
                            width = smallWidth,
                            height = SMALL_HEIGHT_DP,
                            badgeSize = SMALL_BADGE_DP,
                            style = SLATE_NAVY,
                            badgeGlyph = "🏋",
                            title = workout.name,
                            subtitle = "${workout.exercises.size} exercises",
                            clickable = buildLaunchClickable(
                                "tile_w_${workout.id}",
                                "start_workout/${workout.id}",
                            ),
                        )
                    )
                    column.addContent(gap())
                }
        }

        column.addContent(
            allWorkoutsLink(
                "All Workouts (${workouts.size})",
                buildLaunchClickable("tile_all", "workout_list"),
            )
        )

        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(column.build())
            .build()
    }

    private fun gap(): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Spacer.Builder()
            .setHeight(DimensionBuilders.dp(GAP_DP))
            .build()

    /// Plain muted text that opens the full list.
    private fun allWorkoutsLink(
        text: String,
        clickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setHeight(DimensionBuilders.dp(18f))
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(clickable)
                    .build()
            )
            .addContent(
                Text.Builder(this, text)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION3)
                    .setColor(COLOR_TEXT_MUTED)
                    .setMaxLines(1)
                    .build()
            )
            .build()

    /// One stadium pill: round badge on the left, bold title over a muted
    /// subtitle, like `OneUiPill` in the app.
    private fun pill(
        width: Float,
        height: Float,
        badgeSize: Float,
        style: PillStyle,
        badgeGlyph: String,
        title: String,
        subtitle: String,
        clickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        val isBig = height >= BIG_HEIGHT_DP
        val padStart = if (isBig) 7f else 4f
        val padEnd = if (isBig) 12f else 10f
        val spacer = if (isBig) 8f else 6f
        val textWidth = width - padStart - padEnd - badgeSize - spacer

        val badge = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(badgeSize))
            .setHeight(DimensionBuilders.dp(badgeSize))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(style.badge)
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(badgeSize / 2f))
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .addContent(
                Text.Builder(this, badgeGlyph)
                    .setTypography(
                        if (isBig) Typography.TYPOGRAPHY_CAPTION1 else Typography.TYPOGRAPHY_CAPTION3
                    )
                    .setColor(COLOR_TEXT_WHITE)
                    .build()
            )
            .build()

        val texts = LayoutElementBuilders.Column.Builder()
            .setWidth(DimensionBuilders.dp(textWidth))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
            .addContent(
                Text.Builder(this, title)
                    .setTypography(
                        if (isBig) Typography.TYPOGRAPHY_CAPTION1 else Typography.TYPOGRAPHY_CAPTION2
                    )
                    .setColor(COLOR_TEXT_WHITE)
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                    .setMaxLines(1)
                    .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
                    .build()
            )
            .addContent(
                Text.Builder(this, subtitle)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION3)
                    .setColor(style.secondary)
                    .setMaxLines(1)
                    .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
                    .build()
            )
            .build()

        val modifiers = ModifiersBuilders.Modifiers.Builder()
            .setBackground(
                ModifiersBuilders.Background.Builder()
                    .setColor(style.container)
                    .setCorner(
                        ModifiersBuilders.Corner.Builder()
                            .setRadius(DimensionBuilders.dp(height / 2f))
                            .build()
                    )
                    .build()
            )
            .setPadding(
                ModifiersBuilders.Padding.Builder()
                    .setStart(DimensionBuilders.dp(padStart))
                    .setEnd(DimensionBuilders.dp(padEnd))
                    .build()
            )
            .setClickable(clickable)
        style.border?.let {
            modifiers.setBorder(
                ModifiersBuilders.Border.Builder()
                    .setWidth(DimensionBuilders.dp(1f))
                    .setColor(it)
                    .build()
            )
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(width))
            .setHeight(DimensionBuilders.dp(height))
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(modifiers.build())
            .addContent(
                LayoutElementBuilders.Row.Builder()
                    .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                    .addContent(badge)
                    .addContent(
                        LayoutElementBuilders.Spacer.Builder()
                            .setWidth(DimensionBuilders.dp(spacer))
                            .build()
                    )
                    .addContent(texts)
                    .build()
            )
            .build()
    }
}
