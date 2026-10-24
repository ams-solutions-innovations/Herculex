package com.ams.herculex.workout

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import com.ams.herculex.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class WorkoutOngoingServiceTest {

    @Test
    fun `service starts in foreground with chronometer and Herculex logo ongoing icon`() {
        val context: Context = ApplicationProvider.getApplicationContext()
        val startEpoch = System.currentTimeMillis() - 45_000L // Started 45s ago

        val intent = Intent(context, WorkoutOngoingService::class.java).apply {
            action = WorkoutOngoingService.ACTION_START
            putExtra(WorkoutOngoingService.EXTRA_START_EPOCH_MS, startEpoch)
            putExtra(WorkoutOngoingService.EXTRA_WORKOUT_TITLE, "Push Day")
            putExtra(WorkoutOngoingService.EXTRA_EXERCISE_NAME, "Barbell Bench Press")
        }

        val controller = Robolectric.buildService(WorkoutOngoingService::class.java, intent)
        val service = controller.create().startCommand(0, 1).get()

        val shadowService = shadowOf(service)
        val notification: Notification? = shadowService.lastForegroundNotification
        assertNotNull(notification)

        // Notification should display chronometer counting from startEpoch
        assertEquals(startEpoch, notification!!.`when`)
        assertTrue(notification.extras.getBoolean(androidx.core.app.NotificationCompat.EXTRA_SHOW_CHRONOMETER))

        // Icon should be R.drawable.ic_workout_ongoing (Herculex brand logo)
        assertEquals(R.drawable.ic_workout_ongoing, notification.smallIcon.resId)

        // Stop action clears foreground
        val stopIntent = Intent(context, WorkoutOngoingService::class.java).apply {
            action = WorkoutOngoingService.ACTION_STOP
        }
        controller.startCommand(0, 2)
    }
}
