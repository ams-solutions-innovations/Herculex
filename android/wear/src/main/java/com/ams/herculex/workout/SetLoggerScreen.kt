package com.ams.herculex.workout

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Picker
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import androidx.wear.compose.material.rememberPickerState
import com.ams.herculex.media.MediaControlsScreen
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import kotlinx.coroutines.launch

private val weightOptions = (0..400).map { it * 0.5 }
private val repsOptions = (1..50).toList()
private val rpeOptions = (2..20).map { it * 0.5 }
private data class WatchSetType(val id: String, val label: String)
enum class RotaryTarget { WEIGHT, REPS }

private val setTypes = listOf(
    WatchSetType("standard", "Normal"),
    WatchSetType("warmup", "Warm up"),
    WatchSetType("drop", "Drop set"),
    WatchSetType("forced", "Failure"),
    WatchSetType("rest_pause", "Rest-Pause"),
    WatchSetType("myo_reps", "Myo Reps"),
    WatchSetType("partials", "Partials"),
    WatchSetType("negatives", "Negatives"),
    WatchSetType("pause", "Pause Reps"),
)
private val accessoryOptions = listOf("None", "Belt", "Straps", "Bands", "Chains")

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SetLoggerScreen(
    navController: NavController,
    viewModel: WorkoutViewModel,
    startExerciseIndex: Int,
) {
    val session by viewModel.session.collectAsState()
    val heartRate by viewModel.heartRate.collectAsState()

    LaunchedEffect(session) {
        if (session == null) navController.popBackStack("home", inclusive = false)
    }
    val s = session ?: return

    var exerciseIndex by remember(startExerciseIndex) {
        val initialIndex = startExerciseIndex.takeIf { it in s.exercises.indices }
            ?: s.currentExerciseIndex
        mutableIntStateOf(initialIndex)
    }
    var previousSize by remember { mutableIntStateOf(s.exercises.size) }
    LaunchedEffect(s.exercises.size) {
        if (s.exercises.size > previousSize) {
            exerciseIndex = s.exercises.lastIndex
            viewModel.selectExerciseInSession(exerciseIndex)
        } else if (s.exercises.isNotEmpty() && exerciseIndex !in s.exercises.indices) {
            exerciseIndex = s.exercises.lastIndex
        }
        previousSize = s.exercises.size
    }
    val exercise = s.exercises.getOrNull(exerciseIndex) ?: return
    val setNumber = exercise.completedSets + 1
    val plannedOrCurrentSet = remember(exerciseIndex, exercise.sets) {
        exercise.sets.firstOrNull { !it.completed } ?: exercise.sets.lastOrNull()
    }

    var setType by remember(exerciseIndex, plannedOrCurrentSet?.setType, plannedOrCurrentSet?.isWarmup) {
        val plannedType = if (plannedOrCurrentSet?.isWarmup == true) {
            "warmup"
        } else {
            plannedOrCurrentSet?.setType ?: "standard"
        }
        mutableStateOf(setTypes.firstOrNull { it.id == plannedType } ?: setTypes.first())
    }
    var selectedAccessory by remember { mutableStateOf<String?>(null) }
    var showRpeDialog by remember { mutableStateOf(false) }

    val initWeightIdx = remember(exerciseIndex, plannedOrCurrentSet?.weight) {
        val initialWeight = plannedOrCurrentSet?.weight?.takeIf { it > 0 }
            ?: exercise.template.plannedSets.firstOrNull { (it.targetWeightKg ?: 0.0) > 0 }?.targetWeightKg
            ?: exercise.template.prevWeight
        weightOptions.indexOfFirst { it >= initialWeight }.takeIf { it >= 0 } ?: 0
    }
    val initRepsIdx = remember(exerciseIndex, plannedOrCurrentSet?.reps) {
        val initialReps = plannedOrCurrentSet?.reps?.takeIf { it > 0 }
            ?: exercise.template.plannedSets.firstOrNull { (it.targetReps ?: 0) > 0 }?.targetReps
            ?: exercise.template.prevReps.takeIf { it > 0 }
            ?: 8
        (initialReps - 1).coerceIn(0, repsOptions.size - 1)
    }

    val weightState = rememberPickerState(
        initialNumberOfOptions = weightOptions.size,
        initiallySelectedOption = initWeightIdx,
        repeatItems = false,
    )
    val repsState = rememberPickerState(
        initialNumberOfOptions = repsOptions.size,
        initiallySelectedOption = initRepsIdx,
        repeatItems = false,
    )

    var rotaryTarget by remember { mutableStateOf(RotaryTarget.WEIGHT) }
    val setPickerFocus = remember { FocusRequester() }

    val selectedWeight = weightOptions[weightState.selectedOption]
    val selectedReps = repsOptions[repsState.selectedOption]
    val prevWeight = "%.1f".format(exercise.template.prevWeight)

    val pagerState = rememberPagerState(pageCount = { 3 })
    // Page 0 = glance (swipe down), 1 = the set logger (default), 2 = media controls (swipe up).
    val mediaPagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })

    LaunchedEffect(pagerState.currentPage, mediaPagerState.currentPage) {
        if (pagerState.currentPage == 0 && mediaPagerState.currentPage == 1) {
            runCatching { setPickerFocus.requestFocus() }
        }
    }

    // NestedScrollConnection to intercept swipe-right on page 0 and trigger popBackStack()
    val nestedScrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (pagerState.currentPage == 0 && available.x > 25f) {
                    navController.popBackStack()
                    return available
                }
                return Offset.Zero
            }
        }
    }

    VerticalPager(
        state = mediaPagerState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) { verticalPage ->
        if (verticalPage == 0) {
            WorkoutGlanceScreen(session = s)
        } else if (verticalPage == 1) {
            HorizontalPager(
        state = pagerState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .nestedScroll(nestedScrollConnection),
    ) { page ->
        when (page) {
            0 -> {
                // Page 0: Set Logger Screen
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .attachWorkoutSetPickerRotary(
                            weightState = weightState,
                            weightOptionsCount = weightOptions.size,
                            repsState = repsState,
                            repsOptionsCount = repsOptions.size,
                            rotaryTarget = rotaryTarget,
                            focusRequester = setPickerFocus,
                        )
                        .padding(top = 18.dp, bottom = 4.dp, start = 10.dp, end = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    // Header: Main exercise name and equipment variant on second line.
                    val rawName = exercise.template.name
                    val mainName = if (rawName.contains("(")) rawName.substringBefore("(").trim() else rawName
                    val qualifier = if (rawName.contains("(")) rawName.substringAfter("(").substringBefore(")").trim() else ""
                    val subName = qualifier.ifEmpty {
                        exercise.template.equipmentVariant?.let { ExerciseCatalog.equipmentLabel(it) } ?: ""
                    }

                    Text(
                        mainName,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 12.dp),
                    )
                    if (subName.isNotEmpty()) {
                        Text(
                            subName,
                            color = Color(0xFFB0BEC5),
                            fontWeight = FontWeight.Medium,
                            fontSize = 11.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(horizontal = 12.dp),
                        )
                    }
                    
                    Spacer(Modifier.height(4.dp))
                    
                    // Pickers (Weight & Reps with attachPickerRotary) and Set Control in between
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        // Weight Picker Column
                        Column(
                            modifier = Modifier
                                .width(64.dp)
                                .clickable {
                                    rotaryTarget = RotaryTarget.WEIGHT
                                    runCatching { setPickerFocus.requestFocus() }
                                },
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text("Kg", color = if (rotaryTarget == RotaryTarget.WEIGHT) Color(0xFF42A5F5) else Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Picker(
                                state = weightState,
                                contentDescription = "Weight",
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .weight(1f),
                            ) { index ->
                                val isSelected = index == weightState.selectedOption
                                Text(
                                    text = "%.1f".format(weightOptions[index]),
                                    color = if (isSelected && rotaryTarget == RotaryTarget.WEIGHT) Color(0xFF42A5F5) else Color.White,
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                    fontSize = if (isSelected) 19.sp else 13.sp,
                                )
                            }
                        }

                        // Middle Column: Set Indicator (W/D/F if warmup/drop/failure, 1/3 below)
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        ) {
                            val indicatorChar = when (setType.id) {
                                "warmup" -> "W"
                                "drop" -> "D"
                                "forced" -> "F"
                                "rest_pause" -> "R"
                                else -> if (setType.id != "standard") setType.label.take(1).uppercase() else ""
                            }
                            if (indicatorChar.isNotEmpty()) {
                                Text(
                                    indicatorChar,
                                    color = Color(0xFFFFA726),
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                )
                                Spacer(Modifier.height(2.dp))
                            }
                            Text(
                                "$setNumber/${exercise.template.targetSets}",
                                color = Color.White,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }

                        // Reps Picker Column
                        Column(
                            modifier = Modifier
                                .width(64.dp)
                                .clickable {
                                    rotaryTarget = RotaryTarget.REPS
                                    runCatching { setPickerFocus.requestFocus() }
                                },
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text("Reps", color = if (rotaryTarget == RotaryTarget.REPS) Color(0xFF42A5F5) else Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Picker(
                                state = repsState,
                                contentDescription = "Reps",
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .weight(1f),
                            ) { index ->
                                val isSelected = index == repsState.selectedOption
                                Text(
                                    text = "${repsOptions[index]}",
                                    color = if (isSelected && rotaryTarget == RotaryTarget.REPS) Color(0xFF42A5F5) else Color.White,
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                    fontSize = if (isSelected) 21.sp else 14.sp,
                                )
                            }
                        }
                    }
                    
                    // Set Type & Accessory Indicator & Prev Perf
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val tags = mutableListOf<String>()
                        if (setType.id != "standard") tags.add(setType.label)
                        if (!selectedAccessory.isNullOrEmpty() && selectedAccessory != "None") tags.add(selectedAccessory!!)
                        
                        if (tags.isNotEmpty()) {
                            Text("[${tags.joinToString(" / ")}] ", color = Color(0xFF26C6DA), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }
                        Text("prev. $prevWeight kg x ${exercise.template.prevReps}", color = Color(0xFF757575), fontSize = 10.sp)
                    }
                    
                    Spacer(Modifier.height(4.dp))
                    
                    // Bottom Nav Buttons: Arced arrangement
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 4.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Box(modifier = Modifier.offset(y = (-10).dp)) {
                            NavCircleButton(label = "<", bg = Color(0xFF2C2C2E), size = 36) {
                                if (exerciseIndex > 0) {
                                    exerciseIndex -= 1
                                    viewModel.selectExerciseInSession(exerciseIndex)
                                } else {
                                    navController.popBackStack()
                                }
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        NavCircleButton(label = "OK", bg = Color(0xFF1976D2), size = 44) {
                            showRpeDialog = true
                        }
                        Spacer(Modifier.width(12.dp))
                        Box(modifier = Modifier.offset(y = (-10).dp)) {
                            NavCircleButton(label = ">", bg = Color(0xFF2C2C2E), size = 36) {
                                if (exerciseIndex < s.exercises.size - 1) {
                                    exerciseIndex += 1
                                    viewModel.selectExerciseInSession(exerciseIndex)
                                }
                            }
                        }
                    }
                }
            }
            1 -> {
                // Page 1: Set Type Selection & Add/Remove Set Buttons
                val setTypeListState = rememberScalingLazyListState()

                ScalingLazyColumn(
                    state = setTypeListState,
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black)
                        .attachRotaryScroll(setTypeListState),
                    autoCentering = null,
                    contentPadding = PaddingValues(top = 10.dp, bottom = 20.dp, start = 12.dp, end = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    item {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                "Set Type",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                modifier = Modifier.padding(bottom = 2.dp),
                            )
                        }
                    }
                    items(setTypes) { type ->
                        val isSel = setType.id == type.id
                        OneUiPill(
                            title = type.label,
                            icon = if (isSel) "✓" else "•",
                            style = if (isSel) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy,
                            onClick = { setType = type },
                        )
                    }
                    item {
                        Spacer(Modifier.height(4.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Box(modifier = Modifier.weight(1f)) {
                                OneUiPill(
                                    title = "- Remove",
                                    style = OneUiPillStyle.DangerTransparent,
                                    onClick = { viewModel.removeSetFromExercise(exerciseIndex) },
                                )
                            }
                            Box(modifier = Modifier.weight(1f)) {
                                OneUiPill(
                                    title = "+ Add Set",
                                    icon = "+",
                                    style = OneUiPillStyle.AccentBlue,
                                    onClick = { viewModel.addSetToExercise(exerciseIndex) },
                                )
                            }
                        }
                    }
                }
            }
            2 -> {
                // Page 2: Accessories per set Selection
                val accListState = rememberScalingLazyListState()

                ScalingLazyColumn(
                    state = accListState,
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black)
                        .attachRotaryScroll(accListState),
                    autoCentering = null,
                    contentPadding = PaddingValues(top = 10.dp, bottom = 20.dp, start = 14.dp, end = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    item {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                "Accessories",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                modifier = Modifier.padding(bottom = 2.dp),
                            )
                        }
                    }
                    items(accessoryOptions) { acc ->
                        val isSelected = (acc == "None" && selectedAccessory == null) || selectedAccessory == acc
                        OneUiPill(
                            title = acc,
                            icon = if (isSelected) "✓" else "⚙️",
                            style = if (isSelected) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy,
                            onClick = {
                                selectedAccessory = if (acc == "None") null else acc
                            },
                        )
                    }
                }
            }
        }
            }
        } else {
            MediaControlsScreen()
        }
    }

    if (showRpeDialog) {
        Dialog(showDialog = showRpeDialog, onDismissRequest = { showRpeDialog = false }) {
            val rpeState = rememberPickerState(initialNumberOfOptions = rpeOptions.size, initiallySelectedOption = 14)
            val rpeFocus = remember { FocusRequester() }
            
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
                    .padding(horizontal = 20.dp, vertical = 20.dp)
                    .attachPickerRotary(
                        pickerState = rpeState,
                        maxOptions = rpeOptions.size,
                        focusRequester = rpeFocus,
                        isFocused = true,
                    ),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text("RPE (Effort)", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.height(6.dp))
                Picker(
                    state = rpeState,
                    contentDescription = "RPE",
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                ) { index ->
                    val isSelected = index == rpeState.selectedOption
                    Text(
                        text = if (rpeOptions[index] % 1.0 == 0.0) {
                            rpeOptions[index].toInt().toString()
                        } else {
                            "%.1f".format(rpeOptions[index])
                        },
                        color = Color.White,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                        fontSize = if (isSelected) 24.sp else 16.sp,
                    )
                }
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    NavCircleButton(label = "X", bg = Color(0xFF2C2C2E), size = 44) { showRpeDialog = false }
                    Spacer(Modifier.width(14.dp))
                    NavCircleButton(label = "OK", bg = Color(0xFF4CAF50), size = 44) {
                        showRpeDialog = false
                        viewModel.logSet(
                            exerciseIndex = exerciseIndex,
                            weight = selectedWeight,
                            reps = selectedReps,
                            rpe = rpeOptions[rpeState.selectedOption],
                            setType = setType.id,
                            accessory = selectedAccessory,
                        )
                        val updatedSession = viewModel.session.value
                        if (updatedSession != null) {
                            val lastEx = updatedSession.exercises.last()
                            if (updatedSession.currentExerciseIndex == updatedSession.exercises.size - 1 && lastEx.completedSets >= lastEx.template.targetSets) {
                                navController.popBackStack()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NavCircleButton(label: String, bg: Color, size: Int, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .background(bg, shape = CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = (size / 2.5).sp, fontWeight = FontWeight.Bold)
    }
}
