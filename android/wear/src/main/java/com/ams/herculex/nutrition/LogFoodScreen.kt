package com.ams.herculex.nutrition

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Text

@Composable
fun LogFoodScreen(navController: NavController, viewModel: NutritionViewModel) {
    var calories by remember { mutableStateOf(0) }
    var protein  by remember { mutableStateOf(0) }
    var carbs    by remember { mutableStateOf(0) }
    var fats     by remember { mutableStateOf(0) }

    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
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
                    text = "Log Food",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }
        item {
            MacroAdjuster(
                label = "Calories",
                value = calories,
                color = Color(0xFF42A5F5),
                steps = listOf(-100, -10, +10, +100),
                onValueChange = { calories = (calories + it).coerceAtLeast(0) },
            )
        }
        item {
            MacroAdjuster(
                label = "Protein",
                value = protein,
                color = Color(0xFFFFA726),
                steps = listOf(-10, -1, +1, +10),
                onValueChange = { protein = (protein + it).coerceAtLeast(0) },
            )
        }
        item {
            MacroAdjuster(
                label = "Carbs",
                value = carbs,
                color = Color(0xFF26C6DA),
                steps = listOf(-10, -1, +1, +10),
                onValueChange = { carbs = (carbs + it).coerceAtLeast(0) },
            )
        }
        item {
            MacroAdjuster(
                label = "Fat",
                value = fats,
                color = Color(0xFFBA68C8),
                steps = listOf(-10, -1, +1, +10),
                onValueChange = { fats = (fats + it).coerceAtLeast(0) },
            )
        }
        item {
            // Confirm button
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1976D2), shape = CircleShape)
                    .clickable {
                        viewModel.logFood(calories, protein, carbs, fats)
                        navController.popBackStack()
                    }
                    .padding(vertical = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("Log Food", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
        }
    }
}

@Composable
fun MacroAdjuster(
    label: String,
    value: Int,
    color: Color,
    steps: List<Int>,
    onValueChange: (Int) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1C1C1E), shape = CircleShape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, color = Color(0xFF9E9E9E), fontSize = 11.sp)
            Text("$value", color = color, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }
        Spacer(Modifier.height(6.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            steps.forEach { step ->
                val sign = if (step > 0) "+" else ""
                StepButton(label = "$sign$step", onClick = { onValueChange(step) })
            }
        }
    }
}

@Composable
private fun StepButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .background(Color(0xFF2C2C2E), shape = CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}
