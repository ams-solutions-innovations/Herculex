package com.ams.herculex.complication

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.ams.herculex.MainActivity
import com.ams.herculex.R
import com.ams.herculex.sync.CnsStore

class CnsComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = type,
            current = 85f,
            min = 0f,
            max = 100f,
            text = "85%",
            title = "CNS",
            shortTextFallback = "85%",
            shortTextTitle = "CNS",
            description = "CNS Readiness 85% (FRESH)",
            pendingIntent = null,
            iconResId = R.drawable.ic_hx_cns,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val readiness = CnsStore.readinessPct(this).toFloat()
        val status = CnsStore.status(this)
        val formatted = "${readiness.toInt()}%"

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "cns")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1006,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return WearComplicationHelper.buildProgressComplicationData(
            context = this,
            type = request.complicationType,
            current = readiness,
            min = 0f,
            max = 100f,
            text = formatted,
            title = "CNS",
            shortTextFallback = formatted,
            shortTextTitle = "CNS",
            description = "CNS Readiness $formatted ($status)",
            pendingIntent = pendingIntent,
            iconResId = R.drawable.ic_hx_cns,
        )
    }
}
