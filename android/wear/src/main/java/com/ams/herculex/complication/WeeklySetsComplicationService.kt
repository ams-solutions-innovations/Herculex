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

class WeeklySetsComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = 35f,
            min = 0f,
            max = 50f,
            text = "35",
            title = "Sets",
            shortTextFallback = "35",
            shortTextTitle = "Sets",
            description = "Weekly Sets 35 of 50",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_dumbbell,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val sets = MacroStore.weeklySets(this).toFloat()
        val goalSets = maxOf(sets, 50f)
        val formatted = sets.toInt().toString()

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

        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = request.complicationType,
            current = sets,
            min = 0f,
            max = goalSets,
            text = formatted,
            title = "Sets",
            shortTextFallback = formatted,
            shortTextTitle = "Sets",
            description = "Weekly Sets $formatted of ${goalSets.toInt()}",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_dumbbell,
        )
    }
}
