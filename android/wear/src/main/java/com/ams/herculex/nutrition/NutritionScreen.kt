package com.ams.herculex.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll

private data class MenuItem(
    val label: String,
    val icon: String,
    val style: OneUiPillStyle,
    val route: String,
)

private val menuItems = listOf(
    MenuItem("Log food",      "+",  OneUiPillStyle.RoyalBlue,    "log_food"),
    MenuItem("Nutrients",     "≡",  OneUiPillStyle.VioletIndigo, "nutrients"),
    MenuItem("Add calories",  "⚡", OneUiPillStyle.Terracotta,   "add_calories"),
    MenuItem("Add water",     "○",  OneUiPillStyle.AccentBlue,   "add_water"),
)

@Composable
fun NutritionScreen(navController: NavController) {
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
                    text = "Nutrition",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }
        items(menuItems) { item ->
            OneUiPill(
                title = item.label,
                icon = item.icon,
                style = item.style,
                onClick = { navController.navigate(item.route) },
            )
        }
    }
}
