package com.ams.herculex.nutrition

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import kotlinx.coroutines.delay

private val RingTrack = Color(0xFF2C1E4A)
private val RingProgress = Color(0xFF64D2FF)
private val RingScheduled = Color(0xFF0B6E4F)

/** `H:MM` — the 46sp readout has no room for "14h 32m". */
private fun formatHm(totalSeconds: Long): String =
    "%d:%02d".format(totalSeconds / 3600L, (totalSeconds % 3600L) / 60L)

@Composable
fun FastingScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    val fasting = data.fastingSnapshot
    var nowEpochMs by remember { mutableLongStateOf(System.currentTimeMillis()) }

    // Ticks while idle too: the countdown to the next scheduled fast has to move.
    LaunchedEffect(fasting.hasActiveFast, fasting.startedAtEpochMs) {
        while (true) {
            nowEpochMs = System.currentTimeMillis()
            delay(1_000)
        }
    }

    val nextFastMs = fasting.nextFastEpochMs
    val nextFormatted = fasting.nextFastFormatted(nowEpochMs)
    val progress = fasting.progress(nowEpochMs)
    val progressPercent = (progress * 100).toInt()
    val elapsedSec = fasting.elapsedSeconds(nowEpochMs)
    val remainingSec = (fasting.targetSeconds - elapsedSec).coerceAtLeast(0L)

    val readout = when {
        fasting.hasActiveFast -> formatHm(elapsedSec)
        nextFastMs != null -> formatHm(((nextFastMs - nowEpochMs) / 1000L).coerceAtLeast(0L))
        else -> "0:00"
    }
    val readoutCaption = when {
        fasting.hasActiveFast -> "elapsed · $progressPercent%"
        nextFastMs != null -> "until next fast"
        else -> "idle"
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        // Progress ring around the whole bezel, clockwise from 12 o'clock.
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokePx = 8.dp.toPx()
            val inset = 8.5.dp.toPx()
            val topLeft = Offset(inset, inset)
            val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
            drawArc(
                color = RingTrack,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = strokePx),
            )
            // Active: real progress. Idle with a scheduled fast: a short green
            // stub, so the ring shows that something is coming.
            val sweepFraction = when {
                fasting.hasActiveFast -> progress
                nextFastMs != null -> 0.05f
                else -> 0f
            }
            if (sweepFraction > 0f) {
                drawArc(
                    color = if (fasting.hasActiveFast) RingProgress else RingScheduled,
                    startAngle = -90f,
                    sweepAngle = 360f * sweepFraction,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = strokePx, cap = StrokeCap.Round),
                )
            }
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "FASTING TIMER",
                color = Color.Gray,
                fontSize = 11.sp,
                lineHeight = 13.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(5.dp))
            Text(
                text = readout,
                color = Color(0xFFD1C4E9), // Light purple
                fontSize = 46.sp,
                lineHeight = 54.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = readoutCaption,
                color = Color(0xFFD3D3D3),
                fontSize = 12.sp,
                lineHeight = 14.sp,
                maxLines = 1,
            )
            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    if (fasting.hasActiveFast) {
                        nutritionViewModel.stopFast()
                    } else {
                        nutritionViewModel.startFast()
                    }
                },
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = if (fasting.hasActiveFast) Color(0xFF7A2434) else Color(0xFF0B6E4F)
                ),
                modifier = Modifier
                    .width(110.dp)
                    .height(40.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (fasting.hasActiveFast) HxIcons.Stop else HxIcons.Play,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(if (fasting.hasActiveFast) "Stop Fast" else "Start Fast", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }

            // One fixed-height line, so the layout doesn't jump between states:
            // the current stage / time left while fasting, the next scheduled
            // fast while idle, otherwise how long the last one ran.
            Box(
                modifier = Modifier.height(18.dp),
                contentAlignment = Alignment.BottomCenter,
            ) {
                val lastFastSeconds = fasting.lastFastDurationSeconds
                val stage = fasting.currentStageMessage
                when {
                    fasting.hasActiveFast && remainingSec == 0L -> Text(
                        text = "Goal reached!",
                        color = Color(0xFF64D2FF),
                        fontSize = 10.sp,
                        lineHeight = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                    )
                    fasting.hasActiveFast && stage != null -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = HxIcons.Flame,
                            contentDescription = null,
                            tint = Color(0xFF64D2FF),
                            modifier = Modifier.size(11.dp),
                        )
                        Spacer(modifier = Modifier.width(3.dp))
                        Text(
                            text = stage,
                            color = Color(0xFF64D2FF),
                            fontSize = 10.sp,
                            lineHeight = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    fasting.hasActiveFast -> Text(
                        text = "${remainingSec / 3600L}h ${(remainingSec % 3600L) / 60L}m left",
                        color = Color(0xFFBBDEFB),
                        fontSize = 10.sp,
                        lineHeight = 12.sp,
                        maxLines = 1,
                    )
                    nextFormatted != null -> Text(
                        text = "$nextFormatted • ${fasting.nextFastPlanName ?: "16:8"}",
                        color = Color(0xFF64D2FF),
                        fontSize = 10.sp,
                        lineHeight = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    lastFastSeconds != null -> Text(
                        text = "Last: ${lastFastSeconds / 3600L}h ${(lastFastSeconds % 3600L) / 60L}m",
                        color = Color.Gray,
                        fontSize = 10.sp,
                        lineHeight = 12.sp,
                    )
                    else -> Unit
                }
            }
        }
    }
}
