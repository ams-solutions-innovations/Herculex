package com.ams.herculex.media

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Generates a smooth, scalloped flower/squircle shape with [lobes] ripples,
 * matching the Material You / Wear OS organic media player button shape.
 */
class FlowerScallopShape(
    private val lobes: Int = 12,
    private val amplitudeFraction: Float = 0.09f,
    private val phaseOffsetRad: Float = 0f,
) : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val path = createScallopPath(size, lobes, amplitudeFraction, phaseOffsetRad)
        return Outline.Generic(path)
    }
}

fun createScallopPath(
    size: Size,
    lobes: Int = 12,
    amplitudeFraction: Float = 0.09f,
    phaseOffsetRad: Float = 0f,
): Path {
    val path = Path()
    val cx = size.width / 2f
    val cy = size.height / 2f
    val baseRadius = (minOf(size.width, size.height) / 2f) * (1f - amplitudeFraction)
    val amplitude = baseRadius * amplitudeFraction

    val steps = lobes * 10
    val dTheta = (2.0 * PI / steps).toFloat()

    for (i in 0..steps) {
        val theta = i * dTheta
        val r = baseRadius + amplitude * cos((lobes * theta) + phaseOffsetRad)
        val x = cx + r * cos(theta)
        val y = cy + r * sin(theta)
        if (i == 0) {
            path.moveTo(x, y)
        } else {
            path.lineTo(x, y)
        }
    }
    path.close()
    return path
}
