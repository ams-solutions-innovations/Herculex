package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

@Composable
fun ManageExerciseScreen(
    navController: NavController,
    viewModel: WorkoutViewModel,
    action: String, // "remove" or "substitute"
) {
    val session by viewModel.session.collectAsState()

    // If session was discarded/finished, pop back to home
    LaunchedEffect(session) {
        if (session == null) navController.popBackStack("home", inclusive = false)
    }

    val s = session ?: return

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
                    text = if (action == "remove") "Remove Exercise" else "Substitute Exercise",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }

        itemsIndexed(s.exercises) { index, exercise ->
            OneUiPill(
                title = exercise.template.name,
                iconComposable = {
                    ExerciseArtwork(
                        name = exercise.template.name,
                        slug = exercise.template.slug,
                        size = 38.dp,
                    )
                },
                rightContent = {
                    Text(
                        text = if (action == "remove") "✕" else "⇄",
                        color = if (action == "remove") Color(0xFFEF5350) else Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                    )
                },
                style = if (action == "remove") OneUiPillStyle.DangerTransparent else OneUiPillStyle.RoyalBlue,
                onClick = {
                    if (action == "remove") {
                        viewModel.removeExerciseFromSession(index)
                        navController.popBackStack()
                    } else {
                        navController.navigate("select_exercise/substitute/$index")
                    }
                },
            )
        }
    }
}
