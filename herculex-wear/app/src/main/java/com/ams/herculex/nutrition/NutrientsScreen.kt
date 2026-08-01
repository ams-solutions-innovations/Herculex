package com.ams.herculex.nutrition

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
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Text

private data class NutrientRow(
    val label: String,
    val unit: String,
    val color: Color,
    val value: (NutritionData) -> Int,
    val goal: (NutritionGoals) -> Int,
)

private val nutrientRows = listOf(
    NutrientRow("Calories", "kcal", Color(0xFF42A5F5), { it.calories }, { it.calorieGoal }),
    NutrientRow("Protein",  "g",    Color(0xFFFFA726), { it.protein  }, { it.proteinGoal }),
    NutrientRow("Carbs",    "g",    Color(0xFF26C6DA), { it.carbs    }, { it.carbsGoal  }),
    NutrientRow("Fat",      "g",    Color(0xFFBA68C8), { it.fats     }, { it.fatGoal    }),
    NutrientRow("Water",    "ml",   Color(0xFF80DEEA), { it.water    }, { it.waterGoal  }),
)

@Composable
fun NutrientsScreen(viewModel: NutritionViewModel) {
    val data  by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()

    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        autoCentering = null,
        contentPadding = PaddingValues(top = 10.dp, bottom = 20.dp, start = 10.dp, end = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "Nutrients",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
        }
        items(nutrientRows) { row ->
            NutrientItem(
                label = row.label,
                value = row.value(data),
                goal  = row.goal(goals),
                unit  = row.unit,
                color = row.color,
            )
        }
    }
}

@Composable
private fun NutrientItem(label: String, value: Int, goal: Int, unit: String, color: Color) {
    val progress = if (goal > 0) (value.toFloat() / goal.toFloat()).coerceIn(0f, 1f) else 0f

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1C1C1E), shape = CircleShape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, color = Color.White, fontWeight = FontWeight.Medium, fontSize = 13.sp)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("$value", color = color, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    Text("/ $goal $unit", color = Color(0xFF757575), fontSize = 10.sp)
                }
            }
            Spacer(Modifier.height(6.dp))
            // Progress bar
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .background(Color(0xFF3A3A3A), shape = CircleShape),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(progress)
                        .height(4.dp)
                        .background(color, shape = CircleShape),
                )
            }
        }
    }
}
