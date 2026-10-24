package com.ams.herculex.nutrition

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
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
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
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
import com.ams.herculex.sync.QuickAddMealSlot
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll
import kotlin.math.roundToInt

@Composable
fun EditLoggedFoodScreen(
    navController: NavController,
    viewModel: NutritionViewModel,
    entryId: Int,
) {
    val loggedEntries by viewModel.loggedEntries.collectAsState()
    val mealSlots by viewModel.quickAddMealSlots.collectAsState()
    val selectedEntry by viewModel.selectedLoggedEntry.collectAsState()

    val entry = remember(selectedEntry, loggedEntries, entryId) {
        selectedEntry?.takeIf { it.id == entryId }
            ?: loggedEntries.firstOrNull { it.id == entryId }
    }

    if (entry == null) {
        LaunchedEffect(Unit) {
            navController.popBackStack()
        }
        return
    }

    val haptic = LocalHapticFeedback.current
    val listState = rememberScalingLazyListState()
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    var selectedMealKey by remember(entry) { mutableStateOf(entry.mealKey) }
    var currentAmount by remember(entry) {
        mutableDoubleStateOf(if (entry.portionAmount > 0) entry.portionAmount else 100.0)
    }
    var isDeleteConfirming by remember { mutableStateOf(false) }

    val resolvedSlots = remember(mealSlots) {
        if (mealSlots.isNotEmpty()) mealSlots else listOf(
            QuickAddMealSlot("breakfast", "Breakfast"),
            QuickAddMealSlot("lunch", "Lunch"),
            QuickAddMealSlot("dinner", "Dinner"),
            QuickAddMealSlot("snack", "Snacks"),
        )
    }

    val isGramOrMl = entry.portionUnit.equals("g", ignoreCase = true) ||
            entry.portionUnit.equals("ml", ignoreCase = true)
    val step = if (isGramOrMl) 10.0 else 0.25

    val multiplier = if (entry.portionAmount > 0) currentAmount / entry.portionAmount else 1.0
    val computedKcal = (entry.kcal * multiplier).roundToInt().coerceAtLeast(0)
    val computedProtein = (entry.protein * multiplier).roundToInt().coerceAtLeast(0)
    val computedCarbs = (entry.carbs * multiplier).roundToInt().coerceAtLeast(0)
    val computedFat = (entry.fat * multiplier).roundToInt().coerceAtLeast(0)

    val formattedAmount = if (currentAmount % 1.0 == 0.0) {
        "%.0f".format(currentAmount)
    } else {
        "%.1f".format(currentAmount)
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focusRequester)
            .focusable()
            .onRotaryScrollEvent { event ->
                if (event.verticalScrollPixels > 0) {
                    currentAmount = (currentAmount + (if (isGramOrMl) 5.0 else 0.25)).coerceAtMost(3000.0)
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                } else if (event.verticalScrollPixels < 0) {
                    currentAmount = (currentAmount - (if (isGramOrMl) 5.0 else 0.25)).coerceAtLeast(if (isGramOrMl) 5.0 else 0.25)
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                }
                true
            }
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 34.dp, bottom = 48.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Header: Food Name & Live Macro Summary ────────────────────────
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Edit Food",
                    color = Color(0xFF9098AA),
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                )
                Text(
                    text = entry.name,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "$formattedAmount ${entry.portionUnit} · $computedKcal kcal",
                    color = Color(0xFF64D2FF),
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                )
                Text(
                    text = "${computedProtein}P · ${computedCarbs}C · ${computedFat}F",
                    color = Color(0xFF8C95AA),
                    fontSize = 10.sp,
                )
            }
        }

        // ── Portion Amount Stepper ────────────────────────────────────────
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF141824), shape = RoundedCornerShape(18.dp))
                    .border(1.dp, Color(0xFF262E40), RoundedCornerShape(18.dp))
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    // Minus Button
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .background(Color(0xFF22293A), shape = CircleShape)
                            .clickable {
                                currentAmount = (currentAmount - step).coerceAtLeast(step)
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = HxIcons.Minus,
                            contentDescription = "Decrease",
                            tint = Color.White,
                            modifier = Modifier.size(16.dp),
                        )
                    }

                    // Value & Unit Display
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = formattedAmount,
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 18.sp,
                        )
                        Text(
                            text = entry.portionUnit,
                            color = Color(0xFF8C95AA),
                            fontSize = 10.sp,
                        )
                    }

                    // Plus Button
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .background(Color(0xFF22293A), shape = CircleShape)
                            .clickable {
                                currentAmount = (currentAmount + step).coerceAtMost(3000.0)
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = HxIcons.Plus,
                            contentDescription = "Increase",
                            tint = Color.White,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }

        // ── Meal Slot Selection ───────────────────────────────────────────
        item {
            Text(
                text = "Meal",
                color = Color(0xFF8C95AA),
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 6.dp, top = 2.dp),
            )
        }

        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                for (slot in resolvedSlots) {
                    val isSelected = selectedMealKey.equals(slot.key, ignoreCase = true)
                    val bg = if (isSelected) Color(0xFF1B4D3E) else Color(0xFF141824)
                    val border = if (isSelected) Color(0xFF00E676) else Color(0xFF242C3D)
                    val textCol = if (isSelected) Color(0xFFA5D6A7) else Color(0xFFD6DBE8)

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(bg, shape = CircleShape)
                            .border(1.dp, border, CircleShape)
                            .clickable {
                                selectedMealKey = slot.key
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            }
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            text = slot.label,
                            color = textCol,
                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                            fontSize = 12.sp,
                        )
                        if (isSelected) {
                            Icon(
                                imageVector = HxIcons.Check,
                                contentDescription = "Selected",
                                tint = Color(0xFF00E676),
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                }
            }
        }

        // ── Action: Save Changes ──────────────────────────────────────────
        item {
            Spacer(Modifier.height(4.dp))
            OneUiPill(
                title = "Save Changes",
                iconVector = HxIcons.Check,
                style = OneUiPillStyle.EmeraldGreen,
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    viewModel.updateLoggedEntry(
                        entry = entry,
                        newMealKey = selectedMealKey,
                        newAmount = currentAmount,
                        newUnit = entry.portionUnit,
                        newPortionText = "$formattedAmount ${entry.portionUnit}",
                        newKcal = computedKcal,
                        newProtein = computedProtein,
                        newCarbs = computedCarbs,
                        newFat = computedFat,
                        newServings = multiplier * entry.servings,
                    )
                    navController.popBackStack()
                },
            )
        }

        // ── Action: Delete Item ───────────────────────────────────────────
        item {
            if (isDeleteConfirming) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF381014), shape = CircleShape)
                        .border(1.5.dp, Color(0xFFFF453A), CircleShape)
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            viewModel.deleteLoggedEntry(entry)
                            navController.popBackStack()
                        }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = HxIcons.Trash,
                            contentDescription = "Delete",
                            tint = Color(0xFFFF5252),
                            modifier = Modifier.size(16.dp),
                        )
                        Column {
                            Text(
                                text = "Delete Entry?",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 12.sp,
                            )
                            Text(
                                text = "Tap to confirm",
                                color = Color(0xFFFF8A80),
                                fontSize = 10.sp,
                            )
                        }
                    }
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .background(Color(0xFF2A1517), shape = CircleShape)
                            .clickable { isDeleteConfirming = false },
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
                OneUiPill(
                    title = "Delete Entry",
                    iconVector = HxIcons.Trash,
                    style = OneUiPillStyle.DangerTransparent,
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        isDeleteConfirming = true
                    },
                )
            }
        }
    }
}
