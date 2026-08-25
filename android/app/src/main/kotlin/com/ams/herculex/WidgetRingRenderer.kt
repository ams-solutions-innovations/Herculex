package com.ams.herculex

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF

object WidgetRingRenderer {

    /**
     * Draws an anti-aliased circular progress ring and returns a crisp [Bitmap].
     *
     * @param sizePx Output bitmap width and height in pixels.
     * @param strokeWidthPx Width of the gauge stroke.
     * @param progress Fraction of completion (0.0 to 1.0+).
     * @param progressColor Color for the filled progress arc.
     * @param trackColor Color for the background circle track.
     * @param startAngle Angle in degrees where the arc begins (-90f is top/12 o'clock).
     */
    fun drawRing(
        sizePx: Int = 240,
        strokeWidthPx: Float = 18f,
        progress: Float = 0f,
        progressColor: Int = Color.parseColor("#E5E5EA"),
        trackColor: Int = Color.parseColor("#2C2C32"),
        startAngle: Float = -90f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val halfStroke = strokeWidthPx / 2f
        val rect = RectF(
            halfStroke + 2f,
            halfStroke + 2f,
            sizePx - halfStroke - 2f,
            sizePx - halfStroke - 2f
        )

        // Background track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = trackColor
        }
        canvas.drawOval(rect, trackPaint)

        // Progress arc
        val clampedProgress = progress.coerceIn(0f, 1f)
        if (clampedProgress > 0.001f) {
            val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx
                color = progressColor
                strokeCap = Paint.Cap.ROUND
            }
            val sweepAngle = clampedProgress * 360f
            canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint)
        }

        return bitmap
    }
}
