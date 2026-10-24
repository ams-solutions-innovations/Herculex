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

class CaloriesComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val current = 1850f
        val goal = 2400f
        val formatted = WearComplicationHelper.formatCalories(current)
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = current,
            min = 0f,
            max = goal,
            text = formatted,
            title = "kcal",
            shortTextFallback = formatted,
            shortTextTitle = "kcal",
            description = "Calories $formatted / ${goal.toInt()} kcal",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_flame,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val current = MacroStore.calories(this).toFloat()
        val rawGoal = MacroStore.calorieGoal(this).toFloat()
        val goal = if (rawGoal > 0f) rawGoal else 2000f
        val formatted = WearComplicationHelper.formatCalories(current)

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "nutrient_trend/calories")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1002,
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
            title = "kcal",
            shortTextFallback = formatted,
            shortTextTitle = "kcal",
            description = "Calories $formatted / ${goal.toInt()} kcal",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_flame,
        )
    }
}
