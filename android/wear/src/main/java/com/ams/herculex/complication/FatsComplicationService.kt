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

class FatsComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val current = 45f
        val goal = 65f
        val formatted = "45g"
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = current,
            min = 0f,
            max = goal,
            text = formatted,
            title = "F",
            shortTextFallback = formatted,
            shortTextTitle = "F",
            description = "Fats $formatted / ${goal.toInt()}g",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_fat,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val current = MacroStore.fats(this).toFloat()
        val rawGoal = MacroStore.fatGoal(this).toFloat()
        val goal = if (rawGoal > 0f) rawGoal else 65f
        val formatted = "${current.toInt()}g"

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "nutrient_trend/fats")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1004,
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
            title = "F",
            shortTextFallback = formatted,
            shortTextTitle = "F",
            description = "Fats $formatted / ${goal.toInt()}g",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_fat,
        )
    }
}
