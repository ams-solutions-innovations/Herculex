package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

@Composable
fun WorkoutDetailScreen(
    navController: NavController,
    viewModel: WorkoutViewModel,
    workoutId: String,
) {
    val context = LocalContext.current
    val workouts by viewModel.workouts.collectAsState()
    val activeSession by viewModel.session.collectAsState()

    // Resilient lookup: check ViewModel state first, fall back to synchronous WorkoutStore
    val workout = workouts.firstOrNull { it.id == workoutId }
        ?: remember(workoutId) { WorkoutStore.getById(context, workoutId) }

    if (workout == null) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Workout not found",
                color = Color(0xFF9E9E9E),
                fontSize = 13.sp,
            )
        }
        return
    }

    val isCurrentRunning = activeSession?.template?.id == workout.id
    val listState = rememberScalingLazyListState()

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 28.dp, bottom = 48.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Routine Header ──────────────────────────────────────────────
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (workout.scheduledToday) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        modifier = Modifier
                            .background(Color(0xFF132E78), CircleShape)
                            .border(0.8.dp, Color(0xFF1E44AA), CircleShape)
                            .padding(horizontal = 8.dp, vertical = 2.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(5.dp)
                                .background(Color(0xFF64D2FF), CircleShape)
                        )
                        Text(
                            text = (workout.scheduleTitle ?: "TODAY").uppercase(),
                            color = Color(0xFF64D2FF),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.5.sp,
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                }

                Text(
                    text = workout.name,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center,
                )

                val totalSets = workout.exercises.sumOf { it.targetSets }
                Text(
                    text = "${workout.exercises.size} Exercises · $totalSets Sets",
                    color = Color(0xFFA0AABF),
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Normal,
                    modifier = Modifier.padding(top = 2.dp, bottom = 8.dp),
                )

                OneUiPill(
                    title = if (isCurrentRunning) "Resume Workout" else "Start Workout",
                    iconVector = HxIcons.Play,
                    style = if (isCurrentRunning) OneUiPillStyle.EmeraldGreen else OneUiPillStyle.RoyalBlue,
                    onClick = {
                        if (!isCurrentRunning) {
                            viewModel.startWorkout(workout)
                        }
                        navController.navigate("active_workout")
                    },
                )
            }
        }

        // ── Exercises Section Header ─────────────────────────────────────
        if (workout.exercises.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 6.dp, end = 6.dp, top = 6.dp, bottom = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "EXERCISES",
                        color = Color(0xFF8A94A6),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 0.6.sp,
                    )
                    Text(
                        text = "${workout.exercises.size}",
                        color = Color(0xFF8A94A6),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        // ── Exercises List ───────────────────────────────────────────────
        if (workout.exercises.isEmpty()) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = "No exercises in this routine",
                        color = Color(0xFF9E9E9E),
                        fontSize = 12.sp,
                    )
                }
            }
        } else {
            itemsIndexed(workout.exercises) { index, ex ->
                val firstPlanned = ex.plannedSets.firstOrNull()
                val weight = firstPlanned?.targetWeightKg?.takeIf { it > 0 } ?: ex.prevWeight
                val reps = firstPlanned?.targetReps?.takeIf { it > 0 }
                    ?: firstPlanned?.targetRepsMin?.takeIf { it > 0 }
                    ?: ex.prevReps
                val duration = firstPlanned?.durationSeconds
                val weightStr = if (weight % 1.0 == 0.0) "${weight.toInt()}" else "$weight"
                val durationStr = duration?.let {
                    val m = it / 60
                    val s = it % 60
                    if (m > 0) "%d:%02d".format(m, s) else "${s}s"
                }
                val isBodyweight = ex.isBodyweightOnly()
                val isTime = ex.isTimeBased()
                val targetDetail = when {
                    isTime && isBodyweight && durationStr != null -> durationStr
                    isTime && durationStr != null && weight > 0 -> "$weightStr kg • $durationStr"
                    isTime && durationStr != null -> durationStr
                    isBodyweight && reps > 0 -> "$reps reps"
                    weight > 0 && reps > 0 -> "$weightStr kg × $reps"
                    weight > 0 -> "$weightStr kg"
                    reps > 0 -> "$reps reps"
                    else -> null
                }
                val setsText = "${ex.targetSets} sets"
                val subtitleText = if (targetDetail != null) "$setsText · $targetDetail" else setsText

                OneUiPill(
                    title = ex.name,
                    subtitle = subtitleText,
                    iconComposable = {
                        ExerciseArtwork(
                            name = ex.name,
                            slug = ex.slug,
                            size = 38.dp,
                        )
                    },
                    rightContent = {
                        Text(
                            text = "#${index + 1}",
                            color = Color(0xFF6B7280),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    },
                    style = OneUiPillStyle.SlateNavy,
                )
            }

            if (workout.exercises.size >= 4) {
                item {
                    Spacer(Modifier.height(4.dp))
                    OneUiPill(
                        title = if (isCurrentRunning) "Resume Workout" else "Start Workout",
                        iconVector = HxIcons.Play,
                        style = if (isCurrentRunning) OneUiPillStyle.EmeraldGreen else OneUiPillStyle.RoyalBlue,
                        onClick = {
                            if (!isCurrentRunning) {
                                viewModel.startWorkout(workout)
                            }
                            navController.navigate("active_workout")
                        },
                    )
                }
            }
        }
    }
}
