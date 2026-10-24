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

class WaterComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val current = 1500f
        val goal = 2000f
        val formatted = "1.5L"
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = current,
            min = 0f,
            max = goal,
            text = formatted,
            title = "Water",
            shortTextFallback = formatted,
            shortTextTitle = "Water",
            description = "Water 1500ml / 2000ml",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_drop,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val current = MacroStore.water(this).toFloat()
        val rawGoal = MacroStore.waterGoal(this).toFloat()
        val goal = if (rawGoal > 0f) rawGoal else 2000f
        val formatted = if (current >= 1000f) {
            "%.1fL".format(java.util.Locale.US, current / 1000f)
        } else {
            "${current.toInt()}ml"
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "add_water")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1007,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = request.complicationType,
            current = current,
            min = 0f,
            max = goal,
            text = formatted,
            title = "Water",
            shortTextFallback = formatted,
            shortTextTitle = "Water",
            description = "Water ${current.toInt()}ml / ${goal.toInt()}ml",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_drop,
        )
    }
}
