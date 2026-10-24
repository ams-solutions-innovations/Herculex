package com.ams.herculex.nutrition

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.navigation.NavController
import com.ams.herculex.ui.HxIcons

@Composable
fun AddCaloriesScreen(navController: NavController, viewModel: NutritionViewModel) {
    val data by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()

    QuickNutritionEntryScreen(
        navController = navController,
        title = "Add kcal",
        icon = HxIcons.Flame,
        unit = "kcal",
        currentTotal = data.calories,
        dailyGoal = goals.calorieGoal,
        stepSize = 50,
        presets = listOf(50, 100, 200, 500),
        accentColor = Color(0xFFD84315),
        accentGlow = Color(0xFFFF7043),
        trackColor = Color(0xFF2E1A14),
        chipBgColor = Color(0xFF381B14),
        chipBorderColor = Color(0xFF5A3225).copy(alpha = 0.5f),
        chipTextColor = Color(0xFFFFCCBC),
        onConfirm = { amount ->
            viewModel.addCalories(amount)
        },
    )
}
