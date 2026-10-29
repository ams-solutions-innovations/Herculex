package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
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
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.R

@Composable
fun WorkoutListScreen(navController: NavController, viewModel: WorkoutViewModel) {
    val workouts by viewModel.workouts.collectAsState()
    val session by viewModel.session.collectAsState()
    val listState = rememberScalingLazyListState()

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        Image(
            painter = painterResource(R.drawable.hx_glow_workout),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.FillBounds,
        )
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
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
                        "HERCULEX",
                        color = Color(0xFF42A5F5),
                        fontWeight = FontWeight.Bold,
                        fontSize = 10.sp,
                        letterSpacing = 1.sp,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }
            }

            // Same as the tile: a running workout shows Resume first.
            if (session != null) {
                item {
                    OneUiPill(
                        title = "Resume Workout",
                        subtitle = "In progress",
                        iconVector = HxIcons.Play,
                        style = OneUiPillStyle.EmeraldGreen,
                        shimmer = true,
                        onClick = { navController.navigate("active_workout") },
                    )
                }
            }

            // Routine Templates
            // Today's scheduled workout comes first (WorkoutStore sorts it up) and is
            // highlighted so it can be started without hunting through the list.
            items(workouts) { workout ->
                val today = workout.scheduledToday
                OneUiPill(
                    title = if (today) workout.scheduleTitle ?: workout.name else workout.name,
                    subtitle = if (today) "Today · ${workout.exercises.size} exercises"
                    else "${workout.exercises.size} exercises",
                    iconVector = HxIcons.Dumbbell,
                    shimmer = today,
                    style = if (today) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy,
                    onClick = { navController.navigate("workout_detail/${workout.id}") },
                )
            }

            // Start Empty Workout button at the bottom of the list
            item {
                OneUiPill(
                    title = "Empty Workout",
                    iconVector = HxIcons.Plus,
                    style = OneUiPillStyle.AccentBlue,
                    onClick = {
                        viewModel.startEmptyWorkout()
                        navController.navigate("active_workout")
                    },
                )
            }
        }
    }
}
