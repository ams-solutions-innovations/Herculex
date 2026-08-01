package com.ams.herculex.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
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
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import com.ams.herculex.nutrition.NutritionViewModel
import com.ams.herculex.sync.SyncService
import com.ams.herculex.workout.WorkoutViewModel
import com.ams.herculex.workout.attachRotaryScroll

@Composable
fun HomeScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
    workoutViewModel: WorkoutViewModel,
) {
    val context = LocalContext.current
    val data by nutritionViewModel.data.collectAsState()
    val session by workoutViewModel.session.collectAsState()
    val elapsed by workoutViewModel.elapsedSeconds.collectAsState()

    LaunchedEffect(Unit) {
        SyncService.requestSyncFromPhone(context)
    }

    val listState = rememberScalingLazyListState()

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 10.dp, bottom = 20.dp, start = 10.dp, end = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text       = "Herculex",
                    color      = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize   = 16.sp,
                    modifier   = Modifier.padding(bottom = 2.dp),
                )
            }
        }

        // Sync button above Workouts
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF2C2C2E), shape = CircleShape)
                    .clickable { SyncService.requestSyncFromPhone(context) }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Text("🔄", fontSize = 14.sp)
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "Sync with Phone",
                        color      = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize   = 13.sp,
                    )
                }
            }
        }

        // Workouts card
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1976D2), shape = CircleShape)
                    .clickable { navController.navigate("workout_list") }
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Text("💪", fontSize = 18.sp)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Workouts",
                        color      = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize   = 15.sp,
                    )
                }
            }
        }

        // Nutrition card
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1C1C1E), shape = CircleShape)
                    .clickable { navController.navigate("nutrition") }
                    .padding(horizontal = 16.dp, vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        "Nutrition",
                        color      = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize   = 14.sp,
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        HomeMacroChip("${data.calories}", "kcal",    Color(0xFF42A5F5))
                        HomeMacroChip("${data.protein}g", "protein", Color(0xFFFFA726))
                        HomeMacroChip("${data.water}ml",  "water",   Color(0xFF80DEEA))
                    }
                }
            }
        }

        // Active workout card (placed under Nutrition when a workout is running)
        if (session != null) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF4CAF50), shape = CircleShape)
                        .clickable { navController.navigate("active_workout") }
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        Text("⏱️", fontSize = 16.sp)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "Continue phone workout",
                            color      = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize   = 12.sp,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeMacroChip(value: String, label: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Text(label, color = Color(0xFF757575), fontSize = 9.sp)
    }
}
