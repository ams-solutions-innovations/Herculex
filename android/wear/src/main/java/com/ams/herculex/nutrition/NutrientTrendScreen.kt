package com.ams.herculex.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll
import org.json.JSONArray

data class DayTrendItem(
    val date: String,
    val dayLabel: String,
    val value: Int,
    val isToday: Boolean = false,
)

data class NutrientConfig(
    val key: String,
    val name: String,
    val unit: String,
    val icon: String,
    val color: Color,
    val style: OneUiPillStyle,
    val actionRoute: String,
    val actionLabel: String,
    val getValue: (NutritionData) -> Int,
    val getGoal: (NutritionGoals) -> Int,
    val extractDayValue: (org.json.JSONObject) -> Int,
)

private val nutrientConfigs = listOf(
    NutrientConfig(
        key = "calories",
        name = "Calories",
        unit = "kcal",
        icon = "⚡",
        color = Color(0xFF42A5F5),
        style = OneUiPillStyle.RoyalBlue,
        actionRoute = "add_calories",
        actionLabel = "Add calories",
        getValue = { it.calories },
        getGoal = { it.calorieGoal },
        extractDayValue = { it.optInt("calories", 0) },
    ),
    NutrientConfig(
        key = "protein",
        name = "Protein",
        unit = "g",
        icon = "🥩",
        color = Color(0xFFFFA726),
        style = OneUiPillStyle.Terracotta,
        actionRoute = "log_food",
        actionLabel = "Log food",
        getValue = { it.protein },
        getGoal = { it.proteinGoal },
        extractDayValue = { it.optInt("protein", 0) },
    ),
    NutrientConfig(
        key = "carbs",
        name = "Carbs",
        unit = "g",
        icon = "🌾",
        color = Color(0xFF26C6DA),
        style = OneUiPillStyle.SlateNavy,
        actionRoute = "log_food",
        actionLabel = "Log food",
        getValue = { it.carbs },
        getGoal = { it.carbsGoal },
        extractDayValue = { it.optInt("carbs", 0) },
    ),
    NutrientConfig(
        key = "fats",
        name = "Fats",
        unit = "g",
        icon = "🥑",
        color = Color(0xFFBA68C8),
        style = OneUiPillStyle.VioletIndigo,
        actionRoute = "log_food",
        actionLabel = "Log food",
        getValue = { it.fats },
        getGoal = { it.fatGoal },
        extractDayValue = { it.optInt("fats", 0) },
    ),
    NutrientConfig(
        key = "water",
        name = "Water",
        unit = "ml",
        icon = "💧",
        color = Color(0xFF80DEEA),
        style = OneUiPillStyle.AccentBlue,
        actionRoute = "add_water",
        actionLabel = "Add water",
        getValue = { it.water },
        getGoal = { it.waterGoal },
        extractDayValue = { it.optInt("water", 0) },
    ),
)

fun resolveNutrientConfig(nutrientKey: String): NutrientConfig {
    val normalized = nutrientKey.trim().lowercase()
    return when (normalized) {
        "protein", "p" -> nutrientConfigs[1]
        "carbs", "carb", "c" -> nutrientConfigs[2]
        "fats", "fat", "f" -> nutrientConfigs[3]
        "water" -> nutrientConfigs[4]
        else -> nutrientConfigs[0] // calories / kcal default
    }
}

@Composable
fun NutrientTrendScreen(
    navController: NavController,
    viewModel: NutritionViewModel,
    nutrientKey: String,
) {
    val data by viewModel.data.collectAsState()
    val goals by viewModel.goals.collectAsState()
    val config = remember(nutrientKey) { resolveNutrientConfig(nutrientKey) }

    val todayValue = config.getValue(data)
    val goalValue = config.getGoal(goals)

    val listState = rememberScalingLazyListState()

    val trendItems = remember(data.nutrientTrendsJson, todayValue) {
        val list = mutableListOf<DayTrendItem>()
        try {
            val array = JSONArray(data.nutrientTrendsJson)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val rawVal = config.extractDayValue(obj)
                val isToday = (i == array.length() - 1)
                val dayVal = if (isToday && todayValue > 0) todayValue else rawVal
                val rawDay = obj.optString("day", "")
                val dayLabel = if (rawDay.length > 3) rawDay.substring(0, 3) else rawDay
                list.add(
                    DayTrendItem(
                        date = obj.optString("date", ""),
                        dayLabel = if (dayLabel.isNotBlank()) dayLabel else if (isToday) "Today" else "D${i + 1}",
                        value = dayVal,
                        isToday = isToday,
                    )
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // If no history array was synced yet, provide fallback with today's value
        if (list.isEmpty()) {
            list.add(
                DayTrendItem(
                    date = "Today",
                    dayLabel = "Today",
                    value = todayValue,
                    isToday = true,
                )
            )
        }
        list
    }

    val loggedItems = trendItems.filter { it.value > 0 }
    val avgValue = if (loggedItems.isNotEmpty()) {
        loggedItems.map { it.value }.average().toInt()
    } else {
        todayValue
    }

    val diffVsGoal = if (goalValue > 0) avgValue - goalValue else 0
    val maxValInChart = maxOf(goalValue, trendItems.maxOfOrNull { it.value } ?: goalValue, 1)

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 36.dp, bottom = 48.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── 1. Title Header ───────────────────────────────────────────────────
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "${config.icon} ${config.name} Trends",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                )
                Text(
                    text = "7-day overview",
                    color = Color.Gray,
                    fontSize = 11.sp,
                )
            }
        }

        // ── 2. 7-Day Average Card ─────────────────────────────────────────────
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(config.style.containerColor)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "7-DAY AVERAGE",
                    color = config.style.secondaryColor,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.5.sp,
                )
                Spacer(Modifier.height(2.dp))
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = "$avgValue",
                        color = config.color,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp,
                    )
                    Text(
                        text = if (config.unit.isNotEmpty()) " ${config.unit}/day" else " /day",
                        color = Color.White,
                        fontSize = 11.sp,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }
                Spacer(Modifier.height(2.dp))
                val diffText = when {
                    goalValue <= 0 -> "Goal: $goalValue ${config.unit}"
                    diffVsGoal == 0 -> "On daily target ($goalValue ${config.unit})"
                    diffVsGoal > 0 -> "+$diffVsGoal ${config.unit} above target"
                    else -> "${diffVsGoal} ${config.unit} below target"
                }
                Text(
                    text = diffText,
                    color = if (diffVsGoal >= 0) Color(0xFF81C784) else Color(0xFFFFB74D),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }

        // ── 3. 7-Day Mini Bar Chart ───────────────────────────────────────────
        if (trendItems.size >= 2) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(Color(0xFF161B26))
                        .padding(horizontal = 10.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = "LAST 7 DAYS",
                        color = Color(0xFFA0AABF),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 0.5.sp,
                        modifier = Modifier.padding(bottom = 6.dp),
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        trendItems.takeLast(7).forEach { item ->
                            val heightFraction = if (maxValInChart > 0) {
                                (item.value.toFloat() / maxValInChart.toFloat()).coerceIn(0.08f, 1f)
                            } else 0.08f

                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Bottom,
                                modifier = Modifier.fillMaxHeight(),
                            ) {
                                Box(
                                    modifier = Modifier
                                        .width(12.dp)
                                        .fillMaxHeight(heightFraction)
                                        .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                        .background(
                                            if (item.isToday) config.color
                                            else if (item.value >= goalValue && goalValue > 0) config.color.copy(alpha = 0.85f)
                                            else Color(0xFF333E56)
                                        ),
                                )
                                Spacer(Modifier.height(3.dp))
                                Text(
                                    text = item.dayLabel.take(1).uppercase(),
                                    color = if (item.isToday) config.color else Color.LightGray,
                                    fontSize = 9.sp,
                                    fontWeight = if (item.isToday) FontWeight.Bold else FontWeight.Normal,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }
                }
            }
        }

        // ── 4. Today's Status ─────────────────────────────────────────────────
        item {
            val progress = if (goalValue > 0) (todayValue.toFloat() / goalValue.toFloat()).coerceIn(0f, 1f) else 0f
            val pct = if (goalValue > 0) ((todayValue.toFloat() / goalValue.toFloat()) * 100).toInt() else 0

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(CircleShape)
                    .background(config.style.containerColor)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Today", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                    Text(
                        text = "$todayValue / $goalValue ${config.unit} ($pct%)",
                        color = config.color,
                        fontWeight = FontWeight.Bold,
                        fontSize = 11.sp,
                    )
                }
                Spacer(Modifier.height(4.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(CircleShape)
                        .background(Color(0x33FFFFFF)),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(progress)
                            .height(4.dp)
                            .clip(CircleShape)
                            .background(config.color),
                    )
                }
            }
        }

        // ── 5. Daily History Breakdown ────────────────────────────────────────
        item {
            Text(
                text = "History",
                color = Color.Gray,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 6.dp, top = 4.dp),
            )
        }

        items(trendItems.reversed()) { item ->
            val itemProgress = if (goalValue > 0) (item.value.toFloat() / goalValue.toFloat()).coerceIn(0f, 1f) else 0f
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(CircleShape)
                    .background(Color(0xFF1E2433))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = if (item.isToday) "Today" else if (item.date.isNotBlank()) item.date else item.dayLabel,
                            color = if (item.isToday) config.color else Color.White,
                            fontWeight = if (item.isToday) FontWeight.Bold else FontWeight.Medium,
                            fontSize = 11.sp,
                        )
                        Text(
                            text = "${item.value} ${config.unit}",
                            color = if (item.value > 0) Color.White else Color.Gray,
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.sp,
                        )
                    }
                    if (goalValue > 0) {
                        Spacer(Modifier.height(3.dp))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(3.dp)
                                .clip(CircleShape)
                                .background(Color(0x22FFFFFF)),
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth(itemProgress)
                                    .height(3.dp)
                                    .clip(CircleShape)
                                    .background(if (item.isToday) config.color else config.color.copy(alpha = 0.7f)),
                            )
                        }
                    }
                }
            }
        }

        // ── 6. Bottom Action Button ───────────────────────────────────────────
        item {
            OneUiPill(
                title = config.actionLabel,
                icon = "+",
                style = OneUiPillStyle.RoyalBlue,
                onClick = { navController.navigate(config.actionRoute) },
            )
        }
    }
}
