package com.ams.herculex.nutrition

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.AutoCenteringParams
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll
import kotlinx.coroutines.delay

private val RingTrack = Color(0xFF2C1E4A)
private val RingProgress = Color(0xFF64D2FF)
private val RingScheduled = Color(0xFF0B6E4F)

/** `H:MM` — the 46sp readout has no room for "14h 32m". */
private fun formatHm(totalSeconds: Long): String =
    "%d:%02d".format(totalSeconds / 3600L, (totalSeconds % 3600L) / 60L)

@Composable
fun FastingScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    val fasting = data.fastingSnapshot
    var nowEpochMs by remember { mutableLongStateOf(System.currentTimeMillis()) }

    // Ticks while idle too: the countdown to the next scheduled fast has to move.
    LaunchedEffect(fasting.hasActiveFast, fasting.startedAtEpochMs) {
        while (true) {
            nowEpochMs = System.currentTimeMillis()
            delay(1_000)
        }
    }

    val nextFastMs = fasting.nextFastEpochMs
    val nextFormatted = fasting.nextFastFormatted(nowEpochMs)
    val progress = fasting.progress(nowEpochMs)
    val progressPercent = (progress * 100).toInt()
    val elapsedSec = fasting.elapsedSeconds(nowEpochMs)
    val remainingSec = (fasting.targetSeconds - elapsedSec).coerceAtLeast(0L)

    val readout = when {
        fasting.hasActiveFast -> formatHm(elapsedSec)
        nextFastMs != null -> formatHm(((nextFastMs - nowEpochMs) / 1000L).coerceAtLeast(0L))
        else -> "0:00"
    }
    val readoutCaption = when {
        fasting.hasActiveFast -> "elapsed · $progressPercent%"
        nextFastMs != null -> "until next fast"
        else -> "idle"
    }

    val listState = rememberScalingLazyListState()

    // Smoothly dim the bezel progress ring when the user scrolls down to read details
    val isMainView = listState.centerItemIndex == 0
    val ringAlpha by animateFloatAsState(
        targetValue = if (isMainView) 1f else 0.2f,
        animationSpec = tween(durationMillis = 200),
        label = "fastingRingAlpha",
    )

    Scaffold(
        positionIndicator = {
            PositionIndicator(scalingLazyListState = listState)
        }
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center,
        ) {
            // Progress ring around the whole bezel, clockwise from 12 o'clock.
            Canvas(
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer(alpha = ringAlpha)
            ) {
                val strokePx = 8.dp.toPx()
                val inset = 8.5.dp.toPx()
                val topLeft = Offset(inset, inset)
                val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
                drawArc(
                    color = RingTrack,
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = strokePx),
                )
                val sweepFraction = when {
                    fasting.hasActiveFast -> progress
                    nextFastMs != null -> 0.05f
                    else -> 0f
                }
                if (sweepFraction > 0f) {
                    drawArc(
                        color = if (fasting.hasActiveFast) RingProgress else RingScheduled,
                        startAngle = -90f,
                        sweepAngle = 360f * sweepFraction,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = strokePx, cap = StrokeCap.Round),
                    )
                }
            }

            // Scrollable column with rotary dial/crown support:
            // Item 0 is the clean, unclipped main dial centered on screen.
            // Items below are revealed when the user scrolls down.
            ScalingLazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .attachRotaryScroll(listState),
                autoCentering = AutoCenteringParams(itemIndex = 0),
                contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 20.dp, bottom = 44.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // ── Item 0: Main Timer Face ─────────────────────────────
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 16.dp, bottom = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "FASTING TIMER",
                            color = Color.Gray,
                            fontSize = 11.sp,
                            lineHeight = 13.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(modifier = Modifier.height(5.dp))
                        Text(
                            text = readout,
                            color = Color(0xFFD1C4E9), // Light purple
                            fontSize = 46.sp,
                            lineHeight = 54.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = readoutCaption,
                            color = Color(0xFFD3D3D3),
                            fontSize = 12.sp,
                            lineHeight = 14.sp,
                            maxLines = 1,
                        )
                        Spacer(modifier = Modifier.height(14.dp))

                        Button(
                            onClick = {
                                if (fasting.hasActiveFast) {
                                    nutritionViewModel.stopFast()
                                } else {
                                    nutritionViewModel.startFast()
                                }
                            },
                            colors = ButtonDefaults.buttonColors(
                                backgroundColor = if (fasting.hasActiveFast) Color(0xFF7A2434) else Color(0xFF0B6E4F)
                            ),
                            modifier = Modifier
                                .width(110.dp)
                                .height(40.dp),
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = if (fasting.hasActiveFast) HxIcons.Stop else HxIcons.Play,
                                    contentDescription = null,
                                    tint = Color.White,
                                    modifier = Modifier.size(14.dp),
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    if (fasting.hasActiveFast) "Stop Fast" else "Start Fast",
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        }

                        // Subtle scroll-down cue
                        Spacer(modifier = Modifier.height(10.dp))
                        Icon(
                            imageVector = HxIcons.Chevron,
                            contentDescription = "Scroll down for details",
                            tint = Color(0x60FFFFFF),
                            modifier = Modifier
                                .size(13.dp)
                                .graphicsLayer(rotationZ = 90f),
                        )
                    }
                }

                // ── Scroll Down: Stage & Fast Details (in English) ────────
                if (fasting.hasActiveFast) {
                    val stageInfo = FastingStages.resolve(fasting.currentStageMessage, elapsedSec)
                    item {
                        OneUiPill(
                            title = "${stageInfo.hour}h · ${stageInfo.title}",
                            subtitle = stageInfo.description,
                            iconVector = HxIcons.Flame,
                            style = OneUiPillStyle.VioletIndigo,
                        )
                    }

                    item {
                        val isCompleted = remainingSec == 0L
                        val leftH = remainingSec / 3600L
                        val leftM = (remainingSec % 3600L) / 60L
                        OneUiPill(
                            title = if (isCompleted) "Goal reached!" else "Time remaining",
                            subtitle = if (isCompleted) {
                                "Target achieved! You can end or extend your fast."
                            } else {
                                "${leftH}h ${leftM}m left until ${fasting.targetSeconds / 3600L}h goal"
                            },
                            statValue = "$progressPercent%",
                            statLabel = "Elapsed",
                            iconVector = if (isCompleted) HxIcons.Trophy else HxIcons.Timer,
                            style = if (isCompleted) OneUiPillStyle.EmeraldGreen else OneUiPillStyle.SlateNavy,
                        )
                    }
                } else {
                    if (nextFormatted != null) {
                        item {
                            OneUiPill(
                                title = "Next Fast",
                                subtitle = "$nextFormatted • ${fasting.nextFastPlanName ?: "16:8"}",
                                iconVector = HxIcons.Clock,
                                style = OneUiPillStyle.VioletIndigo,
                            )
                        }
                    }

                    val lastFastSeconds = fasting.lastFastDurationSeconds
                    if (lastFastSeconds != null) {
                        val lastH = lastFastSeconds / 3600L
                        val lastM = (lastFastSeconds % 3600L) / 60L
                        item {
                            OneUiPill(
                                title = "Previous Fast",
                                subtitle = "${lastH}h ${lastM}m completed",
                                iconVector = HxIcons.Timer,
                                style = OneUiPillStyle.SlateNavy,
                            )
                        }
                    }

                    item {
                        OneUiPill(
                            title = "Target Fast",
                            subtitle = "${fasting.targetSeconds / 3600L} hours goal",
                            iconVector = HxIcons.Fasting,
                            style = OneUiPillStyle.DarkSlateButton,
                        )
                    }
                }
            }
        }
    }
}
