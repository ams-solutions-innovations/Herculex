package com.ams.herculex.complication

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.util.Log
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.GoalProgressComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.ams.herculex.tile.FastingTileService
import com.ams.herculex.tile.MacrosTileService
import com.ams.herculex.tile.WaterTileService
import com.ams.herculex.tile.WeeklyVolumeTileService
import com.ams.herculex.tile.WorkoutTileService

object WearComplicationHelper {
    private const val TAG = "WearComplicationHelper"

    private val ALL_COMPLICATIONS = listOf(
        CaloriesComplicationService::class.java,
        ProteinComplicationService::class.java,
        CarbsComplicationService::class.java,
        FatsComplicationService::class.java,
        FastingComplicationService::class.java,
        CnsComplicationService::class.java,
        WaterComplicationService::class.java,
        WeeklyVolumeComplicationService::class.java,
        WeeklySetsComplicationService::class.java,
        RamblerComplicationService::class.java,
    )

    private val NUTRITION_COMPLICATIONS = listOf(
        CaloriesComplicationService::class.java,
        ProteinComplicationService::class.java,
        CarbsComplicationService::class.java,
        FatsComplicationService::class.java,
        WaterComplicationService::class.java,
    )

    fun requestNutritionComplicationsUpdate(context: Context) {
        val appCtx = context.applicationContext
        try {
            for (service in NUTRITION_COMPLICATIONS) {
                ComplicationDataSourceUpdateRequester
                    .create(appCtx, ComponentName(appCtx, service))
                    .requestUpdateAll()
            }
            TileService.getUpdater(appCtx).requestUpdate(MacrosTileService::class.java)
            TileService.getUpdater(appCtx).requestUpdate(WaterTileService::class.java)
            Log.d(TAG, "Requested nutrition complications & tile update")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update nutrition complications", e)
        }
    }

    fun requestFastingComplicationsUpdate(context: Context) {
        val appCtx = context.applicationContext
        try {
            ComplicationDataSourceUpdateRequester
                .create(appCtx, ComponentName(appCtx, FastingComplicationService::class.java))
                .requestUpdateAll()
            TileService.getUpdater(appCtx).requestUpdate(FastingTileService::class.java)
            Log.d(TAG, "Requested fasting complication & tile update")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update fasting complication", e)
        }
    }

    fun requestCnsComplicationsUpdate(context: Context) {
        val appCtx = context.applicationContext
        try {
            ComplicationDataSourceUpdateRequester
                .create(appCtx, ComponentName(appCtx, CnsComplicationService::class.java))
                .requestUpdateAll()
            Log.d(TAG, "Requested CNS complication update")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update CNS complication", e)
        }
    }

    fun requestAllComplicationsUpdate(context: Context) {
        val appCtx = context.applicationContext
        try {
            for (service in ALL_COMPLICATIONS) {
                ComplicationDataSourceUpdateRequester
                    .create(appCtx, ComponentName(appCtx, service))
                    .requestUpdateAll()
            }
            TileService.getUpdater(appCtx).requestUpdate(MacrosTileService::class.java)
            TileService.getUpdater(appCtx).requestUpdate(FastingTileService::class.java)
            TileService.getUpdater(appCtx).requestUpdate(WorkoutTileService::class.java)
            TileService.getUpdater(appCtx).requestUpdate(WaterTileService::class.java)
            TileService.getUpdater(appCtx).requestUpdate(WeeklyVolumeTileService::class.java)
            Log.d(TAG, "Requested all complications & tiles update")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update all complications", e)
        }
    }

    fun formatCalories(calories: Float, locale: java.util.Locale = java.util.Locale.getDefault()): String {
        val cal = maxOf(0, calories.toInt())
        return java.text.NumberFormat.getIntegerInstance(locale).format(cal)
    }

    /**
     * Builds complication data supporting progress bars (GOAL_PROGRESS and RANGED_VALUE)
     * as well as standard SHORT_TEXT fallback.
     *
     * IMPORTANT: For GOAL_PROGRESS and RANGED_VALUE, [title] is intentionally omitted (null).
     * On Wear OS Watch Face Format / Samsung Galaxy Watch curved bezel slots, providing both
     * [title] and [text] causes the watch face renderer to concatenate them with a slash
     * ("$title / $text", e.g. "kcal / 1.4k" or "P / 122g"), which overflows the curved text
     * bounding box and gets truncated (e.g. "kcal /." or "P / 12...").
     * Omitting [title] on progress complications matches native complications like Steps (shoe + "1,807")
     * and Battery ("44%"), allowing the full whole-number value to be displayed cleanly.
     * For SHORT_TEXT (circular complication slots), [title] is preserved for the 2-line header layout.
     */
    fun buildProgressComplicationData(
        context: Context,
        type: ComplicationType,
        current: Float,
        min: Float = 0f,
        max: Float,
        text: String? = null,
        title: String? = null,
        shortTextFallback: String? = null,
        shortTextTitle: String? = null,
        description: String,
        pendingIntent: PendingIntent? = null,
        iconResId: Int? = null,
    ): ComplicationData? {
        val safeMax = maxOf(max, min + 1f)
        val clamped = current.coerceIn(min, safeMax)
        val monochromaticImage = iconResId?.let { resId ->
            runCatching {
                val icon = Icon.createWithResource(context, resId)
                MonochromaticImage.Builder(icon).build()
            }.getOrNull()
        }

        val resolvedText = text ?: shortTextFallback

        return when (type) {
            ComplicationType.GOAL_PROGRESS -> {
                val builder = GoalProgressComplicationData.Builder(
                    value = current.coerceAtLeast(min),
                    targetValue = safeMax,
                    contentDescription = PlainComplicationText.Builder(description).build()
                )
                resolvedText?.let { builder.setText(PlainComplicationText.Builder(it).build()) }
                // title omitted on purpose to avoid "$title / $text" bezel concatenation
                monochromaticImage?.let { builder.setMonochromaticImage(it) }
                pendingIntent?.let { builder.setTapAction(it) }
                builder.build()
            }
            ComplicationType.RANGED_VALUE -> {
                val builder = RangedValueComplicationData.Builder(
                    value = clamped,
                    min = min,
                    max = safeMax,
                    contentDescription = PlainComplicationText.Builder(description).build()
                )
                resolvedText?.let { builder.setText(PlainComplicationText.Builder(it).build()) }
                // title omitted on purpose to avoid "$title / $text" bezel concatenation
                monochromaticImage?.let { builder.setMonochromaticImage(it) }
                pendingIntent?.let { builder.setTapAction(it) }
                builder.build()
            }
            ComplicationType.SHORT_TEXT -> {
                val displayText = shortTextFallback ?: text ?: title ?: ""
                val builder = ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder(displayText).build(),
                    contentDescription = PlainComplicationText.Builder(description).build()
                )
                val displayTitle = shortTextTitle ?: title
                displayTitle?.let { builder.setTitle(PlainComplicationText.Builder(it).build()) }
                monochromaticImage?.let { builder.setMonochromaticImage(it) }
                pendingIntent?.let { builder.setTapAction(it) }
                builder.build()
            }
            else -> null
        }
    }
}
