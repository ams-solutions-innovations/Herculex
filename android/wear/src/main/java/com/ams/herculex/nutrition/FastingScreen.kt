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

@Composable
fun FastingScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    val fasting = data.fastingSnapshot
    var nowEpochMs by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(fasting.hasActiveFast, fasting.startedAtEpochMs) {
        while (fasting.hasActiveFast) {
            nowEpochMs = System.currentTimeMillis()
            delay(1_000)
        }
    }

    // Big H:MM readout; "14h 32m" doesn't fit at 46sp.
    val elapsedText = if (fasting.hasActiveFast) {
        val elapsed = fasting.elapsedSeconds(nowEpochMs)
        "%d:%02d".format(elapsed / 3600L, (elapsed % 3600L) / 60L)
    } else {
        "0:00"
    }
    val progress = fasting.progress(nowEpochMs)

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
            if (fasting.hasActiveFast && progress > 0f) {
                drawArc(
                    color = RingProgress,
                    startAngle = -90f,
                    sweepAngle = 360f * progress,
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
                text = elapsedText,
                color = Color(0xFFD1C4E9), // Light purple
                fontSize = 46.sp,
                lineHeight = 54.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = if (fasting.hasActiveFast) "elapsed" else "idle",
                color = Color(0xFFD3D3D3),
                fontSize = 12.sp,
                lineHeight = 14.sp,
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

            // Fixed-height slot so the layout doesn't jump when "Last" appears.
            Box(
                modifier = Modifier.height(18.dp),
                contentAlignment = Alignment.BottomCenter,
            ) {
                if (!fasting.hasActiveFast && fasting.lastFastDurationSeconds != null) {
                    val h = fasting.lastFastDurationSeconds / 3600L
                    val m = (fasting.lastFastDurationSeconds % 3600L) / 60L
                    Text(
                        text = "Last: ${h}h ${m}m",
                        color = Color.Gray,
                        fontSize = 10.sp,
                        lineHeight = 12.sp,
                    )
                }
            }
        }
    }
}
