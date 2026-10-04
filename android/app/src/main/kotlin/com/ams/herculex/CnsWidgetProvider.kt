package com.ams.herculex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import java.util.Calendar

/**
 * CNS Load ring card widget (2x2).
 *
 * Displays a readiness % ring plus a FRESH/MODERATE/HIGH badge. Updated via
 * [AppWidgetManager.updateAppWidget] called from [MainActivity]'s MethodChannel
 * handler whenever Flutter pushes new CNS data.
 */
class CnsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = getPrefs(context)
        val stale = isWidgetDataStale(prefs)
        val readiness = if (stale) -1 else prefs.getInt(KEY_CNS_READINESS, -1)
        val status = if (stale) null else prefs.getString(KEY_CNS_STATUS, null)

        for (id in appWidgetIds) {
            val views = buildViews(context, readiness, status)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, readiness: Int, status: String?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_pill_cns)

        if (readiness < 0 || status == null) {
            views.setTextViewText(R.id.cns_readiness, "—")
            views.setTextViewText(R.id.cns_status, "—")
            val emptyRing = WidgetRingRenderer.drawRing(
                sizePx = 220,
                strokeWidthPx = 16f,
                progress = 0f,
                progressColor = Color.parseColor("#E5E5EA"),
                trackColor = Color.parseColor("#2B374E")
            )
            views.setImageViewBitmap(R.id.cns_ring_image, emptyRing)
        } else {
            views.setTextViewText(R.id.cns_readiness, "$readiness%")
            views.setTextViewText(R.id.cns_status, status)

            val (ringColor, bgResId) = when (status) {
                "FRESH" -> Pair(Color.parseColor("#30D158"), R.drawable.widget_badge_green)
                "MODERATE" -> Pair(Color.parseColor("#FFD60A"), R.drawable.widget_badge_amber)
                else -> Pair(Color.parseColor("#FF453A"), R.drawable.widget_badge_red)
            }
            views.setTextColor(R.id.cns_status, ringColor)
            views.setInt(R.id.cns_status, "setBackgroundResource", bgResId)

            val ringBitmap = WidgetRingRenderer.drawRing(
                sizePx = 220,
                strokeWidthPx = 16f,
                progress = (readiness / 100f).coerceIn(0f, 1f),
                progressColor = ringColor,
                trackColor = Color.parseColor("#2B374E")
            )
            views.setImageViewBitmap(R.id.cns_ring_image, ringBitmap)
        }

        // Tap anywhere on the card opens the app
        views.setOnClickPendingIntent(
            R.id.widget_root,
            launchAppIntent(context)
        )

        return views
    }

    companion object {
        const val KEY_CNS_READINESS = "widget_cns_readiness"
        const val KEY_CNS_STATUS = "widget_cns_status"

        fun getPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /** Push fresh data and trigger a redraw for all active instances. */
        fun updateAll(context: Context, appWidgetManager: AppWidgetManager, ids: IntArray) {
            val provider = CnsWidgetProvider()
            provider.onUpdate(context, appWidgetManager, ids)
        }
    }
}

const val PREFS_NAME = "FlutterSharedPreferences"

/**
 * Epoch day (UTC-independent local day number) of the last sync from Flutter.
 *
 * Providers compare this against today and fall back to their "—" placeholder
 * when it does not match, so a widget never presents yesterday's numbers as if
 * they were current. Written by MainActivity on every sync call.
 */
const val KEY_SYNCED_EPOCH_DAY = "widget_synced_epoch_day"

/** Every AppWidgetProvider registered in the manifest. */
val ALL_WIDGET_PROVIDERS: List<Class<out AppWidgetProvider>> = listOf(
    CnsWidgetProvider::class.java,
    RecoveryWidgetProvider::class.java,
    CarbsWidgetProvider::class.java,
    FatWidgetProvider::class.java,
    ProteinWidgetProvider::class.java,
    ScannerWidgetProvider::class.java,
    TodayCaloriesSmallWidgetProvider::class.java,
    TodayCaloriesMediumWidgetProvider::class.java,
    TodayMacrosMediumWidgetProvider::class.java,
    TrainingWidgetProvider::class.java,
    QuickActionsWidgetProvider::class.java,
)

/**
 * Broadcasts APPWIDGET_UPDATE for every placed instance of [providerClasses].
 *
 * Providers read SharedPreferences in onUpdate, so this is all that is needed
 * to make them repaint. Shared by MainActivity (after a Flutter sync) and
 * WidgetBootReceiver (after a reboot or app update).
 */
fun broadcastWidgetUpdate(context: Context, providerClasses: List<Class<out AppWidgetProvider>>) {
    val appContext = context.applicationContext
    val manager = AppWidgetManager.getInstance(appContext)
    for (cls in providerClasses) {
        val component = ComponentName(appContext, cls)
        val ids = manager.getAppWidgetIds(component)
        if (ids.isEmpty()) continue
        appContext.sendBroadcast(
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                this.component = component
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
        )
    }
}

/**
 * True when the data in SharedPreferences was synced on a day other than today,
 * i.e. the widget would otherwise show stale numbers. Also true before the very
 * first sync, so an unsynced widget renders its placeholder rather than zeros.
 */
fun isWidgetDataStale(prefs: SharedPreferences): Boolean {
    val syncedDay = prefs.getLong(KEY_SYNCED_EPOCH_DAY, -1L)
    return syncedDay != currentEpochDay()
}

/** Local-time epoch day number, matching Dart's DateTime-based computation. */
fun currentEpochDay(): Long {
    val now = Calendar.getInstance()
    now.set(Calendar.HOUR_OF_DAY, 0)
    now.set(Calendar.MINUTE, 0)
    now.set(Calendar.SECOND, 0)
    now.set(Calendar.MILLISECOND, 0)
    val offsetMs = now.get(Calendar.ZONE_OFFSET) + now.get(Calendar.DST_OFFSET)
    return (now.timeInMillis + offsetMs) / 86_400_000L
}

/** Returns a PendingIntent that launches the main Herculex activity. */
fun launchAppIntent(context: Context): PendingIntent {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: Intent(context, MainActivity::class.java)
    return PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}

/** Opens the Nutrition tab (routed through MainActivity, see its pending-action hand-off). */
fun openNutritionIntent(context: Context): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        action = TodayCaloriesSmallWidgetProvider.ACTION_OPEN_NUTRITION
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    return PendingIntent.getActivity(
        context,
        206,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}
