package com.ams.herculex.nutrition

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
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll

@Composable
fun NutritionScreen(
    navController: NavController,
    viewModel: NutritionViewModel = viewModel(),
) {
    val listState = rememberScalingLazyListState()
    val loggedEntries by viewModel.loggedEntries.collectAsState()
    val nutritionData by viewModel.data.collectAsState()

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
                    text = "Nutrition",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }
        item {
            OneUiPill(
                title = "Today's meals",
                subtitle = if (loggedEntries.isNotEmpty()) {
                    "${nutritionData.calories} kcal · ${loggedEntries.size} items"
                } else {
                    "View logged foods"
                },
                iconVector = HxIcons.Utensils,
                style = OneUiPillStyle.RoyalBlue,
                onClick = { navController.navigate("today_meals") },
            )
        }
        item {
            OneUiPill(
                title = "Log food",
                iconVector = HxIcons.Plus,
                style = OneUiPillStyle.EmeraldGreen,
                onClick = { navController.navigate("log_food") },
            )
        }
        item {
            OneUiPill(
                title = "Nutrients",
                iconVector = HxIcons.Nutrients,
                style = OneUiPillStyle.VioletIndigo,
                onClick = { navController.navigate("nutrients") },
            )
        }
        item {
            OneUiPill(
                title = "Add kcal",
                iconVector = HxIcons.Flame,
                style = OneUiPillStyle.Terracotta,
                onClick = { navController.navigate("add_calories") },
            )
        }
        item {
            OneUiPill(
                title = "Add water",
                iconVector = HxIcons.Drop,
                style = OneUiPillStyle.AccentBlue,
                onClick = { navController.navigate("add_water") },
            )
        }
    }
}
