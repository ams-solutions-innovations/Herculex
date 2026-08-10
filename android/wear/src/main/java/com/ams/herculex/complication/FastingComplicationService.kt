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
import com.ams.herculex.sync.FastingStore
import com.ams.herculex.sync.MacroStore

class FastingComplicationService : SuspendingComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        if (type != ComplicationType.SHORT_TEXT) return null
        return createComplicationData("14h", "Fast")
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) return null

        val snapshot = FastingStore.snapshot(this)
        val fasting = if (snapshot.hasActiveFast) {
            snapshot.elapsedText()
        } else {
            MacroStore.fasting(this)
        }

        return createComplicationData(fasting, "Fast")
    }

    private fun createComplicationData(text: String, title: String): ComplicationData {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "fasting")
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
            contentDescription = PlainComplicationText.Builder("Fasting Time Elapsed").build()
        )
            .setTitle(PlainComplicationText.Builder(title).build())
            .setTapAction(pendingIntent)
            .build()
    }
}
