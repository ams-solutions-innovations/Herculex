package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

@Composable
fun ExerciseOptionsScreen(navController: NavController, viewModel: WorkoutViewModel) {
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
                    "Workout Options",
                    color = Color(0xFF9E9E9E),
                    fontSize = 12.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }

        // Add Exercise
        item {
            OneUiPill(
                title = "Add Exercise",
                icon = "+",
                style = OneUiPillStyle.SlateNavy,
                onClick = { navController.navigate("select_exercise/add/-1") },
            )
        }

        // Substitute Exercise
        item {
            OneUiPill(
                title = "Substitute Exercise",
                icon = "⇄",
                style = OneUiPillStyle.SlateNavy,
                onClick = { navController.navigate("manage_exercise/substitute") },
            )
        }

        // Remove Exercise
        item {
            OneUiPill(
                title = "Remove Exercise",
                icon = "✕",
                style = OneUiPillStyle.SlateNavy,
                onClick = { navController.navigate("manage_exercise/remove") },
            )
        }
    }
}
