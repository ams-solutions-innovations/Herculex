package com.ams.herculex.analytics

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.sync.CnsStore
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll

@Composable
fun CnsScreen(navController: NavController) {
    val context = LocalContext.current
    val readiness = CnsStore.readinessPct(context)
    val status = CnsStore.status(context)

    val listState = rememberScalingLazyListState()

    val statusColor = when {
        readiness >= 70 -> Color(0xFF4CAF50) // Emerald Green (Fresh)
        readiness >= 40 -> Color(0xFFFFA726) // Orange (Moderate)
        else -> Color(0xFFEF5350)           // Red (Fatigued)
    }

    val recommendation = when {
        readiness >= 70 -> "Optimal CNS readiness. You are primed for heavy compound lifts and high-intensity sets."
        readiness >= 40 -> "Moderate CNS load. Training capacity is normal. Ensure adequate rest periods between heavy sets."
        else -> "Elevated CNS fatigue. Consider taking an extra rest day or reducing volume and intensity."
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        contentPadding = PaddingValues(top = 36.dp, bottom = 44.dp, start = 14.dp, end = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "CNS READINESS",
                    color = Color(0xFF9DB4F2),
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                    letterSpacing = 1.sp,
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "$readiness%",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 38.sp,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Box(
                    modifier = Modifier
                        .background(statusColor.copy(alpha = 0.2f), shape = RoundedCornerShape(12.dp))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = status.uppercase(),
                        color = statusColor,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp,
                    )
                }
            }
        }

        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF161A26), shape = RoundedCornerShape(14.dp))
                    .padding(12.dp)
            ) {
                Text(
                    text = recommendation,
                    color = Color(0xFFD0D7E8),
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        item {
            OneUiPill(
                title = "Back",
                style = OneUiPillStyle.SlateNavy,
                onClick = { navController.popBackStack() },
            )
        }
    }
}
