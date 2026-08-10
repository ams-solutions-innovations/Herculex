package com.ams.herculex.home

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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.nutrition.NutritionViewModel
import com.ams.herculex.sync.SyncService
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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
        contentPadding = PaddingValues(top = 40.dp, bottom = 48.dp, start = 14.dp, end = 14.dp),
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

        // Sync with Phone Pill
        item {
            var isSyncing by remember { mutableStateOf(false) }
            val scope = rememberCoroutineScope()
            val rotation = if (isSyncing) {
                val infiniteTransition = rememberInfiniteTransition(label = "SyncRotation")
                infiniteTransition.animateFloat(
                    initialValue = 0f,
                    targetValue = 360f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(1200, easing = LinearEasing),
                        repeatMode = RepeatMode.Restart
                    ),
                    label = "Rotation"
                ).value
            } else {
                0f
            }

            OneUiPill(
                title = "Sync with Phone",
                iconComposable = {
                    Text(
                        text = "🔄",
                        fontSize = 16.sp,
                        modifier = Modifier.rotate(rotation)
                    )
                },
                style = OneUiPillStyle.SlateNavy,
                onClick = {
                    if (!isSyncing) {
                        scope.launch {
                            isSyncing = true
                            SyncService.requestSyncFromPhone(context)
                            delay(2000)
                            isSyncing = false
                        }
                    }
                },
            )
        }

        // Workouts Pill (Primary One UI Royal Blue)
        item {
            OneUiPill(
                title = "Workouts",
                subtitle = "Start or manage routines",
                icon = "💪",
                style = OneUiPillStyle.RoyalBlue,
                onClick = { navController.navigate("workout_list") },
            )
        }

        // Nutrition Pill Card (One UI Terracotta / Slate Card with Macro Breakdown)
        item {
            OneUiPillCard(onClick = { navController.navigate("nutrition") }) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp)
                    ) {
                        Text(
                            text = "Nutrition",
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp,
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    HomeMacroChip("${data.calories}", "kcal", Color(0xFF42A5F5))
                    Text("|", color = Color(0x40FFFFFF), fontSize = 12.sp)
                    HomeMacroChip("${data.protein}g", "protein", Color(0xFFFFA726))
                    Text("|", color = Color(0x40FFFFFF), fontSize = 12.sp)
                    HomeMacroChip("${data.water}ml", "water", Color(0xFF80DEEA))
                }
            }
        }

        // Fasting Pill
        item {
            OneUiPill(
                title = "Fasting",
                statValue = data.fasting,
                statLabel = "Duration",
                icon = "⏳",
                style = OneUiPillStyle.VioletIndigo,
                onClick = { navController.navigate("fasting") },
            )
        }

        // Weekly Volume Pill
        item {
            val tonnageText = if (data.weeklyTonnage >= 1000f) {
                "%.1ft".format(data.weeklyTonnage / 1000f)
            } else {
                "${data.weeklyTonnage.toInt()}kg"
            }
            OneUiPill(
                title = "Weekly Volume",
                statValue = "$tonnageText | ${data.weeklySets}",
                statLabel = "Sets",
                icon = "🏋️",
                style = OneUiPillStyle.SlateNavy,
                onClick = { navController.navigate("weekly_volume") },
            )
        }

        // Active workout pill (Emerald Green One UI style when workout running)
        if (session != null) {
            val minutes = elapsed / 60
            val seconds = elapsed % 60
            item {
                OneUiPill(
                    title = "Active Workout",
                    statValue = "%d:%02d".format(minutes, seconds),
                    statLabel = session?.template?.name ?: "Workout",
                    icon = "⏱️",
                    style = OneUiPillStyle.EmeraldGreen,
                    onClick = { navController.navigate("active_workout") },
                )
            }
        }
    }
}

@Composable
private fun OneUiPillCard(onClick: () -> Unit, content: @Composable () -> Unit) {
    OneUiPill(
        title = "Nutrition Overview",
        icon = "🥗",
        style = OneUiPillStyle.Terracotta,
        onClick = onClick,
        rightContent = {
            Text("›", color = Color(0xFFFFCCBC), fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
    )
}

@Composable
private fun HomeMacroChip(value: String, label: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Text(label, color = Color(0xFFB0B8C8), fontSize = 9.sp)
    }
}
