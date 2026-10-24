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

    protected open val layoutId: Int get() = if (pillEligible) R.layout.widget_hx_pill else R.layout.widget_hx_card

    /**
     * Whether the user's pill setting applies: the one-row widgets two cells
     * wide. Taken from the design size, not the live bounds, because a 4x1 is
     * as tall as a 2x1 and a launcher can stretch either.
     */
    protected val pillEligible: Boolean get() = defaultSize.first < 250f && defaultSize.second < 100f

    protected abstract fun render(context: Context, renderer: HxWidgetRenderer, w: Float, h: Float): HxRendered

    /** Wires taps. The default layout has a single target, [R.id.widget_root]. */
    protected abstract fun bindClicks(context: Context, views: RemoteViews)

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val renderer = HxWidgetRenderer(
            HxFonts.fromAssets(context.assets),
            HxWidgetPalette.load(context).forWidget(pillEligible),
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
        val targetH = if (pillEligible) defaultSize.second else h
        val rendered = render(context, renderer, w, targetH)
        val views = RemoteViews(context.packageName, layoutId)
        views.setImageViewBitmap(R.id.widget_canvas, rendered.bitmap)
        // Drop the pre-draw placeholder so it can't show at the bitmap's edges.
        views.setInt(R.id.widget_canvas, "setBackgroundResource", 0)
        views.setContentDescription(R.id.widget_canvas, rendered.description)
        bindClicks(context, views)
        manager.updateAppWidget(id, views)

        updatePickerPreview(context, manager, renderer)
    }

    /**
     * Generated previews are rate-limited by Android. Build them at the
     * widget's design size, rather than reusing an arbitrarily resized live
     * instance, and keep click PendingIntents out of the picker preview.
     */
    private fun updatePickerPreview(
        context: Context,
        manager: AppWidgetManager,
        renderer: HxWidgetRenderer,
    ) {
        if (android.os.Build.VERSION.SDK_INT < 35) return

        val prefs = CnsWidgetProvider.getPrefs(context)
        val key = PREVIEW_ATTEMPT_PREFIX + javaClass.name
        val now = System.currentTimeMillis()
        if (now - prefs.getLong(key, 0L) < PREVIEW_REFRESH_INTERVAL_MS) return

        // Record attempts too, so a rate-limited or unsupported response does
        // not turn each ordinary widget update into another API call.
        prefs.edit().putLong(key, now).apply()
        try {
            val preview = render(context, renderer, defaultSize.first, defaultSize.second)
            val previewViews = RemoteViews(context.packageName, layoutId).apply {
                setImageViewBitmap(R.id.widget_canvas, preview.bitmap)
                setInt(R.id.widget_canvas, "setBackgroundResource", 0)
                setContentDescription(R.id.widget_canvas, preview.description)
            }
            manager.setWidgetPreview(
                android.content.ComponentName(context, this::class.java),
                android.appwidget.AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN,
                previewViews,
            )
        } catch (_: Throwable) {
            // Static previewLayout remains available if generated previews fail.
        }
    }

    private fun sizeOf(context: Context, options: Bundle?): Pair<Float, Float> {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S && options != null) {
            @Suppress("DEPRECATION")
            val sizes = options.getParcelableArrayList<android.util.SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!sizes.isNullOrEmpty()) {
                val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
                val size = if (portrait) sizes.minByOrNull { it.width } ?: sizes.first()
                else sizes.maxByOrNull { it.width } ?: sizes.first()
                if (size.width > 0 && size.height > 0) {
                    return size.width to size.height
                }
            }
        }
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
        private const val PREVIEW_ATTEMPT_PREFIX = "widget_preview_attempt_"
        private const val PREVIEW_REFRESH_INTERVAL_MS = 31L * 60L * 1000L

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
            "sleep" to arrayOf(SleepWidgetProvider::class.java),
            "steps" to arrayOf(StepsWidgetProvider::class.java),
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
            // Yesterday's totals must not read as today's (see isWidgetDataStale).
            if (isWidgetDataStale(prefs)) return HxNutrition.UNSYNCED
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
            if (isWidgetDataStale(prefs)) return HxRecovery(null, emptyList())
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
