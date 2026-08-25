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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog

@Composable
fun VolumeControlDialog(
    showDialog: Boolean,
    onDismissRequest: () -> Unit,
    currentVolume: Int,
    maxVolume: Int,
    onVolumeChanged: (Int) -> Unit,
) {
    if (!showDialog) return

    Dialog(
        showDialog = showDialog,
        onDismissRequest = onDismissRequest,
    ) {
        val safeMax = if (maxVolume > 0) maxVolume else 15
        val progress = (currentVolume.toFloat() / safeMax.toFloat()).coerceIn(0f, 1f)
        val percent = (progress * 100).toInt()

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0F0D15))
                .padding(12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "Volume",
                    color = Color(0xFFD0BCFF),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "$percent%",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(Modifier.height(8.dp))

                // Volume Bar
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.75f)
                        .height(10.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .background(Color(0xFF2B2930)),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(progress)
                            .height(10.dp)
                            .clip(RoundedCornerShape(5.dp))
                            .background(
                                Brush.horizontalGradient(
                                    listOf(Color(0xFFD0BCFF), Color(0xFF9A82DB))
                                )
                            ),
                    )
                }

                Spacer(Modifier.height(14.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(0.85f),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Decrease button
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF211F26))
                            .clickable {
                                val next = (currentVolume - 1).coerceAtLeast(0)
                                onVolumeChanged(next)
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("−", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    }

                    // Mute / Speaker icon
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(if (currentVolume == 0) Color(0xFF381E72) else Color(0xFF211F26))
                            .clickable {
                                if (currentVolume > 0) {
                                    onVolumeChanged(0)
                                } else {
                                    onVolumeChanged(safeMax / 2)
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(if (currentVolume == 0) "🔇" else "🔊", fontSize = 16.sp)
                    }

                    // Increase button
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF211F26))
                            .clickable {
                                val next = (currentVolume + 1).coerceAtMost(safeMax)
                                onVolumeChanged(next)
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("+", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}
