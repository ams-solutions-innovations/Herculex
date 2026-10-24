package com.ams.herculex.nutrition

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Premium Wear OS quick-entry screen for Water and Calories.
 * Features:
 * - Fluid circular bezel progress ring displaying current + projected goal intake
 * - Atmospheric domain radial glow
 * - Tactile stepper controls (- / +) for granular adjustment
 * - Generously spaced quick-add preset chips with tap-to-add & long-press-to-subtract
 * - Interactive number pop animation and spring physics on every button
 * - Hardware rotary bezel / crown support with haptic feedback
 * - Usable bottom actions: Cancel / Clear and prominent Save / Add pill
 */
@Composable
fun QuickNutritionEntryScreen(
    navController: NavController,
    title: String,
    icon: ImageVector,
    unit: String,
    currentTotal: Int,
    dailyGoal: Int,
    stepSize: Int,
    presets: List<Int>,
    accentColor: Color,
    accentGlow: Color,
    trackColor: Color,
    chipBgColor: Color,
    chipBorderColor: Color,
    chipTextColor: Color,
    onConfirm: (Int) -> Unit,
) {
    var amount by remember { mutableIntStateOf(0) }
    var isSaving by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    // Number bounce animation when amount changes
    val amountBounce = remember { Animatable(1f) }
    var prevAmount by remember { mutableIntStateOf(0) }
    LaunchedEffect(amount) {
        if (amount != prevAmount && amount > 0) {
            amountBounce.animateTo(1.15f, tween(70, easing = FastOutSlowInEasing))
            amountBounce.animateTo(
                1f,
                spring(stiffness = Spring.StiffnessLow, dampingRatio = Spring.DampingRatioMediumBouncy),
            )
        }
        prevAmount = amount
    }

    // Confirm button save pop animation
    val confirmScale by animateFloatAsState(
        targetValue = if (isSaving) 1.12f else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium, dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "confirmScale",
    )

    // Rotary Bezel / Crown support
    val focusRequester = remember { FocusRequester() }
    var lastHandledUptimeMillis by remember { mutableLongStateOf(-1L) }
    var accumulatedRotary by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(Unit) {
        repeat(8) {
            delay(100)
            try { focusRequester.requestFocus() } catch (_: Exception) {}
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .nutritionDomainGlow(accentGlow)
            .focusRequester(focusRequester)
            .focusable()
            .onRotaryScrollEvent { event ->
                if (event.uptimeMillis == lastHandledUptimeMillis) return@onRotaryScrollEvent true
                lastHandledUptimeMillis = event.uptimeMillis

                val delta = if (event.verticalScrollPixels != 0f) event.verticalScrollPixels else event.horizontalScrollPixels
                accumulatedRotary += delta
                val threshold = 18f
                if (accumulatedRotary >= threshold) {
                    amount += stepSize
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    accumulatedRotary = 0f
                } else if (accumulatedRotary <= -threshold) {
                    if (amount > 0) {
                        amount = (amount - stepSize).coerceAtLeast(0)
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    }
                    accumulatedRotary = 0f
                }
                true
            },
        contentAlignment = Alignment.Center,
    ) {
        // Perimeter Bezel Progress Ring
        NutritionBezelRing(
            current = currentTotal,
            added = amount,
            goal = dailyGoal,
            baseColor = accentColor.copy(alpha = 0.45f),
            accentColor = accentGlow,
            trackColor = trackColor,
        )

        // Main Content Column
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // ── Top Header ──────────────────────────────────────────────
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = accentGlow,
                    modifier = Modifier.size(13.dp),
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = title,
                    color = Color(0xFF9E9E9E),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
            Spacer(Modifier.height(1.dp))
            Text(
                text = "$currentTotal / $dailyGoal $unit",
                color = chipTextColor,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
            )

            Spacer(Modifier.height(4.dp))

            // ── Center Stepper & Large Animated Amount ──────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Minus Stepper Button
                StepperCircleButton(
                    icon = HxIcons.Minus,
                    enabled = amount > 0,
                    onClick = {
                        amount = (amount - stepSize).coerceAtLeast(0)
                    },
                )

                Spacer(Modifier.width(10.dp))

                // Center Amount Value
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.graphicsLayer(
                        scaleX = amountBounce.value,
                        scaleY = amountBounce.value,
                    ),
                ) {
                    Text(
                        text = "+$amount",
                        color = if (amount > 0) Color.White else Color(0xFFCCCCCC),
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = (-1).sp,
                    )
                    Text(
                        text = unit,
                        color = Color(0xFF8B93A5),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                    )
                }

                Spacer(Modifier.width(10.dp))

                // Plus Stepper Button
                StepperCircleButton(
                    icon = HxIcons.Plus,
                    enabled = true,
                    onClick = {
                        amount += stepSize
                    },
                )
            }

            // Projected Total Indicator
            Box(
                modifier = Modifier
                    .height(14.dp)
                    .padding(top = 1.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (amount > 0) {
                    Text(
                        text = "→ ${currentTotal + amount} $unit",
                        color = accentGlow,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            Spacer(Modifier.height(6.dp))

            // ── Quick-Add Preset Chips (Tap to add, Long-press to subtract) ─
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                presets.forEach { step ->
                    QuickAddPresetChip(
                        label = "+$step",
                        bgColor = chipBgColor,
                        borderColor = chipBorderColor,
                        textColor = chipTextColor,
                        onAdd = { amount += step },
                        onSubtract = { amount = (amount - step).coerceAtLeast(0) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Spacer(Modifier.height(8.dp))

            // ── Bottom Action Row: Cancel / Clear + Save / Add ──────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Cancel / Clear Button
                ActionCircleButton(
                    icon = HxIcons.Close,
                    tint = if (amount > 0) Color(0xFFFF6B6B) else Color(0xFF9E9E9E),
                    bgColor = if (amount > 0) Color(0xFF2E2224) else Color(0xFF1E2430),
                    borderColor = if (amount > 0) Color(0xFF4A3438) else Color(0xFF2C3446),
                    onClick = {
                        if (amount > 0) {
                            amount = 0
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        } else {
                            navController.popBackStack()
                        }
                    },
                )

                Spacer(Modifier.width(12.dp))

                // Confirm / Add Pill Button
                ConfirmPillButton(
                    enabled = amount > 0,
                    accentColor = accentColor,
                    scale = confirmScale,
                    onClick = {
                        if (amount > 0 && !isSaving) {
                            coroutineScope.launch {
                                isSaving = true
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                onConfirm(amount)
                                delay(160)
                                navController.popBackStack()
                            }
                        }
                    },
                )
            }
        }
    }
}

/**
 * Circular Bezel Progress Ring drawn along the watch perimeter.
 * Shows base intake today + animated projected addition towards daily goal.
 */
@Composable
private fun NutritionBezelRing(
    current: Int,
    added: Int,
    goal: Int,
    baseColor: Color,
    accentColor: Color,
    trackColor: Color,
    modifier: Modifier = Modifier,
) {
    val safeGoal = goal.coerceAtLeast(1)
    val currentSweep = (current.toFloat() / safeGoal).coerceIn(0f, 1f) * 360f

    val animatedAdded by animateFloatAsState(
        targetValue = added.toFloat(),
        animationSpec = spring(stiffness = Spring.StiffnessLow, dampingRatio = Spring.DampingRatioLowBouncy),
        label = "addedSweepAnim",
    )
    val projectedSweep = ((current + animatedAdded) / safeGoal).coerceIn(0f, 1.25f) * 360f

    val pulseAlpha by rememberInfiniteTransition(label = "pulseRing").animateFloat(
        initialValue = 0.7f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(750, easing = LinearEasing), RepeatMode.Reverse),
        label = "pulseAlpha",
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val strokeWidth = 4.dp.toPx()
        val inset = 5.dp.toPx() + strokeWidth / 2f
        val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
        val topLeft = Offset(inset, inset)

        // 1. Subtle background track
        drawArc(
            color = trackColor,
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(strokeWidth, cap = StrokeCap.Round),
        )

        // 2. Current intake arc
        if (currentSweep > 0f) {
            drawArc(
                color = baseColor,
                startAngle = -90f,
                sweepAngle = currentSweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(strokeWidth, cap = StrokeCap.Round),
            )
        }

        // 3. Projected addition arc
        val addedSweep = (projectedSweep - currentSweep).coerceAtLeast(0f)
        if (addedSweep > 0.5f) {
            drawArc(
                color = accentColor.copy(alpha = pulseAlpha),
                startAngle = -90f + currentSweep,
                sweepAngle = addedSweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(strokeWidth, cap = StrokeCap.Round),
            )
        }
    }
}

/**
 * Atmospheric domain radial glow from top and bottom.
 */
private fun Modifier.nutritionDomainGlow(accentGlow: Color): Modifier = drawBehind {
    drawRect(
        Brush.radialGradient(
            colors = listOf(accentGlow.copy(alpha = 0.28f), Color.Transparent),
            center = Offset(size.width / 2f, size.height * 1.08f),
            radius = size.width * 0.75f,
        ),
    )
    drawRect(
        Brush.radialGradient(
            colors = listOf(accentGlow.copy(alpha = 0.16f), Color.Transparent),
            center = Offset(size.width / 2f, -size.height * 0.12f),
            radius = size.width * 0.65f,
        ),
    )
}

/**
 * Tactile Stepper Circle Button (- / +) with spring scale press animation.
 */
@Composable
private fun StepperCircleButton(
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptic = LocalHapticFeedback.current
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed && enabled) 0.88f else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium, dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "stepperScale",
    )

    Box(
        modifier = modifier
            .size(34.dp)
            .graphicsLayer(scaleX = scale, scaleY = scale)
            .background(
                if (enabled) Color(0xFF222836) else Color(0xFF161A24),
                shape = CircleShape,
            )
            .border(
                1.dp,
                if (enabled) Color(0xFF333D52) else Color(0xFF202636),
                shape = CircleShape,
            )
            .then(
                if (enabled) {
                    Modifier.clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onClick()
                        },
                    )
                } else Modifier,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (enabled) Color.White else Color(0xFF5A6275),
            modifier = Modifier.size(16.dp),
        )
    }
}

/**
 * Ergonomic Quick-Add Preset Chip.
 * Single tap: adds preset amount.
 * Long press: subtracts preset amount.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun QuickAddPresetChip(
    label: String,
    bgColor: Color,
    borderColor: Color,
    textColor: Color,
    onAdd: () -> Unit,
    onSubtract: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptic = LocalHapticFeedback.current
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.88f else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium, dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "chipScale",
    )

    Box(
        modifier = modifier
            .graphicsLayer(scaleX = scale, scaleY = scale)
            .background(bgColor, shape = CircleShape)
            .border(1.dp, borderColor, shape = CircleShape)
            .combinedClickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onAdd()
                },
                onLongClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onSubtract()
                },
            )
            .padding(vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = textColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}

/**
 * Bottom action circular button (Close / Cancel / Clear).
 */
@Composable
private fun ActionCircleButton(
    icon: ImageVector,
    tint: Color,
    bgColor: Color,
    borderColor: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.88f else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium, dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "actionBtnScale",
    )

    Box(
        modifier = modifier
            .size(38.dp)
            .graphicsLayer(scaleX = scale, scaleY = scale)
            .background(bgColor, shape = CircleShape)
            .border(1.dp, borderColor, shape = CircleShape)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(18.dp),
        )
    }
}

/**
 * Bottom Confirm / Add pill button with checkmark icon and text.
 */
@Composable
private fun ConfirmPillButton(
    enabled: Boolean,
    accentColor: Color,
    scale: Float,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (isPressed && enabled) 0.90f else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium, dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "confirmPressScale",
    )

    Row(
        modifier = modifier
            .height(38.dp)
            .width(76.dp)
            .graphicsLayer(scaleX = scale * pressScale, scaleY = scale * pressScale)
            .background(
                if (enabled) accentColor else Color(0xFF1E2430),
                shape = CircleShape,
            )
            .border(
                1.dp,
                if (enabled) accentColor.copy(alpha = 0.8f) else Color(0xFF2C3446),
                shape = CircleShape,
            )
            .then(
                if (enabled) {
                    Modifier.clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = onClick,
                    )
                } else Modifier,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = HxIcons.Check,
            contentDescription = null,
            tint = if (enabled) Color.White else Color(0xFF5A6275),
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(4.dp))
        Text(
            text = "Add",
            color = if (enabled) Color.White else Color(0xFF5A6275),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}
