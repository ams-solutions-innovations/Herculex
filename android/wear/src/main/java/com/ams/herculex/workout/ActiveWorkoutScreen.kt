package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.media.CompactMediaControls
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

@Composable
fun ActiveWorkoutScreen(navController: NavController, viewModel: WorkoutViewModel) {
    val session by viewModel.session.collectAsState()
    val elapsed by viewModel.elapsedSeconds.collectAsState()
    val heartRate by viewModel.heartRate.collectAsState()

    val listState = rememberScalingLazyListState()

    // If session was discarded/finished, pop back to home
    LaunchedEffect(session) {
        if (session == null) navController.popBackStack("home", inclusive = false)
    }

    val s = session ?: return
    val minutes = elapsed / 60
    val seconds = elapsed % 60
    val hrDisplay = if (heartRate > 0) "$heartRate" else "-"

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 40.dp, bottom = 48.dp, start = 14.dp, end = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Header: name + timer + HR/calories
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(s.template.name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Text(
                    text = "%d:%02d".format(minutes, seconds),
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 30.sp,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text("❤️", fontSize = 13.sp)
                        Text(hrDisplay, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text("🔥", fontSize = 13.sp)
                        Text("-", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }

        item {
            CompactMediaControls()
        }

        // Empty state when no exercises exist
        if (s.exercises.isEmpty()) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("No exercises added", color = Color(0xFF9E9E9E), fontSize = 13.sp)
                    Spacer(Modifier.height(8.dp))
                    OneUiPill(
                        title = "Add Exercise",
                        icon = "+",
                        style = OneUiPillStyle.AccentBlue,
                        onClick = { navController.navigate("select_exercise/add/-1") },
                    )
                }
            }
        } else {
            // Exercise list
            itemsIndexed(s.exercises) { index, exercise ->
                val isCurrent = index == s.currentExerciseIndex
                val targetOrLastSet = exercise.sets.firstOrNull { !it.completed } ?: exercise.sets.lastOrNull()
                val weight = targetOrLastSet?.weight?.takeIf { it > 0 } ?: exercise.template.prevWeight
                val reps = targetOrLastSet?.reps?.takeIf { it > 0 } ?: exercise.template.prevReps

                val weightStr = if (weight % 1.0 == 0.0) "${weight.toInt()}" else "$weight"
                val infoStr = when {
                    weight > 0 && reps > 0 -> "$weightStr kg × $reps"
                    weight > 0 -> "$weightStr kg"
                    reps > 0 -> "$reps reps"
                    else -> null
                }
                val statLabelText = if (infoStr != null) "Sets • $infoStr" else "Sets"

                OneUiPill(
                    title = exercise.template.name,
                    statValue = "${exercise.completedSets}/${exercise.template.targetSets}",
                    statLabel = statLabelText,
                    icon = null,
                    style = if (isCurrent) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy,
                    onClick = {
                        viewModel.selectExerciseInSession(index)
                        navController.navigate("set_logger/$index")
                    },
                )
            }
        }

        // Options button at the bottom
        item {
            OneUiPill(
                title = "Workout Options",
                icon = "⚙️",
                style = OneUiPillStyle.DarkSlateButton,
                onClick = { navController.navigate("exercise_options") },
            )
        }

        // Finish Workout
        item {
            OneUiPill(
                title = "Finish Workout",
                icon = "✓",
                style = OneUiPillStyle.AccentBlue,
                onClick = {
                    viewModel.finishWorkout()
                    navController.popBackStack("home", inclusive = false)
                },
            )
        }

        // Discard Workout
        item {
            OneUiPill(
                title = "Discard Workout",
                icon = "🗑️",
                style = OneUiPillStyle.DangerTransparent,
                onClick = {
                    viewModel.discardWorkout()
                    navController.popBackStack("home", inclusive = false)
                },
            )
        }
    }
}
