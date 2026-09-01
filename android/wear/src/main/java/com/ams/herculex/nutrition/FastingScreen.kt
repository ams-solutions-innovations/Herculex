package com.ams.herculex.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun FastingScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    val fasting = data.fastingSnapshot
    var nowEpochMs by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(fasting.hasActiveFast, fasting.startedAtEpochMs) {
        while (true) {
            nowEpochMs = System.currentTimeMillis()
            delay(1_000)
        }
    }

    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val timeText = timeFormat.format(Date(nowEpochMs))

    val nextFormatted = fasting.nextFastFormatted(nowEpochMs)
    val progress = fasting.progress(nowEpochMs)

    // Elapsed timer calculation
    val elapsedSec = fasting.elapsedSeconds(nowEpochMs)
    val elapsedHours = elapsedSec / 3600L
    val elapsedMinutes = (elapsedSec % 3600L) / 60L
    val elapsedSeconds = elapsedSec % 60L

    val timerDisplay = if (fasting.hasActiveFast) {
        if (elapsedHours > 0) {
            "%d:%02d:%02d".format(elapsedHours, elapsedMinutes, elapsedSeconds)
        } else {
            "%02d:%02d".format(elapsedMinutes, elapsedSeconds)
        }
    } else if (nextFormatted != null) {
        fasting.timeUntilNextFast(nowEpochMs) ?: "--:--"
    } else {
        data.fasting
    }

    val progressPercent = (progress * 100).toInt()
    val targetHours = fasting.targetSeconds / 3600L
    val targetRemainingSec = (fasting.targetSeconds - elapsedSec).coerceAtLeast(0L)
    val remHours = targetRemainingSec / 3600L
    val remMinutes = (targetRemainingSec % 3600L) / 60L

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        // Full-bezel active timer ring hugging the watch edge (classic timer watchface)
        CircularProgressIndicator(
            progress = if (fasting.hasActiveFast) progress else if (nextFormatted != null) 0.05f else 0f,
            modifier = Modifier
                .fillMaxSize()
                .padding(6.dp),
            indicatorColor = if (fasting.hasActiveFast) Color(0xFF64D2FF) else Color(0xFF0B6E4F),
            trackColor = Color(0xFF1E1A2E),
            strokeWidth = 8.dp,
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Header: Local clock time & fasting label
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = timeText,
                    color = Color(0xFF9098AA),
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                )
                Text(
                    text = "•",
                    color = Color(0xFF555D6E),
                    fontSize = 11.sp,
                )
                Text(
                    text = if (fasting.hasActiveFast) "FASTING" else if (nextFormatted != null) "NEXT FAST" else "READY",
                    color = Color(0xFFD1C4E9),
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp,
                )
            }

            Spacer(Modifier.height(2.dp))

            // Prominent Main Timer Readout
            Text(
                text = timerDisplay,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = if (timerDisplay.length > 7) 28.sp else 34.sp,
                textAlign = TextAlign.Center,
            )

            // Stage / Target Subtitle
            if (fasting.hasActiveFast) {
                val subtitleText = if (targetRemainingSec > 0) {
                    "$progressPercent% • ${remHours}h ${remMinutes}m left"
                } else {
                    "$progressPercent% • Goal reached!"
                }
                Text(
                    text = subtitleText,
                    color = Color(0xFFBBDEFB),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                )

                if (fasting.currentStageMessage != null) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "🔥 ${fasting.currentStageMessage}",
                        color = Color(0xFF64D2FF),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            } else if (nextFormatted != null) {
                val plan = fasting.nextFastPlanName ?: "16:8"
                Text(
                    text = "$nextFormatted • $plan",
                    color = Color(0xFF64D2FF),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                )
            } else {
                val lastFastSecs = fasting.lastFastDurationSeconds
                val lastText = if (lastFastSecs != null) {
                    val h = lastFastSecs / 3600L
                    val m = (lastFastSecs % 3600L) / 60L
                    "Last: ${h}h ${m}m"
                } else {
                    "16:8 Plan • 16h target"
                }
                Text(
                    text = lastText,
                    color = Color(0xFF9098AA),
                    fontSize = 11.sp,
                )
            }

            Spacer(Modifier.height(8.dp))

            // Action Button: Stop Fast / Start Fast
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
                    .height(34.dp)
                    .padding(horizontal = 6.dp),
                shape = RoundedCornerShape(17.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = if (fasting.hasActiveFast) "⏹" else "▶",
                        fontSize = 11.sp,
                    )
                    Text(
                        text = if (fasting.hasActiveFast) "Stop Fast" else "Start Fast",
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}
