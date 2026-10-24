package com.ams.herculex.workout

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

private val ActiveHeartColor = Color(0xFFFF453A)
private val ActiveFlameColor = Color(0xFFFFA726)

@Composable
fun ActiveWorkoutScreen(navController: NavController, viewModel: WorkoutViewModel) {
    val session by viewModel.session.collectAsState()
    val elapsed by viewModel.elapsedSeconds.collectAsState()
    val heartRate by viewModel.heartRate.collectAsState()

    var showFinishDialog by remember { mutableStateOf(false) }
    var showDiscardDialog by remember { mutableStateOf(false) }

    val listState = rememberScalingLazyListState()

    // If session was discarded/finished externally, navigate to summary or pop back to home
    LaunchedEffect(session) {
        if (session == null) {
            if (viewModel.finishedWorkoutSummary.value != null) {
                navController.navigate("workout_summary") {
                    popUpTo("home") { inclusive = false }
                }
            } else {
                navController.popBackStack("home", inclusive = false)
            }
        }
    }

    val s = session ?: return
    val minutes = elapsed / 60
    val seconds = elapsed % 60
    val hrDisplay = if (heartRate > 0) "$heartRate" else "-"

    val beat by rememberInfiniteTransition(label = "activeWorkoutBeat").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1070, easing = LinearEasing), RepeatMode.Reverse),
        label = "activeWorkoutBeatValue",
    )

    var dragX by remember { mutableStateOf(0f) }
    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            // Swipe right = back ("nazaj"); swipe left = jump into current exercise
            // (the nav host's swipe-to-dismiss is disabled on this route, see MainActivity).
            .pointerInput(s.currentExerciseIndex) {
                detectHorizontalDragGestures(
                    onDragStart = { dragX = 0f },
                    onDragEnd = {
                        if (dragX > 60f) {
                            if (!navController.popBackStack()) {
                                navController.navigate("home")
                            }
                        } else if (dragX < -60f) {
                            val idx = s.currentExerciseIndex.coerceIn(0, (s.exercises.size - 1).coerceAtLeast(0))
                            if (s.exercises.isNotEmpty()) {
                                viewModel.selectExerciseInSession(idx)
                                navController.navigate("set_logger/$idx")
                            }
                        }
                        dragX = 0f
                    },
                    onDragCancel = { dragX = 0f },
                    onHorizontalDrag = { _, delta -> dragX += delta },
                )
            }
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
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(
                            HxIcons.Heart,
                            contentDescription = null,
                            tint = ActiveHeartColor,
                            modifier = Modifier.size(14.dp).scale(1f + 0.14f * beat),
                        )
                        Text(hrDisplay, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(
                            HxIcons.Flame,
                            contentDescription = null,
                            tint = ActiveFlameColor,
                            modifier = Modifier.size(14.dp),
                        )
                        Text("-", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
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
                val targetPlannedSet = exercise.template.plannedSets.firstOrNull { it.setIndex == targetOrLastSet?.setIndex }
                    ?: exercise.template.plannedSets.firstOrNull()
                val weight = targetOrLastSet?.weight?.takeIf { it > 0 }
                    ?: targetPlannedSet?.targetWeightKg?.takeIf { it > 0 }
                    ?: exercise.template.prevWeight
                val reps = targetOrLastSet?.reps?.takeIf { it > 0 }
                    ?: targetPlannedSet?.targetReps?.takeIf { it > 0 }
                    ?: targetPlannedSet?.targetRepsMin?.takeIf { it > 0 }
                    ?: exercise.template.prevReps
                val duration = targetOrLastSet?.durationSeconds?.takeIf { it > 0 }
                    ?: targetPlannedSet?.durationSeconds
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
                    weight > 0 && reps > 0 -> "${if (exercise.template.isAssistanceLoad()) "Assist " else ""}$weightStr kg × $reps"
                    weight > 0 -> "$weightStr kg"
                    reps > 0 -> "$reps reps"
                    exercise.template.performanceHint != null -> exercise.template.performanceHint
                    else -> null
                }

                val sGroup = exercise.supersetGroup ?: exercise.template.supersetGroup
                val groupRows = if (sGroup != null) s.exercises.filter { (it.supersetGroup ?: it.template.supersetGroup) == sGroup } else emptyList()
                val isLinked = groupRows.size > 1
                val groupIndex = groupRows.indexOf(exercise)
                val isFirst = groupIndex == 0
                val isLast = groupIndex == groupRows.size - 1

                val effortTarget = buildList {
                    targetPlannedSet?.targetRpe?.let { add("RPE ${"%.1f".format(it)}") }
                    targetPlannedSet?.targetRir?.let { add("RIR $it") }
                    targetPlannedSet?.targetPercentOf1Rm?.let { add("${"%.0f".format(it)}% 1RM") }
                }.joinToString(" • ")
                val targetSummary = listOfNotNull(infoStr, effortTarget.takeIf { it.isNotBlank() }).joinToString(" • ")
                val statLabelText = if (targetSummary.isNotBlank()) "Target • $targetSummary" else "Sets"

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .drawBehind {
                            if (isLinked) {
                                val strokeWidth = 3.dp.toPx()
                                val lineX = strokeWidth / 2f
                                val extraY = 4.dp.toPx()
                                val startY = if (isFirst) 16.dp.toPx() else -extraY
                                val endY = if (isLast) size.height - 16.dp.toPx() else size.height + extraY
                                drawLine(
                                    color = Color(0xFF1565C0),
                                    start = androidx.compose.ui.geometry.Offset(lineX, startY),
                                    end = androidx.compose.ui.geometry.Offset(lineX, endY),
                                    strokeWidth = strokeWidth,
                                    cap = androidx.compose.ui.graphics.StrokeCap.Round
                                )
                            }
                        }
                ) {
                    OneUiPill(
                        modifier = Modifier.padding(start = if (isLinked) 12.dp else 0.dp),
                        title = exercise.template.name,
                        statValue = "${exercise.sets.count { it.completed && !it.isWarmup }}/${exercise.workingSetTotal}",
                        statLabel = statLabelText,
                        iconComposable = {
                            ExerciseArtwork(
                                name = exercise.template.name,
                                slug = exercise.template.slug,
                                size = 38.dp,
                            )
                        },
                        style = if (isCurrent) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy,
                        onClick = {
                            viewModel.selectExerciseInSession(index)
                            navController.navigate("set_logger/$index")
                        },
                    )
                }
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
        val prs by viewModel.sessionPrs.collectAsState()
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
                            text = s.template.name,
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            text = "%d:%02d".format(minutes, seconds),
                            color = Color(0xFF9E9E9E),
                            fontSize = 13.sp,
                        )
                        if (prs.isNotEmpty()) {
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = "${prs.size} PRs achieved! 🏆",
                                color = Color(0xFFFFD60A),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }

                item {
                    OneUiPill(
                        title = "Save Workout",
                        icon = "✓",
                        style = OneUiPillStyle.EmeraldGreen,
                        onClick = {
                            showFinishDialog = false
                            viewModel.finishWorkout(saveAsTemplate = false)
                            navController.navigate("workout_summary") {
                                popUpTo("home") { inclusive = false }
                            }
                        },
                    )
                }
                
                item {
                    OneUiPill(
                        title = "Save as Template",
                        icon = "💾",
                        style = OneUiPillStyle.AccentBlue,
                        onClick = {
                            showFinishDialog = false
                            viewModel.finishWorkout(saveAsTemplate = true)
                            navController.navigate("workout_summary") {
                                popUpTo("home") { inclusive = false }
                            }
                        },
                    )
                }

                item {
                    OneUiPill(
                        title = "Cancel",
                        icon = "▶",
                        style = OneUiPillStyle.SlateNavy,
                        onClick = { showFinishDialog = false },
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
