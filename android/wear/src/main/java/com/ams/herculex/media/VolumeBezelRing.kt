package com.ams.herculex.media

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/** Above this the ring turns red: loud enough to be worth a glance. */
private const val LOUD_PERCENT = 80
private val RingGreen = Color(0xFF1DB954)
private val RingRed = Color(0xFFFF453A)
private val RingTrack = Color(0x33FFFFFF)

/**
 * Volume shown the way a timer is: an arc around the edge of the round
 * screen, filling clockwise from 12 o'clock. Appears while the bezel turns and
 * fades out [hideAfterMs] after the last detent, so the music screen itself
 * carries no volume icon or bar. Green, red above [LOUD_PERCENT] %.
 *
 * [revision] changes on every detent (pass a counter or timestamp) to keep
 * the ring up while the user is still turning.
 */
@Composable
fun VolumeBezelRing(
    volumePercent: Int,
    revision: Long,
    modifier: Modifier = Modifier,
    hideAfterMs: Long = 1500L,
) {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        if (revision == 0L) return@LaunchedEffect
        visible = true
        delay(hideAfterMs)
        visible = false
    }
    val sweep by animateFloatAsState(
        targetValue = volumePercent.coerceIn(0, 100) / 100f,
        animationSpec = tween(durationMillis = 120),
        label = "volumeSweep",
    )
    val color = if (volumePercent > LOUD_PERCENT) RingRed else RingGreen

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(tween(120)),
        exit = fadeOut(tween(300)),
        modifier = modifier,
    ) {
        Canvas(modifier = Modifier.fillMaxSize().padding(3.dp)) {
            val stroke = 6.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            val topLeft = Offset(inset, inset)
            drawArc(
                color = RingTrack,
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = stroke),
            )
            if (sweep > 0f) {
                drawArc(
                    color = color,
                    startAngle = -90f,
                    sweepAngle = 360f * sweep,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
            }
        }
    }
}

/**
 * Shrinks a control slightly while pressed — the transport buttons used to
 * have no press feedback at all, so a tap felt like it had not registered.
 */
fun Modifier.pressFeedback(interactionSource: MutableInteractionSource): Modifier = composed {
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.88f else 1f,
        animationSpec = tween(durationMillis = 90),
        label = "pressScale",
    )
    graphicsLayer {
        scaleX = scale
        scaleY = scale
    }
}
