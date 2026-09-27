package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

/**
 * "Training" widget (4x4).
 *
 * Shows today's planned workout (title, exercise count, program week) and up
 * to 4 of today's supplements with a static taken/not-taken indicator.
 * Populated via [MainActivity]'s MethodChannel handler (`syncTraining`)
 * whenever the dashboard's today's-session provider or the supplement
 * tracker changes — see `widgetTrainingSyncControllerProvider` in
 * `dashboard_providers.dart`.
 */
class TrainingWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = CnsWidgetProvider.getPrefs(context)

        // Yesterday's workout and its supplement ticks must not read as today's:
        // on a stale (or not yet synced) store, fall through to the empty state.
        val stale = isWidgetDataStale(prefs)

        val title = if (stale) null else prefs.getString(KEY_TITLE, null)
        val week = if (stale) -1 else prefs.getInt(KEY_WEEK, -1)
        val exerciseCount = if (stale) 0 else prefs.getInt(KEY_EXERCISE_COUNT, 0)

        val names = if (stale) emptyList() else splitField(prefs.getString(KEY_SUPP_NAMES, null))
        val doses = if (stale) emptyList() else splitField(prefs.getString(KEY_SUPP_DOSES, null))
        val times = if (stale) emptyList() else splitField(prefs.getString(KEY_SUPP_TIMES, null))
        val taken = if (stale) emptyList() else splitField(prefs.getString(KEY_SUPP_TAKEN, null))
        val takenCount = if (stale) 0 else prefs.getInt(KEY_SUPP_TAKEN_COUNT, 0)
        val totalCount = if (stale) 0 else prefs.getInt(KEY_SUPP_TOTAL_COUNT, 0)

        for (id in appWidgetIds) {
            val views = buildViews(
                context,
                title,
                week,
                exerciseCount,
                names,
                doses,
                times,
                taken,
                takenCount,
                totalCount,
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun splitField(raw: String?): List<String> =
        if (raw.isNullOrEmpty()) emptyList() else raw.split(FIELD_DELIMITER)

    private fun buildViews(
        context: Context,
        title: String?,
        week: Int,
        exerciseCount: Int,
        names: List<String>,
        doses: List<String>,
        times: List<String>,
        taken: List<String>,
        takenCount: Int,
        totalCount: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_training)

        if (title.isNullOrEmpty()) {
            views.setTextViewText(R.id.training_headline, "No workout scheduled")
            views.setTextViewText(R.id.training_stats, "")
            views.setViewVisibility(R.id.training_week_badge, View.GONE)
        } else {
            views.setTextViewText(R.id.training_headline, title)
            views.setTextViewText(
                R.id.training_stats,
                if (exerciseCount == 1) "1 exercise" else "$exerciseCount exercises"
            )
            if (week > 0) {
                views.setTextViewText(R.id.training_week_badge, "WEEK $week")
                views.setViewVisibility(R.id.training_week_badge, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.training_week_badge, View.GONE)
            }
        }

        views.setTextViewText(R.id.training_supp_count, "$takenCount/$totalCount")

        val rowIds = intArrayOf(
            R.id.training_supp_row_1, R.id.training_supp_row_2,
            R.id.training_supp_row_3, R.id.training_supp_row_4,
        )
        val dotIds = intArrayOf(
            R.id.training_supp_dot_1, R.id.training_supp_dot_2,
            R.id.training_supp_dot_3, R.id.training_supp_dot_4,
        )
        val nameIds = intArrayOf(
            R.id.training_supp_name_1, R.id.training_supp_name_2,
            R.id.training_supp_name_3, R.id.training_supp_name_4,
        )
        val doseIds = intArrayOf(
            R.id.training_supp_dose_1, R.id.training_supp_dose_2,
            R.id.training_supp_dose_3, R.id.training_supp_dose_4,
        )
        val timeIds = intArrayOf(
            R.id.training_supp_time_1, R.id.training_supp_time_2,
            R.id.training_supp_time_3, R.id.training_supp_time_4,
        )

        for (i in 0 until MAX_SUPPLEMENT_ROWS) {
            if (i >= names.size || names[i].isEmpty()) {
                views.setViewVisibility(rowIds[i], View.GONE)
                continue
            }
            views.setViewVisibility(rowIds[i], View.VISIBLE)
            views.setTextViewText(nameIds[i], names[i])
            views.setTextViewText(doseIds[i], doses.getOrElse(i) { "" })

            val time = times.getOrElse(i) { "" }
            if (time.isEmpty()) {
                views.setViewVisibility(timeIds[i], View.GONE)
            } else {
                views.setViewVisibility(timeIds[i], View.VISIBLE)
                views.setTextViewText(timeIds[i], time)
            }

            // Filled purple circle + visible checkmark when taken; plain
            // outline circle with the checkmark hidden otherwise.
            val isTaken = taken.getOrElse(i) { "0" } == "1"
            views.setInt(
                dotIds[i],
                "setBackgroundResource",
                if (isTaken) R.drawable.widget_supplement_dot_filled else R.drawable.widget_supplement_dot_outline
            )
            views.setImageViewResource(dotIds[i], R.drawable.ic_widget_check)
            views.setInt(dotIds[i], "setImageAlpha", if (isTaken) 255 else 0)
            views.setTextColor(
                nameIds[i],
                if (isTaken) Color.parseColor("#8A8A8E") else Color.parseColor("#F5F5F7")
            )
        }

        // Tap anywhere on the card opens the app
        views.setOnClickPendingIntent(R.id.widget_root, launchAppIntent(context))

        // "Start workout" jumps straight to the workout tab/active-session
        // screen — the same `open_active_workout` extra the Workout Bubble
        // and watch notifications already use (see WorkoutBubbleController.kt
        // and MainActivity.handleWorkoutsIntent). No dedicated AppRoutes
        // constant exists for "today's workout", so this is the closest
        // existing deep link rather than a raw string route.
        val startWorkoutIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("open_active_workout", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val startWorkoutPendingIntent = PendingIntent.getActivity(
            context,
            401,
            startWorkoutIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_start_workout, startWorkoutPendingIntent)

        return views
    }

    companion object {
        const val KEY_TITLE = "widget_training_title"
        const val KEY_WEEK = "widget_training_week"
        const val KEY_EXERCISE_COUNT = "widget_training_exercise_count"
        const val KEY_SUPP_NAMES = "widget_training_supp_names"
        const val KEY_SUPP_DOSES = "widget_training_supp_doses"
        const val KEY_SUPP_TIMES = "widget_training_supp_times"
        const val KEY_SUPP_TAKEN = "widget_training_supp_taken"
        const val KEY_SUPP_TAKEN_COUNT = "widget_training_supp_taken_count"
        const val KEY_SUPP_TOTAL_COUNT = "widget_training_supp_total_count"

        /**
         * SharedPreferences only stores primitives, so per-supplement fields
         * are packed into a single delimited string, one field per pref key.
         * The ASCII Unit Separator control character cannot appear in a
         * supplement name/dose/time typed through the app's UI.
         */
        const val FIELD_DELIMITER = ""
        const val MAX_SUPPLEMENT_ROWS = 4
    }
}
