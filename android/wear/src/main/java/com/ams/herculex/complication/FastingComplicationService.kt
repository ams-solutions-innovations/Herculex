package com.ams.herculex.complication

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.ams.herculex.MainActivity
import com.ams.herculex.R
import com.ams.herculex.sync.FastingStore

class FastingComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = 14f * 3600f,
            min = 0f,
            max = 16f * 3600f,
            text = "14h",
            title = "Fast",
            shortTextFallback = "14h",
            shortTextTitle = "Fast",
            description = "Fasting 14h of 16h",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_fasting,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val snapshot = FastingStore.snapshot(this)

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "fasting")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1005,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val (current, max, text, desc) = if (snapshot.hasActiveFast) {
            val elapsedSec = snapshot.elapsedSeconds().toFloat()
            val targetSec = snapshot.targetSeconds.toFloat()
            val hours = (elapsedSec / 3600f).toInt()
            val mins = ((elapsedSec % 3600f) / 60f).toInt()
            val display = if (hours >= 1) "${hours}h" else "${mins}m"
            val targetHours = (targetSec / 3600f).toInt()
            Quad(elapsedSec, targetSec, display, "Fasting ${snapshot.elapsedText()} of ${targetHours}h")
        } else {
            Quad(0f, 16f * 3600f, "0h", "No active fast")
        }

        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = request.complicationType,
            current = current,
            min = 0f,
            max = max,
            text = text,
            title = "Fast",
            shortTextFallback = text,
            shortTextTitle = "Fast",
            description = desc,
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_fasting,
        )
    }

    private data class Quad(val current: Float, val max: Float, val text: String, val desc: String)
}
