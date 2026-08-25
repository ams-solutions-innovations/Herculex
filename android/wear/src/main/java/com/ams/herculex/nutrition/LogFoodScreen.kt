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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Picker
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.rememberPickerState
import com.ams.herculex.sync.QuickAddFoodItem
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll
import kotlin.math.roundToInt

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
        item {
            com.ams.herculex.ui.OneUiPill(
                title = "Rambler Voice AI",
                subtitle = "Speak to log meal",
                icon = "🎙️",
                style = OneUiPillStyle.VioletIndigo,
                onClick = { navController.navigate("rambler_voice") },
            )
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
                    // Tap the row itself: adjust the amount before logging.
                    onClick = {
                        viewModel.selectQuickAddItem(food)
                        navController.navigate("log_food_amount")
                    },
                    // Tap "+": one-tap log of exactly the default/last-used
                    // amount, straight to the food's last-used meal — no
                    // extra screens.
                    onQuickAdd = {
                        viewModel.logQuickAdd(food, viewModel.defaultMealKeyFor(food))
                    },
                )
            }
        }
    }
}

@Composable
private fun QuickAddFoodRow(
    food: QuickAddFoodItem,
    onClick: () -> Unit,
    onQuickAdd: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
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
                .background(OneUiPillStyle.RoyalBlue.badgeColor, shape = CircleShape)
                .clickable {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onQuickAdd()
                },
            contentAlignment = Alignment.Center,
        ) {
            Text("+", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
    }
}

private val amountMultiplierOptions =
    listOf(0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)

/// Step between [LogFoodScreen] and [LogFoodMealPickerScreen]: scales the
/// tapped item's default portion up or down before it's logged. Reached only
/// by tapping the food row itself — the "+" badge on that row skips this and
/// logs the default amount directly.
@Composable
fun LogFoodAmountScreen(navController: NavController, viewModel: NutritionViewModel) {
    val pendingItem by viewModel.pendingQuickAddItem.collectAsState()
    val item = pendingItem

    if (item == null) {
        LaunchedEffect(Unit) { navController.popBackStack() }
        return
    }

    val defaultIdx = amountMultiplierOptions.indexOf(1.0).takeIf { it >= 0 } ?: 0
    val pickerState = rememberPickerState(
        initialNumberOfOptions = amountMultiplierOptions.size,
        initiallySelectedOption = defaultIdx,
        repeatItems = false,
    )
    val selectedMultiplier = amountMultiplierOptions[pickerState.selectedOption]
    val scaledKcal = (item.kcal * selectedMultiplier).roundToInt()
    val scaledAmount = item.portionAmount * selectedMultiplier

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .padding(top = 32.dp, bottom = 12.dp, start = 14.dp, end = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = item.name,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
        )
        Text(
            text = "%.0f %s · $scaledKcal kcal".format(scaledAmount, item.portionUnit),
            color = Color(0xFF9E9E9E),
            fontSize = 11.sp,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        Picker(
            state = pickerState,
            contentDescription = "Amount",
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) { index ->
            val isSelected = index == pickerState.selectedOption
            val multiplier = amountMultiplierOptions[index]
            Text(
                text = if (multiplier == 1.0) "1x (default)" else "${"%.2f".format(multiplier).trimEnd('0').trimEnd('.')}x",
                color = if (isSelected) OneUiPillStyle.RoyalBlue.contentColor else Color.White,
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                fontSize = if (isSelected) 19.sp else 13.sp,
            )
        }
        com.ams.herculex.ui.OneUiPill(
            title = "Next",
            style = OneUiPillStyle.EmeraldGreen,
            onClick = {
                viewModel.setPendingQuickAddMultiplier(selectedMultiplier)
                navController.navigate("log_food_meal")
            },
        )
    }
}

/// Second step after tapping a quick-add item: pick which meal it's logged
/// to. The item itself lives in [NutritionViewModel.pendingQuickAddItem]
/// rather than a nav argument — Wear's NavHost only carries string args, and
/// the item already lives in a StateFlow the moment it's tapped.
@Composable
fun LogFoodMealPickerScreen(navController: NavController, viewModel: NutritionViewModel) {
    val pendingItem by viewModel.pendingQuickAddItem.collectAsState()
    val multiplier by viewModel.pendingQuickAddMultiplier.collectAsState()
    val mealSlots by viewModel.quickAddMealSlots.collectAsState()
    val listState = rememberScalingLazyListState()
    val item = pendingItem

    if (item == null) {
        LaunchedEffect(Unit) { navController.popBackStack() }
        return
    }

    val scaledKcal = (item.kcal * multiplier).roundToInt()

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
                    text = if (multiplier == 1.0) {
                        "${item.portionLabel} · ${item.kcal} kcal"
                    } else {
                        "%.2fx portion · $scaledKcal kcal".format(multiplier).replace(".00x", "x")
                    },
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
                        viewModel.logQuickAdd(item, slot.key, multiplier)
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
