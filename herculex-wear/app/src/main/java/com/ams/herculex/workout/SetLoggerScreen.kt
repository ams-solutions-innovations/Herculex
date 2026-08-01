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
import kotlinx.coroutines.launch

private val weightOptions = (0..400).map { it * 0.5 }
private val repsOptions = (1..50).toList()
private val rpeOptions = (1..10).toList()
private val setTypes = listOf("Normal", "Warm up", "Drop set", "Failure")
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

    var exerciseIndex by remember(s.currentExerciseIndex) {
        mutableIntStateOf(s.currentExerciseIndex)
    }
    val exercise = s.exercises.getOrNull(exerciseIndex) ?: return
    val setNumber = exercise.completedSets + 1

    var setType by remember { mutableStateOf("Normal") }
    var selectedAccessory by remember { mutableStateOf<String?>(null) }
    var showRpeDialog by remember { mutableStateOf(false) }

    val initWeightIdx = remember(exerciseIndex) {
        weightOptions.indexOfFirst { it >= exercise.template.prevWeight }.takeIf { it >= 0 } ?: 0
    }
    val initRepsIdx = remember(exerciseIndex) {
        (exercise.template.prevReps - 1).coerceIn(0, repsOptions.size - 1)
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

    var focusedCol by remember { mutableIntStateOf(0) }
    val weightFocus = remember { FocusRequester() }
    val repsFocus = remember { FocusRequester() }

    val selectedWeight = weightOptions[weightState.selectedOption]
    val selectedReps = repsOptions[repsState.selectedOption]
    val prevWeight = "%.1f".format(exercise.template.prevWeight)

    val pagerState = rememberPagerState(pageCount = { 3 })

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
                        .padding(horizontal = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(Modifier.height(4.dp))
                    
                    // Header: Main exercise name and equipment variant on second line
                    val rawName = exercise.template.name
                    val mainName = if (rawName.contains("(")) rawName.substringBefore("(").trim() else rawName
                    val subName = if (rawName.contains("(")) rawName.substringAfter("(").substringBefore(")").trim() else ""

                    Text(
                        mainName,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                    if (subName.isNotEmpty()) {
                        Text(
                            subName,
                            color = Color(0xFFB0BEC5),
                            fontWeight = FontWeight.Medium,
                            fontSize = 10.sp,
                            modifier = Modifier.padding(horizontal = 8.dp),
                        )
                    }
                    
                    Spacer(Modifier.height(2.dp))
                    
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
                                .clickable { focusedCol = 0 }
                                .attachPickerRotary(
                                    pickerState = weightState,
                                    maxOptions = weightOptions.size,
                                    focusRequester = weightFocus,
                                    isFocused = focusedCol == 0,
                                ),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text("Kg", color = if (focusedCol == 0) Color(0xFF42A5F5) else Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
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
                                    color = if (isSelected && focusedCol == 0) Color(0xFF42A5F5) else Color.White,
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                    fontSize = if (isSelected) 19.sp else 13.sp,
                                )
                            }
                        }

                        // Middle Column: Set Indicator (W above, 1/4 below)
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        ) {
                            val indicatorChar = if (setType == "Normal") "W" else setType.take(1).uppercase()
                            Text(
                                indicatorChar,
                                color = Color(0xFFFFA726),
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                "$setNumber/${exercise.template.targetSets}",
                                color = Color.White,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }

                        // Reps Picker Column
                        Column(
                            modifier = Modifier
                                .width(64.dp)
                                .clickable { focusedCol = 1 }
                                .attachPickerRotary(
                                    pickerState = repsState,
                                    maxOptions = repsOptions.size,
                                    focusRequester = repsFocus,
                                    isFocused = focusedCol == 1,
                                ),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text("Reps", color = if (focusedCol == 1) Color(0xFF42A5F5) else Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
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
                                    color = if (isSelected && focusedCol == 1) Color(0xFF42A5F5) else Color.White,
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
                        if (setType != "Normal") tags.add(setType)
                        if (!selectedAccessory.isNullOrEmpty() && selectedAccessory != "None") tags.add(selectedAccessory!!)
                        
                        if (tags.isNotEmpty()) {
                            Text("[${tags.joinToString(" • ")}] ", color = Color(0xFF26C6DA), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }
                        Text("prev. $prevWeight kg × ${exercise.template.prevReps}", color = Color(0xFF757575), fontSize = 10.sp)
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
                            NavCircleButton(label = "‹", bg = Color(0xFF2C2C2E), size = 36) {
                                if (exerciseIndex > 0) {
                                    exerciseIndex -= 1
                                } else {
                                    navController.popBackStack()
                                }
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        NavCircleButton(label = "✓", bg = Color(0xFF1976D2), size = 44) {
                            showRpeDialog = true
                        }
                        Spacer(Modifier.width(12.dp))
                        Box(modifier = Modifier.offset(y = (-10).dp)) {
                            NavCircleButton(label = "›", bg = Color(0xFF2C2C2E), size = 36) {
                                if (exerciseIndex < s.exercises.size - 1) exerciseIndex += 1
                            }
                        }
                    }
                }
            }
            1 -> {
                // Page 1: Set Type Selection & Add/Remove Set Buttons
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text("Set Type", color = Color(0xFF9E9E9E), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))
                    setTypes.forEach { type ->
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 2.dp)
                                .background(if (setType == type) Color(0xFF1976D2) else Color(0xFF2C2C2E), shape = CircleShape)
                                .clickable { setType = type }
                                .padding(vertical = 6.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(type, color = Color.White, fontSize = 13.sp)
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .background(Color(0xFF2C2C2E), shape = CircleShape)
                                .clickable { viewModel.removeSetFromExercise(exerciseIndex) }
                                .padding(vertical = 6.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("- Remove", color = Color(0xFFFF5252), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .background(Color(0xFF1976D2), shape = CircleShape)
                                .clickable { viewModel.addSetToExercise(exerciseIndex) }
                                .padding(vertical = 6.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("+ Add Set", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
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
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(if (isSelected) Color(0xFF1976D2) else Color(0xFF1C1C1E), shape = CircleShape)
                                .clickable {
                                    selectedAccessory = if (acc == "None") null else acc
                                }
                                .padding(vertical = 10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(acc, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }
        }
    }

    if (showRpeDialog) {
        Dialog(showDialog = showRpeDialog, onDismissRequest = { showRpeDialog = false }) {
            val rpeState = rememberPickerState(initialNumberOfOptions = rpeOptions.size, initiallySelectedOption = 7)
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
                        text = "${rpeOptions[index]}",
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
                    NavCircleButton(label = "✓", bg = Color(0xFF4CAF50), size = 44) {
                        showRpeDialog = false
                        viewModel.logSet(
                            exerciseIndex = exerciseIndex,
                            weight = selectedWeight,
                            reps = selectedReps,
                            rpe = rpeOptions[rpeState.selectedOption],
                            setType = setType,
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
