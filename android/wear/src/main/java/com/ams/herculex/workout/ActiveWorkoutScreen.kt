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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import androidx.wear.compose.material.dialog.Dialog
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

@Composable
fun ActiveWorkoutScreen(navController: NavController, viewModel: WorkoutViewModel) {
    val session by viewModel.session.collectAsState()
    val elapsed by viewModel.elapsedSeconds.collectAsState()
    val heartRate by viewModel.heartRate.collectAsState()

    var showFinishDialog by remember { mutableStateOf(false) }
    var showDiscardDialog by remember { mutableStateOf(false) }

    val listState = rememberScalingLazyListState()

    // If session was discarded/finished externally, pop back to home
    LaunchedEffect(session) {
        if (session == null && viewModel.finishedWorkoutSummary.value == null) {
            navController.popBackStack("home", inclusive = false)
        }
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
                val isBodyweight = exercise.template.isBodyweightOnly()
                val isTimeBased = exercise.template.isTimeBased()
                val targetOrLastSet = exercise.sets.firstOrNull { !it.completed } ?: exercise.sets.lastOrNull()
                val weight = targetOrLastSet?.weight?.takeIf { it > 0 } ?: exercise.template.prevWeight
                val reps = targetOrLastSet?.reps?.takeIf { it > 0 } ?: exercise.template.prevReps
                val duration = targetOrLastSet?.durationSeconds?.takeIf { it > 0 }
                    ?: exercise.template.plannedSets.firstOrNull()?.durationSeconds

                val weightStr = if (weight % 1.0 == 0.0) "${weight.toInt()}" else "$weight"
                val durationStr = duration?.let {
                    val m = it / 60
                    val s = it % 60
                    if (m > 0) "%d:%02d".format(m, s) else "${s}s"
                }

                val infoStr = when {
                    isTimeBased && isBodyweight && durationStr != null -> durationStr
                    isTimeBased && durationStr != null && weight > 0 -> "$weightStr kg • $durationStr"
                    isTimeBased && durationStr != null -> durationStr
                    isBodyweight && reps > 0 -> "$reps reps"
                    weight > 0 && reps > 0 -> "$weightStr kg × $reps"
                    weight > 0 -> "$weightStr kg"
                    reps > 0 -> "$reps reps"
                    else -> null
                }

                val sGroup = exercise.supersetGroup ?: exercise.template.supersetGroup
                val groupCount = if (sGroup != null) s.exercises.count { (it.supersetGroup ?: it.template.supersetGroup) == sGroup } else 0
                val groupPrefix = if (groupCount >= 3) "🔁 " else if (groupCount == 2) "⚡ " else ""
                val statLabelText = if (infoStr != null) "Sets • $infoStr" else "Sets"

                OneUiPill(
                    title = "$groupPrefix${exercise.template.name}",
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
                onClick = { showFinishDialog = true },
            )
        }

        // Discard Workout
        item {
            OneUiPill(
                title = "Discard Workout",
                icon = "🗑️",
                style = OneUiPillStyle.DangerTransparent,
                onClick = { showDiscardDialog = true },
            )
        }
    }

    if (showFinishDialog) {
        val finishListState = rememberScalingLazyListState()
        Dialog(
            showDialog = showFinishDialog,
            onDismissRequest = { showFinishDialog = false },
        ) {
            ScalingLazyColumn(
                state = finishListState,
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
                    .attachRotaryScroll(finishListState),
                autoCentering = null,
                contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 14.dp, end = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "Finish Workout?",
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            text = "Save and complete session",
                            color = Color(0xFF9E9E9E),
                            fontSize = 11.sp,
                        )
                    }
                }

                // Resume button
                item {
                    OneUiPill(
                        title = "Resume",
                        subtitle = "Continue workout",
                        icon = "▶",
                        style = OneUiPillStyle.SlateNavy,
                        onClick = { showFinishDialog = false },
                    )
                }

                // Confirm Finish button
                item {
                    OneUiPill(
                        title = "Finish",
                        subtitle = "Save workout",
                        icon = "✓",
                        style = OneUiPillStyle.EmeraldGreen,
                        onClick = {
                            showFinishDialog = false
                            viewModel.finishWorkout()
                            navController.navigate("workout_summary") {
                                popUpTo("home") { inclusive = false }
                            }
                        },
                    )
                }
            }
        }
    }

    if (showDiscardDialog) {
        val discardListState = rememberScalingLazyListState()
        Dialog(
            showDialog = showDiscardDialog,
            onDismissRequest = { showDiscardDialog = false },
        ) {
            ScalingLazyColumn(
                state = discardListState,
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
                    .attachRotaryScroll(discardListState),
                autoCentering = null,
                contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 14.dp, end = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "Discard Workout?",
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            text = "All progress will be lost",
                            color = Color(0xFFFF8A80),
                            fontSize = 11.sp,
                        )
                    }
                }

                // Resume button
                item {
                    OneUiPill(
                        title = "Resume",
                        subtitle = "Continue workout",
                        icon = "▶",
                        style = OneUiPillStyle.SlateNavy,
                        onClick = { showDiscardDialog = false },
                    )
                }

                // Confirm Discard button
                item {
                    OneUiPill(
                        title = "Discard",
                        subtitle = "Delete workout",
                        icon = "🗑️",
                        style = OneUiPillStyle.DangerTransparent,
                        onClick = {
                            showDiscardDialog = false
                            viewModel.discardWorkout()
                            navController.popBackStack("home", inclusive = false)
                        },
                    )
                }
            }
        }
    }
}
