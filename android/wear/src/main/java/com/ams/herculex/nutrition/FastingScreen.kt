package com.ams.herculex.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay

@Composable
fun FastingScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    val fasting = data.fastingSnapshot
    var nowEpochMs by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(fasting.hasActiveFast, fasting.startedAtEpochMs) {
        while (fasting.hasActiveFast) {
            nowEpochMs = System.currentTimeMillis()
            delay(1_000)
        }
    }

    val elapsedText = if (fasting.hasActiveFast) fasting.elapsedText(nowEpochMs) else data.fasting
    val progress = fasting.progress(nowEpochMs)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.weight(1f))

        Text(
            text = "FASTING TIMER",
            color = Color.Gray,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Circular Ring Visual
        Box(
            modifier = Modifier
                .size(105.dp)
                .background(Color(0xFF2C1E4A), shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator(
                progress = progress,
                modifier = Modifier.fillMaxSize(),
                indicatorColor = Color(0xFF64D2FF),
                trackColor = Color(0xFF2C1E4A),
                strokeWidth = 5.dp,
            )
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = elapsedText,
                    color = Color(0xFFD1C4E9), // Light purple
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = if (fasting.hasActiveFast) "elapsed" else "idle",
                    color = Color.LightGray,
                    fontSize = 10.sp,
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

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
                .height(40.dp)
        ) {
            Text(if (fasting.hasActiveFast) "Stop Fast" else "Start Fast", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}
