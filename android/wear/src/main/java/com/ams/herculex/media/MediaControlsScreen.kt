package com.ams.herculex.media

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Text
import com.ams.herculex.R
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

    LaunchedEffect(controller) {
        while (true) {
            delay(1000)
            controller.refresh()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .mediaVolumeRotary { controller.adjustVolume(it) },
        contentAlignment = Alignment.Center,
    ) {
        // ── 1. Fullscreen Media Artwork / Default Backdrop ──────────────────
        val artworkBitmap = state.artwork
        if (artworkBitmap != null) {
            Image(
                bitmap = artworkBitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Image(
                painter = painterResource(id = R.drawable.default_media_cover),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }

        // ── 2. Dark Spotify Scrim Gradient Overlay for Contrast & Readability ─
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.75f),
                            Color(0xFF121212).copy(alpha = 0.85f),
                            Color.Black.copy(alpha = 0.95f),
                        )
                    )
                )
        )

        // ── 3. Foreground: Title, Artist, Live Equalizer, Progress & Central Controls ───
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Bezel spacing for round watch screen
            Spacer(Modifier.height(20.dp))

            // Spotify Live Badge + Equalizer
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth(),
            ) {
                LiveEqualizerVisualizer(isPlaying = state.isPlaying)
                Spacer(Modifier.width(6.dp))
                Text(
                    text = if (state.isSpotify) "Spotify Live" else state.appName,
                    color = SpotifyGreen,
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Bold,
                )
            }

            Spacer(Modifier.height(6.dp))

            if (!controller.hasMediaAccess() && state.source != "phone") {
                Text(
                    text = "Media controls permission",
                    color = Color.White,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF1F1F1F))
                        .clickable { controller.openMediaAccessSettings() }
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                )
                Spacer(Modifier.height(4.dp))
            }

            // Track Title (bold, high-contrast white)
            Text(
                text = state.title,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth(0.90f),
            )

            Spacer(Modifier.height(2.dp))

            // Artist Subtitle (subtle accent green / gray)
            Text(
                text = state.artist,
                color = if (state.isPlaying) SpotifyGreen else SpotifySecondaryText,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth(0.85f),
            )

            Spacer(Modifier.height(8.dp))

            // ── Live Progress Line ────────────────────────────────────
            val progress = state.progress
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.78f)
                    .height(3.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(Color(0xFF333333)),
            ) {
                if (progress > 0f) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(progress)
                            .height(3.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(SpotifyGreen),
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            // Central Media Transport Controls: Previous | Play/Pause | Next
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Previous Button
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF222222))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = { controller.previous() },
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    SpotifySkipPreviousIcon(modifier = Modifier.size(28.dp))
                }

                Spacer(Modifier.width(14.dp))

                // Play/Pause Button (Large solid Spotify green circle)
                Box(
                    modifier = Modifier
                        .size(62.dp)
                        .clip(CircleShape)
                        .background(if (state.isPlaying) SpotifyGreen else Color.White)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = { controller.playPause() },
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (state.isPlaying) {
                        SpotifyPauseIcon(modifier = Modifier.size(22.dp), color = Color.Black)
                    } else {
                        SpotifyPlayIcon(modifier = Modifier.size(22.dp), color = Color.Black)
                    }
                }

                Spacer(Modifier.width(14.dp))

                // Next Button
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF222222))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = { controller.next() },
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    SpotifySkipNextIcon(modifier = Modifier.size(28.dp))
                }
            }

            // Bottom space
            Spacer(Modifier.height(24.dp))
        }
    }
}

/**
 * Compact inline media controls row embedded in the Active Workout screen.
 * Delegates to the modern [SpotifyLiveMediaBar].
 */
@Composable
fun CompactMediaControls() {
    SpotifyLiveMediaBar()
}
