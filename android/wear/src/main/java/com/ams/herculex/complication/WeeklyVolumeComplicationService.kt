package com.ams.herculex.complication

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.ams.herculex.MainActivity
import com.ams.herculex.R
import com.ams.herculex.sync.MacroStore

class WeeklyVolumeComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = 12000f,
            min = 0f,
            max = 20000f,
            text = "12t",
            title = "Vol",
            shortTextFallback = "12t",
            shortTextTitle = "Vol",
            description = "Weekly Volume 12t",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_barbell,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val tonnage = MacroStore.weeklyTonnage(this)
        val formatted = if (tonnage >= 1000f) {
            "%.1ft".format(java.util.Locale.US, tonnage / 1000f)
        } else {
            "${tonnage.toInt()}kg"
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "weekly_volume")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val benchmark = maxOf(tonnage, 20000f)

        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = request.complicationType,
            current = tonnage,
            min = 0f,
            max = benchmark,
            text = formatted,
            title = "Vol",
            shortTextFallback = formatted,
            shortTextTitle = "Vol",
            description = "Weekly Volume $formatted",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_barbell,
        )
    }
}
