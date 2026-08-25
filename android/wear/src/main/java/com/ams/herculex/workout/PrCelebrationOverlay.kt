package com.ams.herculex.workout

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay

/**
 * Full-screen Apple Watch Fitness Award style celebratory notification for PRs.
 * Displays for 3 seconds with animated gold trophy, vibrant badge metrics, and wrist haptics.
 */
@Composable
fun PrCelebrationOverlay(
    event: WatchPrEvent,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var isVisible by remember { mutableStateOf(false) }
    val trophyScale = remember { Animatable(0.2f) }

    // Haptic feedback pulse + 3-second auto dismiss timer
    LaunchedEffect(event.id) {
        isVisible = true
        // Trigger celebratory haptic pattern on watch
        runCatching {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (vibrator != null && vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(
                        longArrayOf(0, 60, 50, 110),
                        intArrayOf(0, 200, 0, 255),
                        -1
                    )
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(longArrayOf(0, 60, 50, 110), -1)
                }
            }
        }

        // Bouncing entrance animation for the trophy
        trophyScale.animateTo(
            targetValue = 1.0f,
            animationSpec = spring(
                dampingRatio = Spring.DampingRatioMediumBouncy,
                stiffness = Spring.StiffnessLow
            )
        )

        // Display for the specified duration (default 3000ms)
        delay(event.durationMs)
        isVisible = false
        delay(250)
        onDismiss()
    }

    AnimatedVisibility(
        visible = isVisible,
        enter = fadeIn(tween(200)),
        exit = fadeOut(tween(200)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = {
                        isVisible = false
                        onDismiss()
                    }
                ),
            contentAlignment = Alignment.Center,
        ) {
            // Apple Watch subtle ambient radial gold glow
            Box(
                modifier = Modifier
                    .size(160.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.radialGradient(
                            colors = listOf(
                                Color(0x55FFD60A),
                                Color(0x22FF9500),
                                Color.Transparent,
                            )
                        )
                    )
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                // Apple Fitness style Trophy Medallion
                Box(
                    modifier = Modifier
                        .scale(trophyScale.value)
                        .size(54.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.linearGradient(
                                colors = listOf(
                                    Color(0xFFFFE600),
                                    Color(0xFFFF9500),
                                    Color(0xFFFF5E00),
                                )
                            )
                        )
                        .border(1.5.dp, Color(0xFFFFF7C2), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "🏆",
                        fontSize = 28.sp,
                        textAlign = TextAlign.Center,
                    )
                }

                Spacer(Modifier.height(6.dp))

                // Apple Watch glowing uppercase category badge
                Text(
                    text = event.headline.ifBlank { "NEW PR" },
                    color = Color(0xFFFFD60A), // Apple Fitness bright gold
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 0.8.sp,
                    textAlign = TextAlign.Center,
                )

                Spacer(Modifier.height(2.dp))

                // Exercise Title (Bold San Francisco style)
                Text(
                    text = event.exerciseName,
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )

                Spacer(Modifier.height(4.dp))

                // Metric Capsule (Apple Watch dark glass card with glowing text)
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFF1C1C1E))
                        .border(1.dp, Color(0xFF38383A), RoundedCornerShape(12.dp))
                        .padding(horizontal = 10.dp, vertical = 3.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = event.valueText,
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        if (!event.diffText.isNullOrBlank()) {
                            Spacer(Modifier.size(5.dp))
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(Color(0xFF30D158).copy(alpha = 0.25f))
                                    .padding(horizontal = 4.dp, vertical = 1.dp)
                            ) {
                                Text(
                                    text = event.diffText,
                                    color = Color(0xFF30D158), // Apple Fitness Mint Green
                                    fontSize = 10.5.sp,
                                    fontWeight = FontWeight.ExtraBold,
                                )
                            }
                        }
                    }
                }

                if (!event.subDetail.isNullOrBlank()) {
                    Spacer(Modifier.height(3.dp))
                    Text(
                        text = event.subDetail,
                        color = Color(0xFF98989D),
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}
