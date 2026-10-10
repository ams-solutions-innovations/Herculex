package com.ams.herculex.workout

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val GlanceBlue = Color(0xFF1976D2)
private val GlanceTrack = Color(0xFF1B1F2C)
private val GlanceGray = Color(0xFF9098AA)
private val GlanceHeart = Color(0xFFFF453A)
private val GlanceTimer = Color(0xFF80C4FA)

/**
 * Glance page reached by swiping down from the set logger (Claude Design
 * "Glance"): the bezel is split per exercise and fills as its sets are done,
 * the centre shows the clock, workout completion %, sets done / left, a bar
 * per exercise, elapsed time and live heart rate.
 */
@Composable
fun WorkoutGlanceScreen(
    session: WorkoutSession,
    heartRate: Int = -1,
    elapsedSeconds: Long = 0L,
) {
    var nowEpochMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            nowEpochMs = System.currentTimeMillis()
            delay(1_000)
        }
    }
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val timeText = timeFormat.format(Date(nowEpochMs))

    // Warm-ups count like any other set, exactly as in the logger's bezel.
    val totals = session.exercises.map { it.warmupSetTotal + it.workingSetTotal }
    val dones = session.exercises.mapIndexed { i, ex -> ex.completedSets.coerceAtMost(totals[i]) }
    val targetSets = totals.sum()
    val completedSets = dones.sum()
    val leftSets = (targetSets - completedSets).coerceAtLeast(0)

    // Bezel / percentage grow in on entry, like the design (900 ms).
    val grow = remember { Animatable(0f) }
    LaunchedEffect(Unit) { grow.animateTo(1f, tween(900)) }
    val percent = if (targetSets > 0) {
        (completedSets.toFloat() / targetSets * 100f * grow.value).toInt()
    } else 0

    val elapsedHours = elapsedSeconds / 3600
    val elapsedMinutes = (elapsedSeconds % 3600) / 60
    val elapsedSecs = elapsedSeconds % 60
    val elapsedDisplay = if (elapsedHours > 0) {
        "%d:%02d:%02d".format(elapsedHours, elapsedMinutes, elapsedSecs)
    } else {
        "%d:%02d".format(elapsedMinutes, elapsedSecs)
    }
    val hrDisplay = if (heartRate > 0) "$heartRate" else "--"

    val beat by rememberInfiniteTransition(label = "glanceBeat").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1070, easing = LinearEasing), RepeatMode.Reverse),
        label = "glanceBeatValue",
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .domainGlow(Color(0xFF1976D2).copy(alpha = 0.22f), Color(0xFF1E44AA).copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        ExerciseBezel(
            totals = totals,
            dones = dones,
            grow = grow.value,
        )

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = timeText,
                color = GlanceGray,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
            )
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text = "$percent",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 46.sp,
                    letterSpacing = (-1.5).sp,
                )
                Text(
                    text = "%",
                    color = GlanceGray,
                    fontWeight = FontWeight.Bold,
                    fontSize = 22.sp,
                    modifier = Modifier.padding(bottom = 6.dp),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "$completedSets/$targetSets sets · ",
                    color = GlanceGray,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    text = "$leftSets left",
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
            Spacer(Modifier.height(6.dp))
            ExerciseBars(
                totals = totals,
                dones = dones,
                currentIndex = session.currentExerciseIndex,
            )
            Spacer(Modifier.height(7.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(HxIcons.Timer, null, tint = GlanceTimer, modifier = Modifier.size(14.dp))
                    Text(
                        text = elapsedDisplay,
                        color = Color.White,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        HxIcons.Heart,
                        null,
                        tint = GlanceHeart,
                        modifier = Modifier.size(14.dp).scale(1f + 0.14f * beat),
                    )
                    Text(
                        text = hrDisplay,
                        color = Color.White,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

/** Bezel split in proportion to each exercise's sets; every slice fills as sets are done. */
@Composable
private fun ExerciseBezel(totals: List<Int>, dones: List<Int>, grow: Float) {
    val all = totals.sum().coerceAtLeast(1)
    Canvas(Modifier.fillMaxSize()) {
        val stroke = size.minDimension * 10f / 330f
        val inset = size.minDimension * 9f / 330f + stroke / 2f
        val arcSize = Size(size.width - 2 * inset, size.height - 2 * inset)
        val topLeft = Offset(inset, inset)
        val gap = (15f / (2f * Math.PI.toFloat() * 156f)) * 360f
        var cursor = -90f
        totals.forEachIndexed { i, total ->
            val slice = 360f * total / all
            val start = cursor + gap / 2f
            val sweep = (slice - gap).coerceAtLeast(1f)
            drawArc(GlanceTrack, start, sweep, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            val fill = if (total > 0) dones[i].toFloat() / total else 0f
            if (fill > 0f) {
                drawArc(
                    GlanceBlue,
                    start,
                    (sweep * fill * grow).coerceAtLeast(1f),
                    false,
                    topLeft,
                    arcSize,
                    style = Stroke(stroke, cap = StrokeCap.Round),
                )
            }
            cursor += slice
        }
    }
}

/** One bar per exercise: taller = more sets, filled from the bottom as they are done, current outlined. */
@Composable
private fun ExerciseBars(totals: List<Int>, dones: List<Int>, currentIndex: Int) {
    val dense = totals.size > 8
    val barWidth = if (dense) 6.dp else 10.dp
    Row(
        horizontalArrangement = Arrangement.spacedBy(if (dense) 3.dp else 4.5.dp),
        verticalAlignment = Alignment.Bottom,
        modifier = Modifier.height(22.dp),
    ) {
        totals.forEachIndexed { i, total ->
            val shape = RoundedCornerShape(3.dp)
            val fill = if (total > 0) dones[i].toFloat() / total else 0f
            val height = (6f + 15f * total.coerceAtMost(8) / 8f).dp
            Box(
                Modifier
                    .width(barWidth)
                    .height(height)
                    .background(GlanceTrack, shape)
                    .then(
                        if (i == currentIndex) Modifier.border(1.dp, Color.White, shape) else Modifier,
                    ),
                contentAlignment = Alignment.BottomCenter,
            ) {
                if (fill > 0f) {
                    Box(
                        Modifier
                            .width(barWidth)
                            .fillMaxHeight(fill)
                            .background(GlanceBlue, shape),
                    )
                }
            }
        }
    }
}
