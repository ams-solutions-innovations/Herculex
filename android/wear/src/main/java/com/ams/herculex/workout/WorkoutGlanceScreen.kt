package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
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
 * Minimal glance page reached by swiping down from the set logger: just the time and how far
 * through the workout you are, for a quick glance without the full logging UI in the way.
 */
@Composable
fun WorkoutGlanceScreen(session: WorkoutSession) {
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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = timeText,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 40.sp,
        )
        Spacer(Modifier.height(14.dp))
        Box(
            modifier = Modifier
                .size(90.dp)
                .background(Color(0xFF1B1F2C), shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator(
                progress = progress,
                modifier = Modifier.fillMaxSize(),
                indicatorColor = Color(0xFF1565C0),
                trackColor = Color(0xFF1B1F2C),
                strokeWidth = 6.dp,
            )
            Text(
                text = percentText,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = "$completedSets/$targetSets sets",
            color = Color(0xFF9098AA),
            fontSize = 12.sp,
        )
    }
}
