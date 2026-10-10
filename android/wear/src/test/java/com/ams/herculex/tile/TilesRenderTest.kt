package com.ams.herculex.tile

import android.content.Context
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.StateBuilders
import androidx.wear.tiles.RequestBuilders
import com.ams.herculex.tile.kit.HxTileService
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.workout.WorkoutStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * Builds every tile the way the host does and serialises it to proto, which is
 * where an invalid layout (bad dynamic text, missing constraint, null prop)
 * would throw. The old FastingTileTest only constructed Material widgets and
 * never touched the real services.
 */
@RunWith(RobolectricTestRunner::class)
class TilesRenderTest {

    private val context: Context get() = RuntimeEnvironment.getApplication()

    private fun request(): RequestBuilders.TileRequest =
        RequestBuilders.TileRequest.Builder()
            .setDeviceConfiguration(
                DeviceParametersBuilders.DeviceParameters.Builder()
                    .setScreenWidthDp(227).setScreenHeightDp(227)
                    .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND).build()
            )
            .setCurrentState(StateBuilders.State.Builder().build())
            .build()

    private fun <T : HxTileService> render(service: Class<T>) {
        val tile = Robolectric.buildService(service).create().get()
        val result = runBlocking { tile.tileRequest(request()) }
        assertNotNull(result)
        // toProto() walks the whole tree; it throws on an invalid builder state.
        val proto = result.toProto()
        assertTrue(proto.tileTimeline.timelineEntriesCount > 0)
    }

    @Test fun macrosRendersEmptyAndFilled() {
        render(MacrosTileService::class.java)
        MacroStore.save(context, 1420, 98, 142, 41, "9h 0m")
        render(MacrosTileService::class.java)
    }

    @Test fun fastingRenders() = render(FastingTileService::class.java)

    @Test fun waterRenders() = render(WaterTileService::class.java)

    @Test fun workoutRenders() = render(WorkoutTileService::class.java)

    @Test fun volumeRendersEmptyAndFilled() {
        render(WeeklyVolumeTileService::class.java)
        MacroStore.saveWeeklyVolume(
            context, 12400.0, 86,
            """[{"muscle":"Chest","tonnage":4100.0,"sets":14.0},{"muscle":"Back","tonnage":3600.0,"sets":16.0},
               {"muscle":"Legs","tonnage":2900.0,"sets":12.0},{"muscle":"Shoulders","tonnage":1200.0,"sets":9.0},
               {"muscle":"Arms","tonnage":600.0,"sets":8.0}]""",
        )
        render(WeeklyVolumeTileService::class.java)
    }

    @Test fun workoutTileListsScheduledWorkoutFirst() {
        WorkoutStore.saveJson(
            context,
            """[{"id":"1","name":"Pull Day","exercises":[]},
               {"id":"scheduled_9","name":"Push A","scheduledToday":true,"scheduleTitle":"Push A","exercises":[]}]""",
        )
        assertEquals("scheduled_9", WorkoutStore.getWorkoutsScheduledFirst(context).first().id)
        render(WorkoutTileService::class.java)
    }

    @Test fun waterTapIsCountedOnceEvenIfTheHostResendsIt() {
        val tile = Robolectric.buildService(WaterTileService::class.java).create().get()
        val sent = mutableListOf<String>()
        tile.sendToPhone = { sent += it }
        val before = MacroStore.water(context)
        runBlocking {
            tile.consumeClick("water_250:1")
            assertEquals(before + 250, MacroStore.water(context))
            tile.consumeClick("water_250:1") // a refresh re-sends the old click
            assertEquals(before + 250, MacroStore.water(context))
            tile.consumeClick("water_500:2") // a real later tap
            assertEquals(before + 750, MacroStore.water(context))
            assertEquals(2, sent.size)
            assertTrue(sent.all { """"kind":"water"""" in it })
            tile.consumeClick("water_250") // id from a pre-stamp layout: ignored
            assertEquals(before + 750, MacroStore.water(context))
        }
    }
}
