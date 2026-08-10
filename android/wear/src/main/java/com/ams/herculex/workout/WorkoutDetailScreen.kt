package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
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
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

@Composable
fun WorkoutDetailScreen(
    navController: NavController,
    viewModel: WorkoutViewModel,
    workoutId: String,
) {
    val workouts by viewModel.workouts.collectAsState()
    val workout = workouts.firstOrNull { it.id == workoutId } ?: return
    val listState = rememberScalingLazyListState()

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
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    workout.name,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                )
                Spacer(Modifier.height(6.dp))
                // Start button (One UI Royal Blue pill)
                OneUiPill(
                    title = "Start Workout",
                    icon = "▶",
                    style = OneUiPillStyle.RoyalBlue,
                    onClick = {
                        viewModel.startWorkout(workout)
                        navController.navigate("active_workout")
                    },
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "${workout.exercises.size} Exercises",
                    color = Color(0xFF9E9E9E),
                    fontSize = 11.sp,
                )
            }
        }

        items(workout.exercises) { ex ->
            OneUiPill(
                title = ex.name,
                subtitle = "${ex.targetSets} Sets",
                icon = null,
                style = OneUiPillStyle.SlateNavy,
            )
        }
    }
}
