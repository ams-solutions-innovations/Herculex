package com.ams.herculex.nutrition

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.ams.herculex.sync.LoggedFoodEntry
import com.ams.herculex.sync.QuickAddMealSlot
import com.ams.herculex.sync.SyncService
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll
import kotlinx.coroutines.delay

@Composable
fun TodayMealsScreen(
    navController: NavController,
    viewModel: NutritionViewModel,
) {
    val loggedEntries by viewModel.loggedEntries.collectAsState()
    val mealSlots by viewModel.quickAddMealSlots.collectAsState()
    val nutritionData by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()

    val listState = rememberScalingLazyListState()
    val context = LocalContext.current
    var deletePendingEntryId by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(Unit) {
        viewModel.refreshQuickAdd()
        SyncService.requestSyncFromPhone(context)
    }

    val resolvedSlots = remember(mealSlots) {
        if (mealSlots.isNotEmpty()) mealSlots else listOf(
            QuickAddMealSlot("breakfast", "Breakfast"),
            QuickAddMealSlot("lunch", "Lunch"),
            QuickAddMealSlot("dinner", "Dinner"),
            QuickAddMealSlot("snack", "Snacks"),
        )
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 36.dp, bottom = 48.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Title & Daily Summary ─────────────────────────────────────────
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Today's Meals",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
                Text(
                    text = "${nutritionData.calories} / ${goals.calorieGoal} kcal",
                    color = OneUiPillStyle.RoyalBlue.secondaryColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "${nutritionData.protein}P · ${nutritionData.carbs}C · ${nutritionData.fats}F",
                    color = Color(0xFF8C95AA),
                    fontSize = 10.sp,
                    modifier = Modifier.padding(top = 1.dp, bottom = 4.dp),
                )
            }
        }

        // ── Empty State ───────────────────────────────────────────────────
        if (loggedEntries.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF141821), shape = RoundedCornerShape(16.dp))
                        .border(1.dp, Color(0xFF232A3B), RoundedCornerShape(16.dp))
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = HxIcons.Utensils,
                            contentDescription = null,
                            tint = Color(0xFF7D869C),
                            modifier = Modifier.size(20.dp),
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = "No meals logged yet today",
                            color = Color(0xFF8C95AA),
                            fontSize = 11.sp,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
            item {
                OneUiPill(
                    title = "Log Food",
                    iconVector = HxIcons.Plus,
                    style = OneUiPillStyle.EmeraldGreen,
                    onClick = { navController.navigate("log_food") },
                )
            }
        } else {
            // ── Meals Breakdown ───────────────────────────────────────────
            for (slot in resolvedSlots) {
                val entriesInMeal = loggedEntries.filter {
                    it.mealKey.equals(slot.key, ignoreCase = true)
                }
                val mealKcal = entriesInMeal.sumOf { it.kcal }

                item(key = "header_${slot.key}") {
                    MealHeader(
                        slot = slot,
                        itemCount = entriesInMeal.size,
                        totalKcal = mealKcal,
                    )
                }

                if (entriesInMeal.isEmpty()) {
                    item(key = "empty_${slot.key}") {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color(0xFF10131A), shape = CircleShape)
                                .border(1.dp, Color(0xFF1D222F), CircleShape)
                                .clickable {
                                    navController.navigate("log_food")
                                }
                                .padding(horizontal = 12.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            Text(
                                text = "+ Add ${slot.label.lowercase()}",
                                color = Color(0xFF6B758D),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Medium,
                            )
                        }
                    }
                } else {
                    for (entry in entriesInMeal) {
                        item(key = "entry_${entry.id}") {
                            LoggedFoodPill(
                                entry = entry,
                                isDeletePending = deletePendingEntryId == entry.id,
                                onClick = {
                                    if (deletePendingEntryId == entry.id) {
                                        deletePendingEntryId = null
                                        viewModel.deleteLoggedEntry(entry)
                                    } else {
                                        deletePendingEntryId = null
                                        viewModel.selectLoggedEntry(entry)
                                        navController.navigate("edit_logged_food/${entry.id}")
                                    }
                                },
                                onLongClick = {
                                    deletePendingEntryId = if (deletePendingEntryId == entry.id) null else entry.id
                                },
                                onCancelDelete = {
                                    deletePendingEntryId = null
                                },
                            )
                        }
                    }
                }
            }

            // Also check for any entries whose mealKey doesn't match standard slots
            val extraEntries = loggedEntries.filter { entry ->
                resolvedSlots.none { it.key.equals(entry.mealKey, ignoreCase = true) }
            }
            if (extraEntries.isNotEmpty()) {
                item(key = "header_extra") {
                    MealHeader(
                        slot = QuickAddMealSlot("other", "Other"),
                        itemCount = extraEntries.size,
                        totalKcal = extraEntries.sumOf { it.kcal },
                    )
                }
                for (entry in extraEntries) {
                    item(key = "entry_${entry.id}") {
                        LoggedFoodPill(
                            entry = entry,
                            isDeletePending = deletePendingEntryId == entry.id,
                            onClick = {
                                if (deletePendingEntryId == entry.id) {
                                    deletePendingEntryId = null
                                    viewModel.deleteLoggedEntry(entry)
                                } else {
                                    deletePendingEntryId = null
                                    viewModel.selectLoggedEntry(entry)
                                    navController.navigate("edit_logged_food/${entry.id}")
                                }
                            },
                            onLongClick = {
                                deletePendingEntryId = if (deletePendingEntryId == entry.id) null else entry.id
                            },
                            onCancelDelete = {
                                deletePendingEntryId = null
                            },
                        )
                    }
                }
            }

            // Quick add pill at bottom
            item(key = "footer_log") {
                OneUiPill(
                    title = "Add more food",
                    iconVector = HxIcons.Plus,
                    style = OneUiPillStyle.SlateNavy,
                    onClick = { navController.navigate("log_food") },
                )
            }
        }
    }
}

@Composable
private fun MealHeader(
    slot: QuickAddMealSlot,
    itemCount: Int,
    totalKcal: Int,
) {
    val icon = when (slot.key.lowercase()) {
        "breakfast" -> HxIcons.Utensils
        "lunch"     -> HxIcons.Utensils
        "dinner"    -> HxIcons.Utensils
        else        -> HxIcons.Apple
    }
    val iconTint = when (slot.key.lowercase()) {
        "breakfast" -> Color(0xFFFFB74D) // Warm Amber / Sunrise
        "lunch"     -> Color(0xFF64D2FF) // Bright Cyan / Sun
        "dinner"    -> Color(0xFFB388FF) // Purple / Evening
        else        -> Color(0xFF81C784) // Green / Snack Apple
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 2.dp, start = 6.dp, end = 6.dp),
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
                modifier = Modifier.size(13.dp),
            )
            Text(
                text = slot.label,
                color = Color(0xFFE2E6F0),
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
            )
        }
        if (totalKcal > 0) {
            Text(
                text = "$totalKcal kcal",
                color = Color(0xFF9098AA),
                fontWeight = FontWeight.SemiBold,
                fontSize = 11.sp,
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LoggedFoodPill(
    entry: LoggedFoodEntry,
    isDeletePending: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onCancelDelete: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val nutritionStyle = remember(entry) { FoodNutritionStyle.resolve(entry) }

    LaunchedEffect(isDeletePending) {
        if (isDeletePending) {
            delay(5000)
            onCancelDelete()
        }
    }

    val animatedBorderColor by animateColorAsState(
        targetValue = if (isDeletePending) Color(0xFFFF453A) else nutritionStyle.borderColor.takeIf { it != Color.Transparent } ?: Color(0xFF323B52),
        animationSpec = tween(durationMillis = 240),
        label = "pillBorderColor",
    )

    val pulseTransition = rememberInfiniteTransition(label = "deletePulse")
    val pulseScale by pulseTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(450, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseScale",
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (isDeletePending) {
                    Modifier.background(Color(0xFF381014), shape = CircleShape)
                } else {
                    Modifier.background(nutritionStyle.backgroundBrush, shape = CircleShape)
                }
            )
            .border(
                width = if (isDeletePending) 1.5.dp else 1.dp,
                color = animatedBorderColor,
                shape = CircleShape,
            )
            .combinedClickable(
                onClick = {
                    if (isDeletePending) {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    }
                    onClick()
                },
                onLongClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onLongClick()
                },
            )
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        if (isDeletePending) {
            // ── Inline Delete Confirmation State ───────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(26.dp)
                            .graphicsLayer {
                                scaleX = pulseScale
                                scaleY = pulseScale
                            }
                            .background(Color(0xFF5A141A), shape = CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = HxIcons.Trash,
                            contentDescription = "Delete",
                            tint = Color(0xFFFF5252),
                            modifier = Modifier.size(14.dp),
                        )
                    }
                    Column {
                        Text(
                            text = "Are you sure?",
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp,
                        )
                        Text(
                            text = "Tap to delete",
                            color = Color(0xFFFF8A80),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .background(Color(0xFF2A1517), shape = CircleShape)
                        .clickable { onCancelDelete() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = HxIcons.Close,
                        contentDescription = "Cancel",
                        tint = Color(0xFFFFB4AB),
                        modifier = Modifier.size(12.dp),
                    )
                }
            }
        } else {
            // ── Normal State (Click to Edit, Long-press to Delete) ──────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = entry.name,
                        color = nutritionStyle.contentColor,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(1.dp))
                    Text(
                        text = "${entry.portionText} · ${entry.kcal} kcal",
                        color = nutritionStyle.secondaryColor,
                        fontSize = 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (entry.protein > 0 || entry.carbs > 0 || entry.fat > 0) {
                        Text(
                            text = "${entry.protein}P · ${entry.carbs}C · ${entry.fat}F",
                            color = nutritionStyle.secondaryColor.copy(alpha = 0.85f),
                            fontSize = 9.sp,
                        )
                    }
                }
                Spacer(Modifier.width(6.dp))
                Icon(
                    imageVector = HxIcons.Chevron,
                    contentDescription = "Edit",
                    tint = nutritionStyle.secondaryColor,
                    modifier = Modifier.size(14.dp),
                )
            }
        }
    }
}
