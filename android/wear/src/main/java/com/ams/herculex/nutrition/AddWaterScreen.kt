package com.ams.herculex.nutrition

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.navigation.NavController
import com.ams.herculex.ui.HxIcons

@Composable
fun AddWaterScreen(navController: NavController, viewModel: NutritionViewModel) {
    val data by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()

    QuickNutritionEntryScreen(
        navController = navController,
        title = "Add Water",
        icon = HxIcons.Drop,
        unit = "ml",
        currentTotal = data.water,
        dailyGoal = goals.waterGoal,
        stepSize = 50,
        presets = listOf(100, 200, 250, 500),
        accentColor = Color(0xFF1565C0),
        accentGlow = Color(0xFF0288D1),
        trackColor = Color(0xFF0D253F),
        chipBgColor = Color(0xFF0F264A),
        chipBorderColor = Color(0xFF1E44AA).copy(alpha = 0.5f),
        chipTextColor = Color(0xFF80DEEA),
        onConfirm = { amount ->
            viewModel.addWater(amount)
        },
    )
}
