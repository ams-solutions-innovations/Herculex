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

class CarbsComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val current = 180f
        val goal = 250f
        val formatted = "180g"
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = current,
            min = 0f,
            max = goal,
            text = formatted,
            title = "C",
            shortTextFallback = formatted,
            shortTextTitle = "C",
            description = "Carbs $formatted / ${goal.toInt()}g",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_carbs,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val current = MacroStore.carbs(this).toFloat()
        val rawGoal = MacroStore.carbsGoal(this).toFloat()
        val goal = if (rawGoal > 0f) rawGoal else 200f
        val formatted = "${current.toInt()}g"

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "nutrient_trend/carbs")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1003,
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
            title = "C",
            shortTextFallback = formatted,
            shortTextTitle = "C",
            description = "Carbs $formatted / ${goal.toInt()}g",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_carbs,
        )
    }
}
