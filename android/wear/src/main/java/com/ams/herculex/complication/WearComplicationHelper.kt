package com.ams.herculex.complication

import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.ams.herculex.tile.FastingTileService
import com.ams.herculex.tile.MacrosTileService
import com.ams.herculex.tile.WorkoutTileService

object WearComplicationHelper {
    private const val TAG = "WearComplicationHelper"

    private val ALL_COMPLICATIONS = listOf(
        CaloriesComplicationService::class.java,
        ProteinComplicationService::class.java,
        CarbsComplicationService::class.java,
        FatsComplicationService::class.java,
        FastingComplicationService::class.java,
        WeeklyVolumeComplicationService::class.java,
        WeeklySetsComplicationService::class.java,
        RamblerComplicationService::class.java,
    )

    private val NUTRITION_COMPLICATIONS = listOf(
        CaloriesComplicationService::class.java,
        ProteinComplicationService::class.java,
        CarbsComplicationService::class.java,
        FatsComplicationService::class.java,
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
            Log.d(TAG, "Requested all complications & tiles update")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update all complications", e)
        }
    }
}
