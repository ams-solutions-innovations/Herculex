package com.ams.herculex.workout

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay

/**
 * Glanceable "IT'S GO TIME" banner shown over whatever screen is open when
 * the rest between sets runs out, or out of wake when the lifter glances at
 * their wrist within the wake grace period. Auto-hides after 4.5 seconds, or on tap.
 *
 * [trigger] is [RestTimerStore.goTimeEvents]; each new value shows it once.
 */
@Composable
fun GoTimeOverlay(
    trigger: Int,
    subtitle: String? = null,
) {
    val context = LocalContext.current
    val storeLabel by RestTimerStore.lastGoTimeLabel.collectAsState()
    val displaySubtitle = subtitle ?: storeLabel

    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        visible = true
        delay(4_500)
        visible = false
    }
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn() + scaleIn(initialScale = 0.85f),
        exit = fadeOut(),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.90f))
                .clickable {
                    visible = false
                    RestTimerStore.dismissGoTime(context)
                },
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "IT'S GO TIME",
                    color = Color(0xFF30D158),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Black,
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = if (displaySubtitle.isNotBlank()) displaySubtitle else "Rest is over",
                    color = Color.White.copy(alpha = 0.75f),
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}
