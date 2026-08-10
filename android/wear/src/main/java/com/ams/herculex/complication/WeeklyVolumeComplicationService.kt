package com.ams.herculex.complication

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.ams.herculex.MainActivity
import com.ams.herculex.sync.MacroStore

class WeeklyVolumeComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        if (type != ComplicationType.SHORT_TEXT) return null
        return createComplicationData("1.5t", "Vol")
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) return null

        val tonnage = MacroStore.weeklyTonnage(this)
        val text = if (tonnage >= 1000f) {
            "%.1ft".format(tonnage / 1000f)
        } else {
            "${tonnage.toInt()}kg"
        }

        return createComplicationData(text, "Vol")
    }

    private fun createComplicationData(text: String, title: String): ComplicationData {
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

        return ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(text).build(),
            contentDescription = PlainComplicationText.Builder("Weekly Volume").build()
        )
            .setTitle(PlainComplicationText.Builder(title).build())
            .setTapAction(pendingIntent)
            .build()
    }
}
