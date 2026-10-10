package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
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
    val session by viewModel.session.collectAsState()
    val keepAwake by WorkoutSettings.keepAwake.collectAsState()
    val context = LocalContext.current

    // If session was discarded/finished, pop back to home
    LaunchedEffect(session) {
        if (session == null) navController.popBackStack("home", inclusive = false)
    }

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
                style = OneUiPillStyle.AccentBlue,
                onClick = { navController.navigate("select_exercise/add/-1") },
            )
        }

        // Substitute Exercise
        item {
            OneUiPill(
                title = "Substitute Exercise",
                icon = "⇄",
                style = OneUiPillStyle.RoyalBlue,
                onClick = { navController.navigate("manage_exercise/substitute") },
            )
        }

        // Remove Exercise
        item {
            OneUiPill(
                title = "Remove Exercise",
                icon = "✕",
                style = OneUiPillStyle.DangerTransparent,
                onClick = { navController.navigate("manage_exercise/remove") },
            )
        }

        // Keep the screen on for the whole workout (applied in MainActivity).
        item {
            OneUiPill(
                title = "Keep awake",
                subtitle = "while workout",
                icon = "☀",
                style = OneUiPillStyle.SlateNavy,
                rightContent = { KeepAwakeSwitch(checked = keepAwake) },
                onClick = { WorkoutSettings.setKeepAwake(context, !keepAwake) },
            )
        }
    }
}

/// Compact on/off switch for [OneUiPill]'s trailing slot.
@Composable
private fun KeepAwakeSwitch(checked: Boolean) {
    Box(
        modifier = Modifier
            .size(width = 34.dp, height = 20.dp)
            .background(if (checked) Color(0xFF42A5F5) else Color(0xFF3D4559), CircleShape),
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .offset(x = if (checked) 16.dp else 2.dp)
                .size(16.dp)
                .background(Color.White, CircleShape),
        )
    }
}
