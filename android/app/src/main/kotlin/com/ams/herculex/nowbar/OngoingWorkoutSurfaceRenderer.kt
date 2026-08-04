package com.ams.herculex.nowbar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ams.herculex.MainActivity
import com.ams.herculex.R

interface OngoingWorkoutSurfaceRenderer {
    fun show(
        snapshot: OngoingWorkoutSurfaceSnapshot,
        actionPendingIntents: Map<String, PendingIntent>,
    )

    fun clear()

    fun diagnostics(): Map<String, Any?>
}

class AndroidOngoingWorkoutSurfaceRenderer(
    context: Context,
    private val capability: LiveUpdatesCapability,
) : OngoingWorkoutSurfaceRenderer {
    private val appContext = context.applicationContext
    private val notificationManager =
        appContext.getSystemService(NotificationManager::class.java)
    private var lastDiagnostics: Map<String, Any?> = mapOf(
        "posted" to false,
        "requestedPromotedOngoing" to false,
        "hasPromotableCharacteristics" to false,
        "systemMarkedPromotedOngoing" to false,
        "style" to if (capability.isPlatformSupported) "ProgressStyle" else "BigTextStyle",
        "shortCriticalText" to null,
        "actionCount" to 0,
        "rowCount" to 0,
        "controlCount" to 0,
        "notificationsEnabled" to capability.areNotificationsEnabled(),
        "channelImportance" to null,
        "category" to NotificationCompat.CATEGORY_WORKOUT,
        "priority" to "low",
        "visibility" to "private",
        "ongoing" to true,
        "ongoingEventFlag" to false,
        "usesChronometer" to true,
    )

    override fun show(
        snapshot: OngoingWorkoutSurfaceSnapshot,
        actionPendingIntents: Map<String, PendingIntent>,
    ) {
        ensureChannel()

        val usePromotedPath = capability.isPlatformSupported
        val shortCriticalText = if (usePromotedPath) shortCriticalTextFor(snapshot) else null
        val style = if (usePromotedPath) "ProgressStyle" else "BigTextStyle"

        val notification = if (usePromotedPath) {
            buildPromotedNotification(snapshot, actionPendingIntents, shortCriticalText)
        } else {
            buildCompatNotification(snapshot, actionPendingIntents)
        }.apply {
            flags = flags or Notification.FLAG_ONGOING_EVENT
        }

        val requestedPromotedOngoing = usePromotedPath
        val hasPromotableCharacteristics = notification.hasPromotableCharacteristicsOrFalse()

        val notifySucceeded = runCatching {
            notificationManager.notify(NOTIFICATION_ID, notification)
        }.onFailure { error ->
            Log.w(TAG, "Unable to show promoted workout surface", error)
        }.isSuccess
        val systemMarkedPromotedOngoing = activeNotificationIsPromotedOngoing()
        val ongoingEventFlag =
            notification.flags and Notification.FLAG_ONGOING_EVENT == Notification.FLAG_ONGOING_EVENT
        Log.d(
            TAG,
            "Posted ${snapshot.collapsed.title} with ${actionPendingIntents.size} actions; " +
                "posted=$notifySucceeded " +
                "requestedPromoted=$requestedPromotedOngoing " +
                "promotable=$hasPromotableCharacteristics " +
                "systemPromoted=$systemMarkedPromotedOngoing; ${capability.summary()}",
        )
        Log.i(
            TAG,
            "diagnostics event=posted surface=${snapshot.surfaceId} session=${snapshot.sessionId} " +
                "title=\"${snapshot.collapsed.title}\" value=\"${snapshot.collapsed.value}\" " +
                "actions=${actionPendingIntents.size} rows=${snapshot.expanded.rows.size} " +
                "controls=${snapshot.expanded.controls.size} " +
                "posted=$notifySucceeded notificationsEnabled=${capability.areNotificationsEnabled()} " +
                "channelImportance=${channelImportanceName()} " +
                "style=$style shortCriticalText=\"${shortCriticalText ?: ""}\" " +
                "requestedPromoted=$requestedPromotedOngoing " +
                "promotable=$hasPromotableCharacteristics " +
                "systemPromoted=$systemMarkedPromotedOngoing " +
                "canPostPromoted=${capability.canPostPromotedNotifications()}",
        )
        lastDiagnostics = mapOf(
            "posted" to notifySucceeded,
            "requestedPromotedOngoing" to requestedPromotedOngoing,
            "hasPromotableCharacteristics" to hasPromotableCharacteristics,
            "systemMarkedPromotedOngoing" to systemMarkedPromotedOngoing,
            "style" to style,
            "shortCriticalText" to shortCriticalText,
            "actionCount" to actionPendingIntents.size,
            "rowCount" to snapshot.expanded.rows.size,
            "controlCount" to snapshot.expanded.controls.size,
            "notificationsEnabled" to capability.areNotificationsEnabled(),
            "channelImportance" to channelImportance(),
            "channelImportanceName" to channelImportanceName(),
            "category" to NotificationCompat.CATEGORY_WORKOUT,
            "priority" to "low",
            "visibility" to "private",
            "ongoing" to true,
            "ongoingEventFlag" to ongoingEventFlag,
            "usesChronometer" to true,
            "canPostPromotedNotifications" to capability.canPostPromotedNotifications(),
        )
    }

    override fun clear() {
        notificationManager.cancel(NOTIFICATION_ID)
        lastDiagnostics = lastDiagnostics.toMutableMap().apply {
            put("posted", false)
        }
        Log.d(TAG, "Cleared workout surface notification")
    }

    override fun diagnostics(): Map<String, Any?> = lastDiagnostics

    /**
     * Android 16 (API 36) Live Update path. Uses the platform [Notification.Builder]
     * rather than [NotificationCompat.Builder] because the bundled androidx version does
     * not expose [Notification.Builder.requestPromotedOngoing], [Notification.ProgressStyle]
     * or [Notification.Builder.setShortCriticalText].
     *
     * `setLocalOnly` and `setSilent` are deliberately absent — both can disqualify a
     * notification from being promoted into the Now Bar.
     */
    @android.annotation.TargetApi(ANDROID_16_API)
    private fun buildPromotedNotification(
        snapshot: OngoingWorkoutSurfaceSnapshot,
        actionPendingIntents: Map<String, PendingIntent>,
        shortCriticalText: String?,
    ): Notification {
        val counter = parseSetCounter(snapshot)
        val totalSegments = counter?.total?.takeIf { total -> total > 0 } ?: 1
        val progress = (counter?.current ?: 1).coerceIn(0, totalSegments)

        val progressStyle = Notification.ProgressStyle()
            .setProgressSegments(
                (0 until totalSegments).map { Notification.ProgressStyle.Segment(1) },
            )
            .setProgress(progress)

        val builder = Notification.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(snapshot.collapsed.title)
            .setContentText(compactContent(snapshot))
            .setSubText(snapshot.collapsed.value.ifBlank { null })
            .setStyle(progressStyle)
            .setContentIntent(openWorkoutIntent(snapshot.sessionId))
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(snapshot.startedAtEpochMillis)
            .setUsesChronometer(true)
            .setColorized(true)
            .setColor(ACCENT_COLOR)
            .setRequestPromotedOngoing(true)

        if (!shortCriticalText.isNullOrBlank()) {
            builder.setShortCriticalText(shortCriticalText)
        }

        snapshot.expanded.actions.forEach { action ->
            val pendingIntent = actionPendingIntents[action.id] ?: return@forEach
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(appContext, android.R.drawable.ic_menu_edit),
                    action.label,
                    pendingIntent,
                ).build(),
            )
        }

        return builder.build()
    }

    /** Pre-API-36 path — unchanged behaviour, no promotion attempt. */
    private fun buildCompatNotification(
        snapshot: OngoingWorkoutSurfaceSnapshot,
        actionPendingIntents: Map<String, PendingIntent>,
    ): Notification {
        val builder = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(snapshot.collapsed.title)
            .setContentText(compactContent(snapshot))
            .setSubText(snapshot.collapsed.value.ifBlank { null })
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(snapshot.expanded.title)
                    .bigText(expandedContent(snapshot))
                    .setSummaryText(snapshot.collapsed.value.ifBlank { null }),
            )
            .setContentIntent(openWorkoutIntent(snapshot.sessionId))
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(snapshot.startedAtEpochMillis)
            .setUsesChronometer(true)
            .setLocalOnly(true)
            .setSilent(true)

        snapshot.expanded.actions.forEach { action ->
            val pendingIntent = actionPendingIntents[action.id] ?: return@forEach
            builder.addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_edit,
                    action.label,
                    pendingIntent,
                ).build(),
            )
        }

        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows active workout status and quick set controls"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun channelImportance(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        return notificationManager.getNotificationChannel(CHANNEL_ID)?.importance
    }

    private fun channelImportanceName(): String {
        return when (channelImportance()) {
            NotificationManager.IMPORTANCE_NONE -> "none"
            NotificationManager.IMPORTANCE_MIN -> "min"
            NotificationManager.IMPORTANCE_LOW -> "low"
            NotificationManager.IMPORTANCE_DEFAULT -> "default"
            NotificationManager.IMPORTANCE_HIGH -> "high"
            NotificationManager.IMPORTANCE_MAX -> "max"
            null -> "unavailable"
            else -> "custom"
        }
    }

    private fun compactContent(snapshot: OngoingWorkoutSurfaceSnapshot): String {
        return listOf(
            snapshot.collapsed.subtitle,
            snapshot.collapsed.value,
            snapshot.collapsed.elapsedLabel,
        ).filter { value -> value.isNotBlank() }.joinToString(" - ")
    }

    private fun expandedContent(snapshot: OngoingWorkoutSurfaceSnapshot): String {
        val status = compactContent(snapshot)
        val rows = snapshot.expanded.rows.joinToString("\n") { row ->
            "${row.label}: ${row.value}"
        }
        return listOf(status, rows)
            .filter { value -> value.isNotBlank() }
            .joinToString("\n")
    }

    /**
     * The collapsed subtitle carries the set counter ("Set 3/5"). The Now Bar chip only
     * has room for a handful of characters, so prefer "3/5", then the raw set index, and
     * fall back to the collapsed value ("82.5 kg x 8") when no counter is present.
     */
    private fun shortCriticalTextFor(snapshot: OngoingWorkoutSurfaceSnapshot): String? {
        val counter = parseSetCounter(snapshot)
        if (counter != null) {
            return if (counter.total != null && counter.total > 0) {
                "${counter.current}/${counter.total}"
            } else {
                counter.current.toString()
            }
        }
        return snapshot.collapsed.value.ifBlank { null }
    }

    private fun parseSetCounter(snapshot: OngoingWorkoutSurfaceSnapshot): SetCounter? {
        val subtitle = snapshot.collapsed.subtitle
        SET_COUNTER_WITH_TOTAL.find(subtitle)?.let { match ->
            val current = match.groupValues[1].toIntOrNull() ?: return@let
            val total = match.groupValues[2].toIntOrNull() ?: return@let
            return SetCounter(current, total)
        }
        SET_COUNTER_ONLY.find(subtitle)?.let { match ->
            val current = match.groupValues[1].toIntOrNull() ?: return@let
            return SetCounter(current, null)
        }
        return null
    }

    private fun openWorkoutIntent(sessionId: Long): PendingIntent {
        val intent = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_active_workout", true)
            putExtra("active_session_id", sessionId)
        }
        return PendingIntent.getActivity(
            appContext,
            OPEN_WORKOUT_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Primary success signal for the Now Bar work — deliberately a direct platform call so
     * a false result means "not promotable", never "the lookup blew up".
     */
    private fun Notification.hasPromotableCharacteristicsOrFalse(): Boolean {
        if (Build.VERSION.SDK_INT < ANDROID_16_API) return false
        return hasPromotableCharacteristics()
    }

    private fun activeNotificationIsPromotedOngoing(): Boolean {
        if (Build.VERSION.SDK_INT < ANDROID_16_API) return false
        val active = notificationManager.activeNotifications
            .firstOrNull { notification -> notification.id == NOTIFICATION_ID }
            ?.notification
            ?: return false
        return active.flags and Notification.FLAG_PROMOTED_ONGOING ==
            Notification.FLAG_PROMOTED_ONGOING
    }

    private data class SetCounter(val current: Int, val total: Int?)

    companion object {
        private const val TAG = "WorkoutSurfaceRenderer"
        private const val CHANNEL_ID = "workout_live"
        private const val CHANNEL_NAME = "Live Workout"
        private const val NOTIFICATION_ID = 1
        private const val OPEN_WORKOUT_REQUEST_CODE = 4201
        private const val ANDROID_16_API = 36

        /** App accent (`lib/theme/app_theme.dart` dark primary) used for `setColorized`. */
        private const val ACCENT_COLOR = 0xFF0A84FF.toInt()

        private val SET_COUNTER_WITH_TOTAL = Regex("""(\d+)\s*/\s*(\d+)""")
        private val SET_COUNTER_ONLY = Regex("""(\d+)""")
    }
}
