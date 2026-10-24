package com.ams.herculex.workout

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.ams.herculex.R
import com.ams.herculex.nutrition.NutritionViewModel
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import org.json.JSONArray

data class MuscleVolumeItem(
    val muscle: String,
    val tonnage: Double,
    val sets: Double
)

private val VolumePalette = listOf(
    Color(0xFF4F7BEA),
    Color(0xFF42A5F5),
    Color(0xFF80CBF5),
    Color(0xFF9FB0D4),
    Color(0xFFC0CCEC)
)
private val TileVolumeLabel = Color(0xFF9DB4F2)
private val TileVolumeTrack = Color(0xFF141926)

@Composable
fun WeeklyVolumeScreen(
    navController: NavController,
    nutritionViewModel: NutritionViewModel,
) {
    val data by nutritionViewModel.data.collectAsState()
    var showBreakdown by remember { mutableStateOf(false) }

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

    val sorted = remember(volumeItems) { volumeItems.sortedByDescending { it.tonnage } }
    val total = data.weeklyTonnage
    val totalText = if (total >= 1000f) "%.1f".format(total / 1000f) else "%d".format(total.toInt())
    val unit = if (total >= 1000f) "t" else "kg"

    if (showBreakdown) {
        BackHandler { showBreakdown = false }
        MuscleBreakdownList(
            sorted = sorted,
            totalText = totalText,
            unit = unit,
            weeklySets = data.weeklySets,
            onBackToOverview = { showBreakdown = false },
        )
    } else {
        WeeklyVolumeDialFace(
            sorted = sorted,
            totalText = totalText,
            unit = unit,
            weeklySets = data.weeklySets,
            onOpenBreakdown = { showBreakdown = true },
        )
    }
}

/**
 * 1:1 match of WeeklyVolumeTileService on the watch.
 * Clean, centered dial with outer bezel composition ring, soft domain glow,
 * big tonnage readout, muscle dots legend, and a dedicated Breakdown pill.
 */
@Composable
private fun WeeklyVolumeDialFace(
    sorted: List<MuscleVolumeItem>,
    totalText: String,
    unit: String,
    weeklySets: Int,
    onOpenBreakdown: () -> Unit,
) {
    val dialFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        dialFocus.requestFocus()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(dialFocus)
            .focusable()
            .onRotaryScrollEvent { event ->
                if (event.verticalScrollPixels > 15f) {
                    onOpenBreakdown()
                    true
                } else false
            },
        contentAlignment = Alignment.Center,
    ) {
        // Soft volume domain glow from drawable
        Image(
            painter = painterResource(id = R.drawable.hx_glow_volume),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.FillBounds,
        )

        // Bezel ring split by muscle share of weekly tonnage (same as tile)
        VolumeBezelRing(items = sorted.take(5))

        // Center Content — perfectly balanced on the 227dp round face
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Label: Barbell icon + "WEEKLY VOLUME"
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                    imageVector = HxIcons.Barbell,
                    contentDescription = null,
                    tint = TileVolumeLabel,
                    modifier = Modifier.size(13.dp),
                )
                Spacer(Modifier.width(5.dp))
                Text(
                    text = "WEEKLY VOLUME",
                    color = TileVolumeLabel,
                    fontWeight = FontWeight.Bold,
                    fontSize = 10.sp,
                    letterSpacing = 0.8.sp,
                )
            }

            Spacer(Modifier.height(3.dp))

            // Main Stat: Big tonnage + unit aligned to bottom
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = totalText,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 44.sp,
                    lineHeight = 44.sp,
                )
                Spacer(Modifier.width(3.dp))
                Text(
                    text = unit,
                    color = Color(0xFFA0AABF),
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    modifier = Modifier.padding(bottom = 5.dp),
                )
            }

            // Sets this week
            Text(
                text = "$weeklySets sets · this week",
                color = Color(0xFFA0AABF),
                fontSize = 11.5.sp,
                fontWeight = FontWeight.Normal,
            )

            Spacer(Modifier.height(8.dp))

            // Legend: 3 top muscles with palette dots, or empty hint
            if (sorted.isEmpty()) {
                Text(
                    text = "Log a workout to see volume",
                    color = Color(0xFFA0AABF),
                    fontSize = 10.sp,
                )
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.padding(horizontal = 8.dp),
                ) {
                    sorted.take(3).forEachIndexed { i, m ->
                        if (i > 0) Spacer(Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .background(VolumePalette[i % VolumePalette.size], CircleShape)
                        )
                        Spacer(Modifier.width(3.dp))
                        Text(
                            text = m.muscle,
                            color = Color(0xFFD5DBE8),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                        )
                    }
                }
            }

            Spacer(Modifier.height(10.dp))

            // Breakdown CTA Pill: matches HxTile.pill(126, 34) on the tile
            Row(
                modifier = Modifier
                    .width(128.dp)
                    .height(34.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF202636))
                    .border(1.dp, Color(0xFF323B52), CircleShape)
                    .clickable { onOpenBreakdown() },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .background(Color(0xFF141926), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = HxIcons.Barbell,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(13.dp),
                    )
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "Breakdown",
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(Modifier.width(6.dp))
                Icon(
                    imageVector = HxIcons.Chevron,
                    contentDescription = null,
                    tint = Color(0xFFA0AABF),
                    modifier = Modifier.size(13.dp),
                )
            }
        }
    }
}

/**
 * Breakdown view showing all individual muscles, cleanly scrollable without
 * overlapping or cutting into the bezel ring.
 */
@Composable
private fun MuscleBreakdownList(
    sorted: List<MuscleVolumeItem>,
    totalText: String,
    unit: String,
    weeklySets: Int,
    onBackToOverview: () -> Unit,
) {
    val listState = rememberScalingLazyListState()

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 28.dp, bottom = 44.dp, start = 14.dp, end = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Back to Overview pill
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color(0xFF202636))
                        .border(1.dp, Color(0xFF323B52), CircleShape)
                        .clickable { onBackToOverview() }
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        imageVector = HxIcons.Chevron,
                        contentDescription = null,
                        tint = TileVolumeLabel,
                        modifier = Modifier
                            .size(12.dp)
                            .graphicsLayer(rotationZ = 180f),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Overview",
                        color = Color.White,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }

        // Section header
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Muscle Breakdown",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                )
                Text(
                    text = "$weeklySets sets · $totalText $unit",
                    color = Color.Gray,
                    fontSize = 11.sp,
                )
            }
        }

        if (sorted.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 20.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No sets logged yet this week.",
                        color = Color.LightGray,
                        fontSize = 12.sp,
                    )
                }
            }
        } else {
            items(sorted) { volItem ->
                val tonnageText = if (volItem.tonnage >= 1000) {
                    "%.1ft".format(volItem.tonnage / 1000f)
                } else {
                    "${volItem.tonnage.toInt()}kg"
                }
                val idx = sorted.indexOf(volItem)
                val dotColor = VolumePalette[idx % VolumePalette.size]

                OneUiPill(
                    title = volItem.muscle,
                    statValue = tonnageText,
                    statLabel = "${volItem.sets.toInt()} sets",
                    iconComposable = {
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .background(Color(0xFF141926), CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(10.dp)
                                    .background(dotColor, CircleShape)
                            )
                        }
                    },
                    style = OneUiPillStyle.SlateNavy,
                )
            }
        }
    }
}

/** Full-bezel ring segmented by each muscle's share of weekly tonnage (composition, not progress). */
@Composable
private fun VolumeBezelRing(items: List<MuscleVolumeItem>) {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val stroke = 7.5.dp.toPx()
        val inset = stroke / 2f + 3.dp.toPx()
        val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
        val topLeft = Offset(inset, inset)

        // Subtle track
        drawArc(
            color = TileVolumeTrack,
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(stroke),
        )

        val sum = items.sumOf { it.tonnage }.takeIf { it > 0 } ?: return@Canvas
        val gap = 5.7f
        var start = -90f // 12 o'clock
        items.forEachIndexed { i, m ->
            val sweep = (360f * (m.tonnage / sum).toFloat() - gap).coerceAtLeast(1f)
            drawArc(
                color = VolumePalette[i % VolumePalette.size],
                startAngle = start,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round),
            )
            start += sweep + gap
        }
    }
}

