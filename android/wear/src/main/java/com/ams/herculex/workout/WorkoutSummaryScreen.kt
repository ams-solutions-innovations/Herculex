package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text

/**
 * Apple Watch Workout App style summary recap screen shown after finishing a workout.
 */
@Composable
fun WorkoutSummaryScreen(
    navController: NavController,
    viewModel: WorkoutViewModel,
) {
    val summary by viewModel.finishedWorkoutSummary.collectAsState()
    val listState = rememberScalingLazyListState()

    val data = summary ?: run {
        // Fallback default if navigating without data
        WorkoutSummaryData(
            workoutName = "Workout Complete",
            durationSeconds = 0L,
            totalVolumeKg = 0.0,
            completedSets = 0,
            totalExercises = 0,
        )
    }

    val minutes = data.durationSeconds / 60
    val seconds = data.durationSeconds % 60
    val timeFormatted = "%d:%02d".format(minutes, seconds)

    val volumeFormatted = if (data.totalVolumeKg >= 1000) {
        val tons = data.totalVolumeKg / 1000.0
        "%.1f t".format(tons)
    } else {
        "${data.totalVolumeKg.toInt()} kg"
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 28.dp, bottom = 40.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        // Apple Fitness Header
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF30D158).copy(alpha = 0.2f))
                        .border(1.dp, Color(0xFF30D158), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("✓", color = Color(0xFF30D158), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "WORKOUT COMPLETE",
                    color = Color(0xFF8E8E93),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.6.sp,
                )
                Text(
                    text = data.workoutName,
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
        }

        // Apple Watch Stat Card 1: Time & Volume
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                // Time Card
                AppleStatCard(
                    modifier = Modifier.weight(1f),
                    label = "TIME",
                    value = timeFormatted,
                    accentColor = Color(0xFF30D158), // Apple Mint
                )
                // Volume Card
                AppleStatCard(
                    modifier = Modifier.weight(1f),
                    label = "VOLUME",
                    value = volumeFormatted,
                    accentColor = Color(0xFF64D2FF), // Apple Cyan
                )
            }
        }

        // Apple Watch Stat Card 2: Sets & Exercises
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                // Completed Sets
                AppleStatCard(
                    modifier = Modifier.weight(1f),
                    label = "SETS",
                    value = "${data.completedSets}",
                    subLabel = "completed",
                    accentColor = Color(0xFFBF5AF2), // Apple Purple
                )
                // Total Exercises
                AppleStatCard(
                    modifier = Modifier.weight(1f),
                    label = "EXERCISES",
                    value = "${data.totalExercises}",
                    subLabel = "performed",
                    accentColor = Color(0xFFFF9F0A), // Apple Orange
                )
            }
        }

        // Apple Watch PR Highlights (if any PRs were hit during this workout)
        if (data.prCount > 0) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF1C1C1E))
                        .border(1.dp, Color(0xFFFFD60A).copy(alpha = 0.6f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                ) {
                    Column {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            Text("🏆", fontSize = 14.sp)
                            Text(
                                text = "${data.prCount} NEW RECORD${if (data.prCount > 1) "S" else ""}",
                                color = Color(0xFFFFD60A),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = 0.5.sp,
                            )
                        }
                        Spacer(Modifier.height(4.dp))
                        data.prList.take(3).forEach { pr ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 1.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = pr.exerciseName,
                                    color = Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    text = pr.valueText,
                                    color = Color(0xFF64D2FF),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        }
                    }
                }
            }
        }

        // Heart rate (if tracked)
        if (data.avgHeartRate > 0) {
            item {
                AppleStatCard(
                    modifier = Modifier.fillMaxWidth(),
                    label = "AVG HEART RATE",
                    value = "${data.avgHeartRate} BPM",
                    accentColor = Color(0xFFFF453A),
                )
            }
        }

        // Apple Watch "Done" Action Button
        item {
            Spacer(Modifier.height(4.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color(0xFF30D158)) // Apple Bright Mint Button
                    .clickable {
                        viewModel.clearFinishedSummary()
                        navController.popBackStack("home", inclusive = false)
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Done",
                    color = Color.Black,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.ExtraBold,
                )
            }
        }
    }
}

@Composable
private fun AppleStatCard(
    modifier: Modifier = Modifier,
    label: String,
    value: String,
    subLabel: String? = null,
    accentColor: Color,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF1C1C1E))
            .border(1.dp, Color(0xFF2C2C2E), RoundedCornerShape(14.dp))
            .padding(horizontal = 8.dp, vertical = 6.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.Start,
        ) {
            Text(
                text = label,
                color = Color(0xFF8E8E93),
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.5.sp,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                text = value,
                color = accentColor,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subLabel != null) {
                Text(
                    text = subLabel,
                    color = Color(0xFF636366),
                    fontSize = 8.5.sp,
                )
            }
        }
    }
}
