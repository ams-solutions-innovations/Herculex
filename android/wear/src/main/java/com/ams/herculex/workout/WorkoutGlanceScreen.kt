package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Minimal glance page reached by swiping down from the set logger: time, workout completion %,
 * completed sets, elapsed workout duration, and real-time heart rate.
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

    val completedSets = session.exercises.sumOf { it.completedSets }
    val targetSets = session.exercises.sumOf { it.template.targetSets }
    val progress = if (targetSets > 0) (completedSets.toFloat() / targetSets).coerceIn(0f, 1f) else 0f
    val percentText = "${(progress * 100).toInt()}%"

    val elapsedHours = elapsedSeconds / 3600
    val elapsedMinutes = (elapsedSeconds % 3600) / 60
    val elapsedSecs = elapsedSeconds % 60
    val elapsedDisplay = if (elapsedHours > 0) {
        "%d:%02d:%02d".format(elapsedHours, elapsedMinutes, elapsedSecs)
    } else {
        "%d:%02d".format(elapsedMinutes, elapsedSecs)
    }
    val hrDisplay = if (heartRate > 0) "$heartRate" else "--"

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        // Full-bezel ring, like a classic round timer face, instead of a
        // small inset circle — hugs the edge of the watch screen.
        CircularProgressIndicator(
            progress = progress,
            modifier = Modifier
                .fillMaxSize()
                .padding(6.dp),
            indicatorColor = Color(0xFF1976D2),
            trackColor = Color(0xFF1B1F2C),
            strokeWidth = 8.dp,
        )

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = timeText,
                color = Color(0xFF9098AA),
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                text = percentText,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 40.sp,
            )
            Text(
                text = "$completedSets/$targetSets sets",
                color = Color(0xFF9098AA),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text("⏱️", fontSize = 12.sp)
                    Text(
                        text = elapsedDisplay,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text("❤️", fontSize = 12.sp)
                    Text(
                        text = hrDisplay,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}
