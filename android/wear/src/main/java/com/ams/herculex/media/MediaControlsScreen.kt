package com.ams.herculex.media

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay

@Composable
fun MediaControlsScreen() {
    val context = LocalContext.current
    val controller = remember(context) { MediaControlsController(context) }
    val state by controller.stateFlow.collectAsStateWithLifecycle()

    DisposableEffect(controller) {
        controller.start()
        onDispose { controller.stop() }
    }
    // Notification access can be granted from Settings while this screen is open, and there is
    // no platform callback for that — poll it slowly as a safety net (see refresh() docs).
    LaunchedEffect(controller) {
        while (true) {
            delay(2_000)
            controller.refresh()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Media", color = Color(0xFF9E9E9E), fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        Text(
            state.title,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            state.artist,
            color = Color(0xFF9E9E9E),
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            MediaButton("<<", 40) { controller.previous() }
            Spacer(Modifier.size(10.dp))
            MediaButton(if (state.isPlaying) "II" else ">", 52) { controller.playPause() }
            Spacer(Modifier.size(10.dp))
            MediaButton(">>", 40) { controller.next() }
        }
        Spacer(Modifier.height(10.dp))
        if (!state.hasNotificationAccess) {
            PillButton("Enable access", Color(0xFF1976D2)) {
                controller.openAccessSettings()
            }
        } else if (!state.hasSession) {
            PillButton("Open player", Color(0xFF2C2C2E)) {
                controller.openSystemPlayer()
            }
        }
    }
}

/**
 * Slim media-controls row meant to be embedded inline (e.g. as an item in the
 * Active Workout screen's list), unlike [MediaControlsScreen] which fills the
 * whole screen as its own destination.
 */
@Composable
fun CompactMediaControls() {
    val context = LocalContext.current
    val controller = remember(context) { MediaControlsController(context) }
    val state by controller.stateFlow.collectAsStateWithLifecycle()

    DisposableEffect(controller) {
        controller.start()
        onDispose { controller.stop() }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1C1C1E), shape = RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {

        Text(
            state.title,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(6.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            MediaButton("<<", 28) { controller.previous() }
            Spacer(Modifier.size(8.dp))
            MediaButton(if (state.isPlaying) "II" else ">", 36) { controller.playPause() }
            Spacer(Modifier.size(8.dp))
            MediaButton(">>", 28) { controller.next() }
        }
    }
}

@Composable
private fun MediaButton(label: String, size: Int, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .background(Color(0xFF1C1C1E), shape = CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = (size / 3).sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun PillButton(label: String, color: Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth(0.85f)
            .background(color, shape = CircleShape)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}
