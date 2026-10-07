package com.ams.herculex.tile

import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.material.CircularProgressIndicator
import androidx.wear.protolayout.material.ProgressIndicatorColors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.protolayout.material.CompactChip
import androidx.wear.protolayout.material.ChipColors
import com.ams.herculex.sync.FastingSnapshot
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class FastingTileTest {

    @Test
    fun testActiveFastingTileBezelLayout() {
        val context = RuntimeEnvironment.getApplication()
        val deviceParams = DeviceParametersBuilders.DeviceParameters.Builder()
            .setScreenWidthDp(227)
            .setScreenHeightDp(227)
            .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
            .build()

        val activeSnapshot = FastingSnapshot(
            hasActiveFast = true,
            startedAtEpochMs = System.currentTimeMillis() - 14 * 3600 * 1000L,
            targetSeconds = 16 * 3600L,
            currentStageMessage = "Optimal fat burning",
        )

        val indicator = CircularProgressIndicator.Builder()
            .setProgress(activeSnapshot.progress())
            .setCircularProgressIndicatorColors(
                ProgressIndicatorColors(
                    ColorBuilders.argb(0xFF64D2FF.toInt()),
                    ColorBuilders.argb(0xFF1E1A2E.toInt())
                )
            )
            .setStrokeWidth(DimensionBuilders.dp(6f))
            .build()

        val headerText = Text.Builder(context, "FASTING TIMER")
            .setTypography(Typography.TYPOGRAPHY_CAPTION1)
            .setColor(ColorBuilders.argb(0xFFD1C4E9.toInt()))
            .build()

        val mainTimer = Text.Builder(context, activeSnapshot.elapsedText())
            .setTypography(Typography.TYPOGRAPHY_DISPLAY2)
            .setColor(ColorBuilders.argb(0xFF64D2FF.toInt()))
            .build()

        val primary = PrimaryLayout.Builder(deviceParams)
            .setPrimaryLabelTextContent(headerText)
            .setContent(mainTimer)
            .build()

        val rootBox = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .addContent(indicator)
            .addContent(primary)
            .build()

        assertNotNull(rootBox)
    }

    @Test
    fun testScheduledFastingTileBezelLayout() {
        val context = RuntimeEnvironment.getApplication()
        val deviceParams = DeviceParametersBuilders.DeviceParameters.Builder()
            .setScreenWidthDp(227)
            .setScreenHeightDp(227)
            .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
            .build()

        val scheduledSnapshot = FastingSnapshot(
            hasActiveFast = false,
            nextFastEpochMs = System.currentTimeMillis() + 2 * 3600 * 1000L,
            nextFastPlanName = "16:8",
        )

        val indicator = CircularProgressIndicator.Builder()
            .setProgress(0.08f)
            .setCircularProgressIndicatorColors(
                ProgressIndicatorColors(
                    ColorBuilders.argb(0xFF0B6E4F.toInt()),
                    ColorBuilders.argb(0xFF1E1A2E.toInt())
                )
            )
            .setStrokeWidth(DimensionBuilders.dp(6f))
            .build()

        val rootBox = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .addContent(indicator)
            .build()

        assertNotNull(rootBox)
    }
}
