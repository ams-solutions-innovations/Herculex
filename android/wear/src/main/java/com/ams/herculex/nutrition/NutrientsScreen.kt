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
import androidx.compose.foundation.layout.size
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
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll

private data class NutrientRow(
    val label: String,
    val unit: String,
    val icon: String,
    val color: Color,
    val style: OneUiPillStyle,
    val value: (NutritionData) -> Int,
    val goal: (NutritionGoals) -> Int,
)

private val nutrientRows = listOf(
    NutrientRow("Calories", "kcal", "⚡", Color(0xFF42A5F5), OneUiPillStyle.RoyalBlue,    { it.calories }, { it.calorieGoal }),
    NutrientRow("Protein",  "g",    "🥩", Color(0xFFFFA726), OneUiPillStyle.Terracotta,   { it.protein  }, { it.proteinGoal }),
    NutrientRow("Carbs",    "g",    "🌾", Color(0xFF26C6DA), OneUiPillStyle.SlateNavy,    { it.carbs    }, { it.carbsGoal  }),
    NutrientRow("Fat",      "g",    "🥑", Color(0xFFBA68C8), OneUiPillStyle.VioletIndigo, { it.fats     }, { it.fatGoal    }),
    NutrientRow("Water",    "ml",   "💧", Color(0xFF80DEEA), OneUiPillStyle.AccentBlue,   { it.water    }, { it.waterGoal  }),
)

@Composable
fun NutrientsScreen(viewModel: NutritionViewModel) {
    val data  by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()
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
                icon  = row.icon,
                value = row.value(data),
                goal  = row.goal(goals),
                unit  = row.unit,
                color = row.color,
                style = row.style,
            )
        }
    }
}

@Composable
private fun NutrientItem(
    label: String,
    icon: String,
    value: Int,
    goal: Int,
    unit: String,
    color: Color,
    style: OneUiPillStyle,
) {
    val progress = if (goal > 0) (value.toFloat() / goal.toFloat()).coerceIn(0f, 1f) else 0f

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(style.containerColor, shape = CircleShape)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Circular Icon Badge
        Box(
            modifier = Modifier
                .size(38.dp)
                .background(style.badgeColor, shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(icon, fontSize = 16.sp)
        }
        Spacer(Modifier.width(10.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, color = style.contentColor, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("$value", color = color, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text("/ $goal $unit", color = style.secondaryColor, fontSize = 10.sp)
                }
            }
            Spacer(Modifier.height(4.dp))
            // One UI Progress Bar
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .background(Color(0x33FFFFFF), shape = CircleShape),
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
