package com.ams.herculex.nutrition

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Picker
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.rememberPickerState
import com.ams.herculex.sync.QuickAddFoodItem
import com.ams.herculex.sync.SyncService
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachPickerRotary
import com.ams.herculex.workout.attachRotaryScroll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/// Tap-to-log list of the user's Suggested foods, Recent foods, and My Recipes,
/// synced from the phone's diary and recipe catalogue.
@Composable
fun LogFoodScreen(navController: NavController, viewModel: NutritionViewModel) {
    val suggestedItems by viewModel.quickAddItems.collectAsState()
    val recentItems by viewModel.recentQuickAddItems.collectAsState()
    val recipeItems by viewModel.recipeQuickAddItems.collectAsState()
    val loggedEntries by viewModel.loggedEntries.collectAsState()
    val listState = rememberScalingLazyListState()
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        viewModel.refreshQuickAdd()
        SyncService.requestSyncFromPhone(context)
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 40.dp, bottom = 52.dp, start = 14.dp, end = 14.dp),
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
            OneUiPill(
                title = "Rambler Voice AI",
                subtitle = "Speak to log meal",
                iconVector = HxIcons.Mic,
                style = OneUiPillStyle.VioletIndigo,
                onClick = { navController.navigate("rambler_voice") },
            )
        }
        if (loggedEntries.isNotEmpty()) {
            item {
                OneUiPill(
                    title = "Today's meals (${loggedEntries.size})",
                    subtitle = "View & edit logged foods",
                    iconVector = HxIcons.Utensils,
                    style = OneUiPillStyle.RoyalBlue,
                    onClick = { navController.navigate("today_meals") },
                )
            }
        }

        // ── Suggested Section ────────────────────────────────────────
        item {
            FoodSectionHeader(
                icon = HxIcons.Star,
                iconTint = Color(0xFF64D2FF),
                title = "Suggested",
                count = suggestedItems.size,
            )
        }
        if (suggestedItems.isEmpty()) {
            item {
                EmptySectionHint("Log foods on your phone to see suggestions here.")
            }
        } else {
            items(suggestedItems) { food ->
                QuickAddFoodRow(
                    food = food,
                    onClick = {
                        viewModel.selectQuickAddItem(food)
                        navController.navigate("log_food_amount")
                    },
                    onQuickAdd = {
                        viewModel.logQuickAdd(food, viewModel.defaultMealKeyFor(food))
                    },
                )
            }
        }

        // ── Recent Section ───────────────────────────────────────────
        item {
            FoodSectionHeader(
                icon = HxIcons.Clock,
                iconTint = Color(0xFFA0AABF),
                title = "Recent",
                count = recentItems.size,
            )
        }
        if (recentItems.isEmpty()) {
            item {
                EmptySectionHint("Recently logged foods will appear here.")
            }
        } else {
            items(recentItems) { food ->
                QuickAddFoodRow(
                    food = food,
                    onClick = {
                        viewModel.selectQuickAddItem(food)
                        navController.navigate("log_food_amount")
                    },
                    onQuickAdd = {
                        viewModel.logQuickAdd(food, viewModel.defaultMealKeyFor(food))
                    },
                )
            }
        }

        // ── My Recipes Section ───────────────────────────────────────
        item {
            FoodSectionHeader(
                icon = HxIcons.Utensils,
                iconTint = Color(0xFFFFB74D),
                title = "My Recipes",
                count = recipeItems.size,
            )
        }
        if (recipeItems.isEmpty()) {
            item {
                EmptySectionHint("Create recipes on your phone to log them in one tap.")
            }
        } else {
            items(recipeItems) { recipe ->
                QuickAddFoodRow(
                    food = recipe,
                    leadingIcon = HxIcons.Utensils,
                    onClick = {
                        viewModel.selectQuickAddItem(recipe)
                        navController.navigate("log_food_amount")
                    },
                    onQuickAdd = {
                        viewModel.logQuickAdd(recipe, viewModel.defaultMealKeyFor(recipe))
                    },
                )
            }
        }
    }
}

@Composable
private fun FoodSectionHeader(
    icon: ImageVector,
    iconTint: Color,
    title: String,
    count: Int,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp, bottom = 2.dp, start = 6.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = title,
                color = Color(0xFFE2E6F0),
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
            )
        }
        if (count > 0) {
            Text(
                text = "$count",
                color = Color(0xFF7D869C),
                fontWeight = FontWeight.SemiBold,
                fontSize = 11.sp,
            )
        }
    }
}

@Composable
private fun EmptySectionHint(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF141821), shape = RoundedCornerShape(16.dp))
            .border(1.dp, Color(0xFF232A3B), RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = Color(0xFF8C95AA),
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun QuickAddFoodRow(
    food: QuickAddFoodItem,
    customStyle: FoodNutritionStyle? = null,
    leadingIcon: ImageVector? = null,
    onClick: () -> Unit,
    onQuickAdd: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()

    var isAdded by remember { mutableStateOf(false) }
    val pillScale = remember { Animatable(1f) }
    val glowAlpha = remember { Animatable(0f) }
    val buttonScale = remember { Animatable(1f) }

    val nutritionStyle = remember(food, customStyle) {
        customStyle ?: FoodNutritionStyle.resolve(food)
    }

    val badgeColor by animateColorAsState(
        targetValue = if (isAdded) Color(0xFF00C853) else nutritionStyle.plusBadgeColor,
        animationSpec = tween(durationMillis = 260),
        label = "badgeColor",
    )

    fun handleQuickAdd() {
        if (isAdded) return
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        onQuickAdd()

        coroutineScope.launch {
            isAdded = true
            launch {
                glowAlpha.snapTo(1f)
                glowAlpha.animateTo(
                    0f,
                    animationSpec = tween(durationMillis = 900, easing = FastOutSlowInEasing),
                )
            }
            launch {
                pillScale.animateTo(0.95f, animationSpec = tween(durationMillis = 70))
                pillScale.animateTo(
                    1.03f,
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioMediumBouncy,
                        stiffness = Spring.StiffnessMedium,
                    ),
                )
                pillScale.animateTo(1f, animationSpec = tween(durationMillis = 140))
            }
            launch {
                buttonScale.animateTo(0.7f, animationSpec = tween(durationMillis = 70))
                buttonScale.animateTo(
                    1.28f,
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioHighBouncy,
                        stiffness = Spring.StiffnessMedium,
                    ),
                )
                buttonScale.animateTo(1f, animationSpec = tween(durationMillis = 140))
            }
            delay(1100)
            isAdded = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = pillScale.value
                scaleY = pillScale.value
            },
        contentAlignment = Alignment.Center,
    ) {
        // Animated glowing ring/border pulse around the pill
        if (glowAlpha.value > 0.01f) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .border(
                        width = 2.5.dp,
                        brush = Brush.horizontalGradient(
                            listOf(
                                Color(0xFF00E676).copy(alpha = glowAlpha.value),
                                Color(0xFF40C4FF).copy(alpha = glowAlpha.value),
                                Color(0xFF69F0AE).copy(alpha = glowAlpha.value),
                            ),
                        ),
                        shape = CircleShape,
                    ),
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (isAdded) {
                        Modifier.background(Color(0xFF1B4D3E), shape = CircleShape)
                    } else {
                        Modifier.background(nutritionStyle.backgroundBrush, shape = CircleShape)
                    }
                )
                .then(
                    if (!isAdded && nutritionStyle.borderColor != Color.Transparent) {
                        Modifier.border(1.dp, nutritionStyle.borderColor, CircleShape)
                    } else Modifier
                )
                .clickable(onClick = onClick)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (leadingIcon != null) {
                Icon(
                    imageVector = leadingIcon,
                    contentDescription = null,
                    tint = nutritionStyle.secondaryColor,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(8.dp))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = food.name,
                    color = nutritionStyle.contentColor,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = if (isAdded) "✓ Added" else "${food.portionLabel} · ${food.kcal} kcal",
                    color = if (isAdded) Color(0xFFA5D6A7) else nutritionStyle.secondaryColor,
                    fontSize = 10.sp,
                    fontWeight = if (isAdded) FontWeight.SemiBold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(Modifier.size(8.dp))
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .graphicsLayer {
                        scaleX = buttonScale.value
                        scaleY = buttonScale.value
                    }
                    .background(badgeColor, shape = CircleShape)
                    .clickable { handleQuickAdd() },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (isAdded) "✓" else "+",
                    color = Color.White,
                    fontSize = if (isAdded) 14.sp else 16.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
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
    val formattedAmount = if (scaledAmount % 1.0 == 0.0) {
        "%.0f".format(scaledAmount)
    } else {
        "%.2f".format(scaledAmount).trimEnd('0').trimEnd('.')
    }
    val unitLabel = if (item.portionUnit == "serving" && scaledAmount != 1.0) "servings" else item.portionUnit
    val focusRequester = remember { FocusRequester() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .padding(top = 28.dp, bottom = 12.dp, start = 14.dp, end = 14.dp)
            .attachPickerRotary(
                pickerState = pickerState,
                maxOptions = amountMultiplierOptions.size,
                focusRequester = focusRequester,
                isFocused = true,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = item.name,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
        )
        Text(
            text = "$formattedAmount $unitLabel · $scaledKcal kcal",
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
        OneUiPill(
            title = "Next",
            style = OneUiPillStyle.EmeraldGreen,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp),
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
