package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * Base for the redesigned home-screen widgets.
 *
 * Each widget is drawn by [HxWidgetRenderer] into one bitmap sized to the
 * widget's current bounds, with transparent click targets laid over it by
 * the layout ([layoutId]). Resizing re-renders via [onAppWidgetOptionsChanged].
 */
abstract class HxWidgetProvider : AppWidgetProvider() {

    /** Design size in dp, used until the launcher reports real bounds. */
    protected abstract val defaultSize: Pair<Float, Float>

    protected open val layoutId: Int get() = R.layout.widget_hx_card

    protected abstract fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered

    /** Wires taps. The default layout has a single target, [R.id.widget_root]. */
    protected abstract fun bindClicks(context: Context, views: RemoteViews)

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val renderer = HxWidgetRenderer(
            HxFonts.fromAssets(context.assets),
            HxWidgetPalette.load(context),
            context.resources.displayMetrics.density,
        )
        for (id in appWidgetIds) update(context, appWidgetManager, id, renderer)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    private fun update(context: Context, manager: AppWidgetManager, id: Int, renderer: HxWidgetRenderer) {
        val (w, h) = sizeOf(context, manager.getAppWidgetOptions(id))
        val rendered = render(context, renderer, w, h)
        val views = RemoteViews(context.packageName, layoutId)
        views.setImageViewBitmap(R.id.widget_canvas, rendered.bitmap)
        // Drop the pre-draw placeholder so it can't show at the bitmap's edges.
        views.setInt(R.id.widget_canvas, "setBackgroundResource", 0)
        views.setContentDescription(R.id.widget_canvas, rendered.description)
        bindClicks(context, views)
        manager.updateAppWidget(id, views)
    }

    private fun sizeOf(context: Context, options: Bundle?): Pair<Float, Float> {
        val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val w = options?.getInt(
            if (portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH,
        ) ?: 0
        val h = options?.getInt(
            if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
        ) ?: 0
        return if (w > 0 && h > 0) w.toFloat() to h.toFloat() else defaultSize
    }

    companion object {
        const val ACTION_OPEN_ROUTE = "com.ams.herculex.ACTION_OPEN_ROUTE"
        const val EXTRA_ROUTE = "route"
        const val ACTION_WIDGET_COMMAND = "com.ams.herculex.ACTION_WIDGET_COMMAND"
        const val EXTRA_COMMAND = "command"
        const val EXTRA_ARG = "arg"

        /** Prefix of the JSON payloads pushed by Flutter's `syncWidgetData`. */
        const val KEY_DATA_PREFIX = "widget_data_"

        /** Which widgets redraw when `syncWidgetData` updates a key. */
        val DATA_PROVIDERS: Map<String, Array<Class<*>>> = mapOf(
            "plan" to arrayOf(TodaysPlanWidgetProvider::class.java),
            "week" to arrayOf(WeekWidgetProvider::class.java),
            "bodyweight" to arrayOf(BodyweightWidgetProvider::class.java),
            "streak_workouts" to arrayOf(WorkoutStreakWidgetProvider::class.java),
            "streak_logging" to arrayOf(LoggingStreakWidgetProvider::class.java),
            "prs" to arrayOf(LatestPrsWidgetProvider::class.java),
            "volume" to arrayOf(VolumeWidgetProvider::class.java),
            "next_focus" to arrayOf(NextFocusWidgetProvider::class.java),
            "supplements" to arrayOf(SupplementsWidgetProvider::class.java),
            "mini" to arrayOf(MiniWorkoutWidgetProvider::class.java),
            "intake" to arrayOf(IntakeTrendWidgetProvider::class.java),
            "cycle" to arrayOf(CycleWidgetProvider::class.java),
        )

        /** Every widget, for redraws that affect all of them (theme changes). */
        val ALL_PROVIDERS: Array<Class<*>> = arrayOf<Class<*>>(
            TodayCaloriesMediumWidgetProvider::class.java,
            TodayCaloriesSmallWidgetProvider::class.java,
            TodayMacrosMediumWidgetProvider::class.java,
            RecoveryWidgetProvider::class.java,
            FastingWidgetProvider::class.java,
            ScannerWidgetProvider::class.java,
            CnsWidgetProvider::class.java,
            ProteinWidgetProvider::class.java,
            CarbsWidgetProvider::class.java,
            FatWidgetProvider::class.java,
        ) + DATA_PROVIDERS.values.flatMap { it.asList() }

        /** A tap that opens [MainActivity] with [action], which Flutter routes on. */
        fun appAction(context: Context, requestCode: Int, action: String, route: String? = null): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                route?.let { putExtra(EXTRA_ROUTE, it) }
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** A tap Flutter handles as an in-app action, e.g. starting today's plan. */
        fun command(context: Context, requestCode: Int, command: String, arg: String? = null): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_WIDGET_COMMAND
                putExtra(EXTRA_COMMAND, command)
                arg?.let { putExtra(EXTRA_ARG, it) }
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** Opens a main tab: 0 dashboard, 1 nutrition, 2 workouts. */
        fun openTab(context: Context, requestCode: Int, tab: Int) = command(context, requestCode, "openTab", "$tab")

        /** The payload Flutter last pushed for [key], or null before the first sync. */
        fun data(context: Context, key: String): JSONObject? =
            CnsWidgetProvider.getPrefs(context).getString(KEY_DATA_PREFIX + key, null)?.let {
                try {
                    JSONObject(it)
                } catch (_: Exception) {
                    null
                }
            }

        fun JSONObject.optStringOrNull(name: String): String? =
            if (isNull(name)) null else optString(name)

        fun JSONObject.floats(name: String): List<Float> {
            val arr = optJSONArray(name) ?: return emptyList()
            return (0 until arr.length()).map { arr.getDouble(it).toFloat() }
        }

        /** Value, unit and sparkline series; [emptyUnit] shows when nothing is logged. */
        fun trend(d: JSONObject?, emptyUnit: String): HxTrend {
            val value = d?.optStringOrNull("value")
            return HxTrend(
                value = value,
                unit = if (value == null) emptyUnit else d.optString("unit"),
                series = d?.floats("series") ?: emptyList(),
                target = if (d == null || d.isNull("target")) null else d.getDouble("target").toFloat(),
            )
        }

        fun streak(d: JSONObject?, defaultUnit: String) = HxStreak(
            current = d?.optInt("current") ?: 0,
            unit = d?.optString("unit")?.takeIf { it.isNotEmpty() } ?: defaultUnit,
            activeToday = d?.optBoolean("activeToday") ?: false,
        )

        fun openNutrition(context: Context) =
            appAction(context, 201, TodayCaloriesSmallWidgetProvider.ACTION_OPEN_NUTRITION)

        fun searchFood(context: Context) =
            appAction(context, 203, TodayCaloriesMediumWidgetProvider.ACTION_SEARCH_FOOD)

        fun scanFood(context: Context) =
            appAction(context, 204, ScannerWidgetProvider.ACTION_SCAN)

        /** Request codes must differ per route: extras don't distinguish PendingIntents. */
        fun openRoute(context: Context, requestCode: Int, route: String) =
            appAction(context, requestCode, ACTION_OPEN_ROUTE, route)

        fun nutrition(prefs: SharedPreferences): HxNutrition {
            val goal = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_BASE_GOAL, 0)
            val food = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_FOOD, 0)
            val exercise = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_EXERCISE, 0)
            return HxNutrition(
                goal = goal,
                food = food,
                exercise = exercise,
                remaining = prefs.getInt(TodayCaloriesSmallWidgetProvider.KEY_CALORIES_REMAINING, goal + exercise - food),
                protein = HxMacro(
                    prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_CURRENT, 0),
                    prefs.getInt(ProteinWidgetProvider.KEY_PROTEIN_TARGET, 0),
                ),
                carbs = HxMacro(
                    prefs.getInt(CarbsWidgetProvider.KEY_CARBS_CURRENT, 0),
                    prefs.getInt(CarbsWidgetProvider.KEY_CARBS_TARGET, 0),
                ),
                fat = HxMacro(
                    prefs.getInt(FatWidgetProvider.KEY_FAT_CURRENT, 0),
                    prefs.getInt(FatWidgetProvider.KEY_FAT_TARGET, 0),
                ),
            )
        }

        fun recovery(prefs: SharedPreferences): HxRecovery {
            val score = prefs.getInt(RecoveryWidgetProvider.KEY_RECOVERY_SCORE, -1)
            val muscles = try {
                val arr = JSONArray(prefs.getString(RecoveryWidgetProvider.KEY_RECOVERY_MUSCLES, "[]"))
                (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    o.getString("name") to o.getInt("score")
                }
            } catch (_: Exception) {
                emptyList()
            }
            return HxRecovery(score.takeIf { it >= 0 }, muscles)
        }
    }
}
