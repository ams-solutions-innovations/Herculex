package com.ams.herculex.nutrition

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text

@Composable
fun SummaryScreen(viewModel: NutritionViewModel) {
    val data  by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Header
            Text(
                text = "Today",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
            )
            Text(
                text = "Summary",
                color = Color(0xFF9E9E9E),
                fontSize = 11.sp,
            )
            Spacer(Modifier.height(6.dp))

            // Top row: carbs · fat · protein
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MacroRing(
                    label    = "carbs",
                    value    = data.carbs,
                    goal     = goals.carbsGoal,
                    ringColor = Color(0xFF26C6DA),
                    size     = 58.dp,
                )
                MacroRing(
                    label    = "fat",
                    value    = data.fats,
                    goal     = goals.fatGoal,
                    ringColor = Color(0xFFBA68C8),
                    size     = 58.dp,
                )
                MacroRing(
                    label    = "protein",
                    value    = data.protein,
                    goal     = goals.proteinGoal,
                    ringColor = Color(0xFFFFA726),
                    size     = 58.dp,
                )
            }

            Spacer(Modifier.height(6.dp))

            // Bottom row: cal · water
            Row(
                modifier = Modifier.fillMaxWidth(0.72f),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MacroRing(
                    label    = "cal",
                    value    = data.calories,
                    goal     = goals.calorieGoal,
                    ringColor = Color(0xFF42A5F5),
                    size     = 66.dp,
                )
                MacroRing(
                    label    = "water",
                    value    = data.water,
                    goal     = goals.waterGoal,
                    ringColor = Color(0xFF80DEEA),
                    size     = 66.dp,
                )
            }
        }
    }
}

@Composable
private fun MacroRing(
    label: String,
    value: Int,
    goal: Int,
    ringColor: Color,
    size: Dp = 58.dp,
) {
    val progress = if (goal > 0) (value.toFloat() / goal.toFloat()).coerceIn(0f, 1f) else 0f
    val valueFontSize = if (size >= 66.dp) 16.sp else 13.sp
    val labelFontSize = if (size >= 66.dp) 9.sp  else 8.sp

    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokeW = 5.dp.toPx()
            val half    = strokeW / 2f
            val arcSize = Size(this.size.width - strokeW, this.size.height - strokeW)
            val topLeft = Offset(half, half)

            // Background ring
            drawArc(
                color       = Color(0xFF3A3A3A),
                startAngle  = -90f,
                sweepAngle  = 360f,
                useCenter   = false,
                topLeft     = topLeft,
                size        = arcSize,
                style       = Stroke(width = strokeW, cap = StrokeCap.Round),
            )
            // Progress arc
            if (progress > 0f) {
                drawArc(
                    color       = ringColor,
                    startAngle  = -90f,
                    sweepAngle  = 360f * progress,
                    useCenter   = false,
                    topLeft     = topLeft,
                    size        = arcSize,
                    style       = Stroke(width = strokeW, cap = StrokeCap.Round),
                )
            }
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text       = "$value",
                color      = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize   = valueFontSize,
                lineHeight = valueFontSize,
            )
            Text(
                text     = label,
                color    = Color(0xFF9E9E9E),
                fontSize = labelFontSize,
            )
        }
    }
}
