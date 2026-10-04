package com.ams.herculex.media

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import kotlinx.coroutines.delay

val SpotifyGreen = Color(0xFF1DB954)
val SpotifyDark = Color(0xFF121212)
val SpotifyCardBg = Color(0xFF181818)
val SpotifySecondaryText = Color(0xFFB3B3B3)

/**
 * Compact Spotify Live Media Bar designed to fit seamlessly on Wear OS workout screens.
 */
@Composable
fun SpotifyLiveMediaBar(
    modifier: Modifier = Modifier,
    controller: MediaControlsController? = null,
) {
    val context = LocalContext.current
    val mediaController = controller ?: remember(context) { MediaControlsController(context) }
    val state by mediaController.stateFlow.collectAsStateWithLifecycle()
    val haptic = LocalHapticFeedback.current

    var showExpandedDialog by remember { mutableStateOf(false) }

    DisposableEffect(mediaController) {
        mediaController.start()
        onDispose { mediaController.stop() }
    }

    LaunchedEffect(mediaController) {
        while (true) {
            delay(1000)
            mediaController.refresh()
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color(0xFF222222),
                        SpotifyCardBg,
                        SpotifyDark,
                    )
                )
            )
            .border(
                width = 1.dp,
                brush = Brush.horizontalGradient(
                    listOf(
                        SpotifyGreen.copy(alpha = 0.45f),
                        Color(0x221DB954),
                        Color(0x10FFFFFF),
                    )
                ),
                shape = RoundedCornerShape(18.dp)
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    showExpandedDialog = true
                }
            )
            .padding(top = 7.dp, bottom = 6.dp, start = 10.dp, end = 10.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // ── Top Row: Spotify Equalizer + Track / Artist info ──────
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f),
                ) {
                    LiveEqualizerVisualizer(
                        isPlaying = state.isPlaying,
                        modifier = Modifier.padding(end = 6.dp)
                    )

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (state.title.isNotBlank()) state.title else "Spotify",
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.5.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = if (state.artist.isNotBlank()) state.artist else "Herculex Music",
                            color = if (state.isPlaying) SpotifyGreen else SpotifySecondaryText,
                            fontWeight = FontWeight.Medium,
                            fontSize = 9.5.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                // Volume indicator icon pill
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF282828))
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            showExpandedDialog = true
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "🔊",
                        fontSize = 11.sp,
                    )
                }
            }

            Spacer(Modifier.height(5.dp))

            // ── Middle: Live Progress Line ─────────────────────────────
            val currentProgress = state.progress
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(2.5.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(Color(0xFF333333)),
            ) {
                if (currentProgress > 0f) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(currentProgress)
                            .height(2.5.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(SpotifyGreen),
                    )
                }
            }

            Spacer(Modifier.height(5.dp))

            // ── Bottom: Transport Controls (Prev, Play/Pause, Next) ────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Previous button
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            mediaController.previous()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    SpotifySkipPreviousIcon(modifier = Modifier.size(17.dp))
                }

                // Play / Pause central button (Spotify green circle)
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(
                            if (state.isPlaying) SpotifyGreen else Color.White
                        )
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            mediaController.playPause()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    if (state.isPlaying) {
                        SpotifyPauseIcon(modifier = Modifier.size(15.dp), color = Color.Black)
                    } else {
                        SpotifyPlayIcon(modifier = Modifier.size(15.dp), color = Color.Black)
                    }
                }

                // Next button
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            mediaController.next()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    SpotifySkipNextIcon(modifier = Modifier.size(17.dp))
                }
            }
        }
    }

    if (showExpandedDialog) {
        SpotifyExpandedPlayerDialog(
            controller = mediaController,
            state = state,
            onDismiss = { showExpandedDialog = false },
        )
    }
}

/**
 * Animated 3-bar green equalizer visualizer that bounces when playing.
 */
@Composable
fun LiveEqualizerVisualizer(
    isPlaying: Boolean,
    modifier: Modifier = Modifier,
    color: Color = SpotifyGreen,
) {
    val transition = rememberInfiniteTransition(label = "EqualizerTransition")

    val bar1Height by if (isPlaying) {
        transition.animateFloat(
            initialValue = 4f,
            targetValue = 13f,
            animationSpec = infiniteRepeatable(
                animation = tween(420, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "Bar1"
        )
    } else {
        remember { mutableFloatStateOf(4f) }
    }

    val bar2Height by if (isPlaying) {
        transition.animateFloat(
            initialValue = 13f,
            targetValue = 5f,
            animationSpec = infiniteRepeatable(
                animation = tween(320, easing = LinearEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "Bar2"
        )
    } else {
        remember { mutableFloatStateOf(6f) }
    }

    val bar3Height by if (isPlaying) {
        transition.animateFloat(
            initialValue = 5f,
            targetValue = 14f,
            animationSpec = infiniteRepeatable(
                animation = tween(480, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "Bar3"
        )
    } else {
        remember { mutableFloatStateOf(3f) }
    }

    Row(
        modifier = modifier
            .height(14.dp)
            .width(13.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(
            modifier = Modifier
                .width(2.5.dp)
                .height(bar1Height.dp)
                .clip(RoundedCornerShape(1.dp))
                .background(color)
        )
        Box(
            modifier = Modifier
                .width(2.5.dp)
                .height(bar2Height.dp)
                .clip(RoundedCornerShape(1.dp))
                .background(color)
        )
        Box(
            modifier = Modifier
                .width(2.5.dp)
                .height(bar3Height.dp)
                .clip(RoundedCornerShape(1.dp))
                .background(color)
        )
    }
}

/**
 * Full expanded dialog with rotary volume crown control, album art, and rich timeline.
 */
@Composable
fun SpotifyExpandedPlayerDialog(
    controller: MediaControlsController,
    state: MediaControlsState,
    onDismiss: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    var liveVolume by remember(state.volume) { mutableStateOf(state.volume) }
    val maxVol = remember(state.maxVolume) { if (state.maxVolume > 0) state.maxVolume else 15 }

    Dialog(
        showDialog = true,
        onDismissRequest = onDismiss,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .mediaVolumeRotary { step ->
                    val next = (liveVolume + step).coerceIn(0, maxVol)
                    liveVolume = next
                    controller.setVolume(next)
                }
                .padding(horizontal = 14.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                // Top: Source indicator + Close button
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LiveEqualizerVisualizer(isPlaying = state.isPlaying)
                        Spacer(Modifier.width(5.dp))
                        Text(
                            text = if (state.isSpotify) "Spotify Live" else state.appName,
                            color = SpotifyGreen,
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.sp,
                        )
                    }

                    Box(
                        modifier = Modifier
                            .size(24.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF282828))
                            .clickable { onDismiss() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("✕", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }

                // Middle: Track title, artist & Volume slider
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = state.title,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = state.artist,
                        color = SpotifySecondaryText,
                        fontWeight = FontWeight.Medium,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )

                    Spacer(Modifier.height(8.dp))

                    // Volume Bar + Percentage
                    val volPercent = ((liveVolume.toFloat() / maxVol.toFloat()) * 100).toInt()
                    Row(
                        modifier = Modifier.fillMaxWidth(0.85f),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            text = "−",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.clickable {
                                val next = (liveVolume - 1).coerceAtLeast(0)
                                liveVolume = next
                                controller.setVolume(next)
                            }
                        )

                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(6.dp)
                                .padding(horizontal = 8.dp)
                                .clip(RoundedCornerShape(3.dp))
                                .background(Color(0xFF333333)),
                        ) {
                            val pct = (liveVolume.toFloat() / maxVol.toFloat()).coerceIn(0f, 1f)
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth(pct)
                                    .height(6.dp)
                                    .clip(RoundedCornerShape(3.dp))
                                    .background(
                                        Brush.horizontalGradient(
                                            listOf(SpotifyGreen, Color(0xFF1ED760))
                                        )
                                    ),
                            )
                        }

                        Text(
                            text = "+",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.clickable {
                                val next = (liveVolume + 1).coerceAtMost(maxVol)
                                liveVolume = next
                                controller.setVolume(next)
                            }
                        )
                    }

                    Text(
                        text = "Volume: $volPercent%",
                        color = Color(0xFF888888),
                        fontSize = 9.sp,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }

                // Controls Row: Prev | Play/Pause | Next
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(42.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF222222))
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                controller.previous()
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        SpotifySkipPreviousIcon(modifier = Modifier.size(24.dp))
                    }

                    Spacer(Modifier.width(14.dp))

                    Box(
                        modifier = Modifier
                            .size(54.dp)
                            .clip(CircleShape)
                            .background(
                                if (state.isPlaying) SpotifyGreen else Color.White
                            )
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                controller.playPause()
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (state.isPlaying) {
                            SpotifyPauseIcon(modifier = Modifier.size(22.dp), color = Color.Black)
                        } else {
                            SpotifyPlayIcon(modifier = Modifier.size(22.dp), color = Color.Black)
                        }
                    }

                    Spacer(Modifier.width(14.dp))

                    Box(
                        modifier = Modifier
                            .size(42.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF222222))
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                controller.next()
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        SpotifySkipNextIcon(modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Canvas Vector Icons for crisp Wear OS rendering
// ─────────────────────────────────────────────────────────────────────────────

@Composable
fun SpotifySkipPreviousIcon(modifier: Modifier = Modifier, color: Color = Color.White) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val barWidth = w * 0.14f
        val barCorner = barWidth * 0.35f
        val barHeight = h * 0.68f
        val barTop = (h - barHeight) / 2f

        drawRoundRect(
            color = color,
            topLeft = Offset(w * 0.08f, barTop),
            size = Size(barWidth, barHeight),
            cornerRadius = CornerRadius(barCorner, barCorner),
        )

        val triPath = Path().apply {
            moveTo(w * 0.90f, h * 0.16f)
            lineTo(w * 0.28f, h * 0.50f)
            lineTo(w * 0.90f, h * 0.84f)
            close()
        }
        drawPath(path = triPath, color = color)
    }
}

@Composable
fun SpotifySkipNextIcon(modifier: Modifier = Modifier, color: Color = Color.White) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val barWidth = w * 0.14f
        val barCorner = barWidth * 0.35f
        val barHeight = h * 0.68f
        val barTop = (h - barHeight) / 2f

        val triPath = Path().apply {
            moveTo(w * 0.10f, h * 0.16f)
            lineTo(w * 0.72f, h * 0.50f)
            lineTo(w * 0.10f, h * 0.84f)
            close()
        }
        drawPath(path = triPath, color = color)

        drawRoundRect(
            color = color,
            topLeft = Offset(w * 0.78f, barTop),
            size = Size(barWidth, barHeight),
            cornerRadius = CornerRadius(barCorner, barCorner),
        )
    }
}

@Composable
fun SpotifyPlayIcon(modifier: Modifier = Modifier, color: Color = Color.Black) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val path = Path().apply {
            moveTo(w * 0.24f, h * 0.14f)
            lineTo(w * 0.86f, h * 0.50f)
            lineTo(w * 0.24f, h * 0.86f)
            close()
        }
        drawPath(path = path, color = color)
    }
}

@Composable
fun SpotifyPauseIcon(modifier: Modifier = Modifier, color: Color = Color.Black) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val barWidth = w * 0.24f
        val barCorner = barWidth * 0.3f
        val barHeight = h * 0.78f
        val top = (h - barHeight) / 2f

        drawRoundRect(
            color = color,
            topLeft = Offset(w * 0.18f, top),
            size = Size(barWidth, barHeight),
            cornerRadius = CornerRadius(barCorner, barCorner),
        )

        drawRoundRect(
            color = color,
            topLeft = Offset(w * 0.58f, top),
            size = Size(barWidth, barHeight),
            cornerRadius = CornerRadius(barCorner, barCorner),
        )
    }
}
