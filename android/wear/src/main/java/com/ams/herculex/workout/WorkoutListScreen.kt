package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
fun WorkoutListScreen(navController: NavController, viewModel: WorkoutViewModel) {
    val workouts by viewModel.workouts.collectAsState()
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
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "Workouts",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }

        // Routine Templates
        items(workouts) { workout ->
            OneUiPill(
                title = workout.name,
                subtitle = "${workout.exercises.size} exercises",
                icon = "🏋️",
                style = OneUiPillStyle.SlateNavy,
                onClick = { navController.navigate("workout_detail/${workout.id}") },
            )
        }

        // Start Empty Workout button at the bottom of the list
        item {
            OneUiPill(
                title = "Empty Workout",
                icon = "+",
                style = OneUiPillStyle.AccentBlue,
                onClick = {
                    viewModel.startEmptyWorkout()
                    navController.navigate("active_workout")
                },
            )
        }
    }
}
