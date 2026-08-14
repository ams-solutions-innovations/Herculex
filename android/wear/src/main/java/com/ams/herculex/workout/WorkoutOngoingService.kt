package com.ams.herculex.workout

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Activity
import android.app.Application
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.ams.herculex.MainActivity
import com.ams.herculex.R
import com.ams.herculex.reps.AndroidRepSensorGateway
import com.ams.herculex.reps.RepCaptureController
import com.ams.herculex.reps.RepMessageSender
import com.ams.herculex.reps.StartResult
import com.ams.herculex.sync.WearDataLayerSyncManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.runBlocking

/**
 * Sends rep-capture batches over the existing [WearDataLayerSyncManager]
 * MessageClient — no second client, and deliberately NOT
 * `sendRealtimeEvent`, whose retry queue is SharedPreferences-backed and
 * would write raw motion samples to disk (REP-04).
 *
 * Blocking is safe here: samples are delivered on
 * `AndroidRepSensorGateway`'s dedicated HandlerThread, never the main looper.
 */
private class WearRepMessageSender(context: Context) : RepMessageSender {
    private val syncManager = WearDataLayerSyncManager(context)

    override fun send(path: String, payloadJson: String): Boolean = try {
        runBlocking { syncManager.sendMessageToAllNodesReporting(path, payloadJson) }
    } catch (_: Exception) {
        false
    }
}

/**
 * Foreground service that keeps the active workout alive while the app is backgrounded.
 * Registers a Wear OS Ongoing Activity surface so a dumbbell ongoing indicator chip appears
 * at the bottom (6 o'clock) of watch faces and in system recents/launcher, allowing
 * one-tap return to the active workout screen.
 */
class WorkoutOngoingService : Service() {

    companion object {
        const val EXTRA_START_EPOCH_MS = "extra_start_epoch_ms"
        const val EXTRA_WORKOUT_TITLE = "extra_workout_title"
        const val EXTRA_EXERCISE_NAME = "extra_exercise_name"
        const val EXTRA_IS_NEW_START = "extra_is_new_start"
        const val ACTION_START = "com.ams.herculex.workout.START"
        const val ACTION_UPDATE = "com.ams.herculex.workout.UPDATE"
        const val ACTION_STOP = "STOP"

        /**
         * Rep capture starts ONLY on this explicit per-set command — never on
         * session start and never automatically (10-CONTEXT: the tracker is
         * opt-in per exercise and only ever proposes).
         */
        const val ACTION_START_REP_CAPTURE = "com.ams.herculex.reps.START_CAPTURE"
        const val ACTION_STOP_REP_CAPTURE = "com.ams.herculex.reps.STOP_CAPTURE"
        const val EXTRA_REP_EXERCISE_SLUG = "extra_rep_exercise_slug"

        private const val CHANNEL_ID = "ongoing_workout_channel"
        private const val NOTIFICATION_ID = 1204

        /**
         * The live on-wrist count for `SetLoggerScreen` to display. It is
         * **provisional** — the screen must label it as such, because the
         * authoritative count comes from the phone's Dart detector (10-04
         * owns the phone-side wording).
         */
        private val _provisionalRepCount = MutableStateFlow(0)
        val provisionalRepCount: StateFlow<Int> = _provisionalRepCount.asStateFlow()
    }

    private var startEpochMs: Long = System.currentTimeMillis()
    private var workoutTitle: String = "Active Workout"
    private var exerciseName: String? = null
    private var isNewStart: Boolean = false

    /**
     * Rep capture is hosted by THIS already-`foregroundServiceType="health"`
     * service. No second foreground service is started and no new manifest
     * permission is declared (10-CONTEXT:52-53).
     */
    private var repCapture: RepCaptureController? = null

    /**
     * Counts started activities so capture can be torn down when the app
     * goes to background. Uses the framework's own
     * `ActivityLifecycleCallbacks` rather than `ProcessLifecycleOwner`, which
     * would mean adding `androidx.lifecycle:lifecycle-process` — this plan
     * adds no Gradle dependency.
     */
    private var startedActivities: Int = 0
    private var lifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_REP_CAPTURE -> {
                startRepCapture(intent.getStringExtra(EXTRA_REP_EXERCISE_SLUG).orEmpty())
                return START_STICKY
            }
            ACTION_STOP_REP_CAPTURE -> {
                repCapture?.stop(RepCaptureController.REASON_USER)
                return START_STICKY
            }
        }

        if (intent?.action == ACTION_STOP) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.hasExtra(EXTRA_START_EPOCH_MS) == true) {
            startEpochMs = intent.getLongExtra(EXTRA_START_EPOCH_MS, System.currentTimeMillis())
        }
        if (intent?.hasExtra(EXTRA_WORKOUT_TITLE) == true) {
            workoutTitle = intent.getStringExtra(EXTRA_WORKOUT_TITLE) ?: "Active Workout"
        }
        if (intent?.hasExtra(EXTRA_EXERCISE_NAME) == true) {
            exerciseName = intent.getStringExtra(EXTRA_EXERCISE_NAME)
        }
        isNewStart = intent?.getBooleanExtra(EXTRA_IS_NEW_START, false) == true

        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        isNewStart = false
        return START_STICKY
    }

    /**
     * Starts capture for one specific set. Returns silently on a typed
     * refusal (low battery, no sensor, already capturing) — a refusal
     * registers no listener, so the register/unregister accounting stays
     * balanced.
     */
    private fun startRepCapture(exerciseSlug: String) {
        val sensorManager = getSystemService(SensorManager::class.java) ?: return
        val controller = repCapture ?: RepCaptureController(
            sensors = AndroidRepSensorGateway(sensorManager),
            sender = WearRepMessageSender(applicationContext),
            batteryLevelPercent = { readBatteryPercent() },
            clock = { System.currentTimeMillis() },
            onProvisionalRep = { _provisionalRepCount.value = it },
        ).also { repCapture = it }

        _provisionalRepCount.value = 0
        val result = controller.start(exerciseSlug)
        if (result is StartResult.Started) {
            observeAppBackground()
        }
    }

    private fun readBatteryPercent(): Int {
        val manager = getSystemService(BatteryManager::class.java) ?: return 100
        return manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    /**
     * The app-background teardown path. Registered lazily on the first
     * capture and unregistered in [onDestroy], so it never outlives the
     * service.
     */
    private fun observeAppBackground() {
        if (lifecycleCallbacks != null) return
        val application = application ?: return

        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                startedActivities += 1
            }

            override fun onActivityStopped(activity: Activity) {
                startedActivities -= 1
                if (startedActivities <= 0) {
                    startedActivities = 0
                    repCapture?.stop(RepCaptureController.REASON_BACKGROUND)
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        }

        application.registerActivityLifecycleCallbacks(callbacks)
        lifecycleCallbacks = callbacks
    }

    override fun onDestroy() {
        // Fifth teardown path. stop() is idempotent, so this is safe even
        // when the set already ended normally.
        repCapture?.onServiceDestroyed()
        repCapture = null
        lifecycleCallbacks?.let { application?.unregisterActivityLifecycleCallbacks(it) }
        lifecycleCallbacks = null
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val touchIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("open_active_workout", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val bodyText = if (!exerciseName.isNullOrBlank()) {
            "$workoutTitle • $exerciseName"
        } else {
            "$workoutTitle in progress"
        }

        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(workoutTitle)
            .setContentText(bodyText)
            .setSmallIcon(R.drawable.ic_workout_ongoing)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setContentIntent(touchIntent)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setSilent(!isNewStart)

        // Status.StopwatchPart renders a live count-up timer from startEpochMs —
        // the system refreshes it on its own without requiring periodic polling.
        val statusText = if (!exerciseName.isNullOrBlank()) {
            "$exerciseName • #elapsed#"
        } else {
            "$workoutTitle • #elapsed#"
        }

        val status = Status.Builder()
            .addTemplate(statusText)
            .addPart("elapsed", Status.StopwatchPart(startEpochMs))
            .build()

        OngoingActivity.Builder(this, NOTIFICATION_ID, notificationBuilder)
            .setAnimatedIcon(R.drawable.ic_workout_ongoing)
            .setStaticIcon(R.drawable.ic_workout_ongoing)
            .setTouchIntent(touchIntent)
            .setStatus(status)
            .build()
            .apply(this)

        return notificationBuilder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ongoing Workout",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows live ongoing workout status on watch face and recents"
                setSound(null, null)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
