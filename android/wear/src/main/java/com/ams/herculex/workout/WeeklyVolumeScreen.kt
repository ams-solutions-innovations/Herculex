package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.nutrition.NutritionViewModel
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import org.json.JSONArray

data class MuscleVolumeItem(
    val muscle: String,
    val tonnage: Double,
    val sets: Double
)

@Composable
fun WeeklyVolumeScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    val listState = rememberScalingLazyListState()

    val volumeItems = remember(data.weeklyVolumeJson) {
        val list = mutableListOf<MuscleVolumeItem>()
        try {
            val array = JSONArray(data.weeklyVolumeJson)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                list.add(
                    MuscleVolumeItem(
                        muscle = obj.getString("muscle"),
                        tonnage = obj.getDouble("tonnage"),
                        sets = obj.getDouble("sets")
                    )
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        list
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 40.dp, bottom = 48.dp, start = 14.dp, end = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text       = "Weekly Volume",
                    color      = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize   = 16.sp,
                    modifier   = Modifier.padding(bottom = 2.dp),
                )
                Text(
                    text       = "Muscle breakdown",
                    color      = Color.Gray,
                    fontSize   = 11.sp,
                )
            }
        }

        if (volumeItems.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 20.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No sets logged yet.",
                        color = Color.LightGray,
                        fontSize = 12.sp,
                    )
                }
            }
        } else {
            items(volumeItems) { volItem ->
                val tonnageText = if (volItem.tonnage >= 1000) {
                    "%.1ft".format(volItem.tonnage / 1000f)
                } else {
                    "${volItem.tonnage.toInt()}kg"
                }

                OneUiPill(
                    title = volItem.muscle,
                    statValue = tonnageText,
                    statLabel = "${volItem.sets.toInt()} sets",
                    style = OneUiPillStyle.SlateNavy,
                )
            }
        }
    }
}
