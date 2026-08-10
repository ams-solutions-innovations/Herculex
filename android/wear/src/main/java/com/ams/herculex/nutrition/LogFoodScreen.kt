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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.sync.QuickAddFoodItem
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll

/// Tap-to-log list of the user's recent/most-common foods, synced from the
/// phone's diary (see `NutritionRepository.quickAddFoods`). There is no
/// manual entry or search here on purpose — the watch has no catalogue of
/// its own, so it can only offer what the phone last sent down.
@Composable
fun LogFoodScreen(navController: NavController, viewModel: NutritionViewModel) {
    val items by viewModel.quickAddItems.collectAsState()
    val listState = rememberScalingLazyListState()

    LaunchedEffect(Unit) { viewModel.refreshQuickAdd() }

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
                horizontalAlignment = Alignment.CenterHorizontally,
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
        if (items.isEmpty()) {
            item {
                Text(
                    text = "Log a few foods on your phone — they'll show up here for quick add.",
                    color = Color(0xFF9E9E9E),
                    fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 16.dp),
                )
            }
        } else {
            items(items) { food ->
                QuickAddFoodRow(
                    food = food,
                    onClick = {
                        viewModel.selectQuickAddItem(food)
                        navController.navigate("log_food_meal")
                    },
                )
            }
        }
    }
}

@Composable
private fun QuickAddFoodRow(food: QuickAddFoodItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(OneUiPillStyle.RoyalBlue.containerColor, shape = CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = food.name,
                color = OneUiPillStyle.RoyalBlue.contentColor,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
                maxLines = 1,
            )
            Text(
                text = "${food.portionLabel} · ${food.kcal} kcal",
                color = OneUiPillStyle.RoyalBlue.secondaryColor,
                fontSize = 10.sp,
            )
        }
        Spacer(Modifier.size(8.dp))
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(OneUiPillStyle.RoyalBlue.badgeColor, shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("+", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
    }
}

/// Second step after tapping a quick-add item: pick which meal it's logged
/// to. The item itself lives in [NutritionViewModel.pendingQuickAddItem]
/// rather than a nav argument — Wear's NavHost only carries string args, and
/// the item already lives in a StateFlow the moment it's tapped.
@Composable
fun LogFoodMealPickerScreen(navController: NavController, viewModel: NutritionViewModel) {
    val pendingItem by viewModel.pendingQuickAddItem.collectAsState()
    val mealSlots by viewModel.quickAddMealSlots.collectAsState()
    val listState = rememberScalingLazyListState()
    val item = pendingItem

    if (item == null) {
        LaunchedEffect(Unit) { navController.popBackStack() }
        return
    }

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
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = item.name,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                )
                Text(
                    text = "${item.portionLabel} · ${item.kcal} kcal",
                    color = Color(0xFF9E9E9E),
                    fontSize = 11.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }
        items(mealSlots) { slot ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(OneUiPillStyle.EmeraldGreen.containerColor, shape = CircleShape)
                    .clickable {
                        viewModel.logQuickAdd(item, slot.key)
                        navController.popBackStack("nutrition", inclusive = false)
                    }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = slot.label,
                    color = OneUiPillStyle.EmeraldGreen.contentColor,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                )
            }
        }
    }
}
