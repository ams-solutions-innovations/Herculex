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
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.PagerSnapDistance
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val weightOptions = (0..400).map { it * 0.5 }
private val repsOptions = (1..50).toList()
private val durationOptions = ((5..300 step 5) + (330..1800 step 30) + (1860..3600 step 60)).toList()
private val distanceOptions = ((0..2000 step 25) + (2050..10000 step 50) + (10100..50000 step 100)).toList()
private val rpeOptions = (2..20).map { it * 0.5 }
private data class WatchSetType(val id: String, val label: String)
enum class RotaryTarget { WEIGHT, REPS, TIME, DISTANCE }

private fun formatDuration(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    return if (m > 0) "%d:%02d".format(m, s) else "%ds".format(s)
}

private val setTypes = listOf(
    WatchSetType("standard", "Normal"),
    WatchSetType("warmup", "Warm up"),
    WatchSetType("drop", "Drop set"),
    WatchSetType("forced", "Forced Reps"),
    WatchSetType("cheat", "Cheat Reps"),
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
    val elapsed by viewModel.elapsedSeconds.collectAsState()

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

    LaunchedEffect(s.currentExerciseIndex) {
        if (s.currentExerciseIndex in s.exercises.indices) {
            exerciseIndex = s.currentExerciseIndex
        }
    }

    val exercise = s.exercises.getOrNull(exerciseIndex) ?: return
    val setNumber = exercise.completedSets + 1
    val plannedOrCurrentSet = remember(exerciseIndex, exercise.sets) {
        exercise.sets.firstOrNull { !it.completed } ?: exercise.sets.lastOrNull()
    }
    val currentSetIdx = if (exercise.sets.isNotEmpty()) {
        val openIdx = exercise.sets.indexOfFirst { !it.completed }
        if (openIdx >= 0) openIdx else (exercise.sets.size - 1)
    } else 0

    val currentPlannedSet = exercise.template.plannedSets.getOrNull(currentSetIdx)
        ?: exercise.template.plannedSets.firstOrNull { it.setIndex == plannedOrCurrentSet?.setIndex }
        ?: exercise.template.plannedSets.firstOrNull()

    var setType by remember(exerciseIndex, plannedOrCurrentSet?.setType, plannedOrCurrentSet?.isWarmup) {
        val plannedType = if (plannedOrCurrentSet?.isWarmup == true) {
            "warmup"
        } else {
            plannedOrCurrentSet?.setType ?: "standard"
        }
        mutableStateOf(setTypes.firstOrNull { it.id == plannedType } ?: setTypes.first())
    }

    LaunchedEffect(exerciseIndex, plannedOrCurrentSet?.setType, plannedOrCurrentSet?.isWarmup) {
        val plannedType = if (plannedOrCurrentSet?.isWarmup == true) {
            "warmup"
        } else {
            plannedOrCurrentSet?.setType ?: "standard"
        }
        setType = setTypes.firstOrNull { it.id == plannedType } ?: setTypes.first()
    }

    var selectedAccessory by remember { mutableStateOf<String?>(null) }
    var showRpeDialog by remember { mutableStateOf(false) }
    var isEditingActivation by remember(exerciseIndex, plannedOrCurrentSet?.wireId) { mutableStateOf(false) }

    val isBodyweight = exercise.template.isBodyweightOnly()
    val isTimeBased = exercise.template.isTimeBased()
    val showsDistanceInWeightSlot = exercise.template.showsDistanceInWeightSlot()
    val showsDistanceInValueSlot = exercise.template.showsDistanceInValueSlot()

    val initWeightIdx = remember(exerciseIndex, currentSetIdx, plannedOrCurrentSet?.weight) {
        val initialWeight = plannedOrCurrentSet?.weight?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetWeightKg?.takeIf { it > 0 }
            ?: exercise.template.prevWeight
        weightOptions.indexOfFirst { it >= initialWeight }.takeIf { it >= 0 } ?: 0
    }
    val initRepsIdx = remember(exerciseIndex, currentSetIdx, plannedOrCurrentSet?.reps) {
        val initialReps = plannedOrCurrentSet?.reps?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetReps?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetRepsMin?.takeIf { it > 0 }
            ?: exercise.template.prevReps.takeIf { it > 0 }
            ?: 10
        (initialReps - 1).coerceIn(0, repsOptions.size - 1)
    }
    val initDurationIdx = remember(exerciseIndex, currentSetIdx, plannedOrCurrentSet?.durationSeconds) {
        val initSec = plannedOrCurrentSet?.durationSeconds?.takeIf { it > 0 }
            ?: currentPlannedSet?.durationSeconds?.takeIf { it > 0 }
            ?: 30
        val idx = durationOptions.indexOfFirst { it >= initSec }
        if (idx >= 0) idx else (durationOptions.indexOfFirst { it >= 30 }.takeIf { it >= 0 } ?: 0)
    }
    val initDistanceIdx = remember(exerciseIndex, currentSetIdx, plannedOrCurrentSet?.distanceMeters) {
        val initialDistance = plannedOrCurrentSet?.distanceMeters?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetDistanceMeters?.takeIf { it > 0 }
            ?: 0.0
        distanceOptions.indexOfFirst { it >= initialDistance }.takeIf { it >= 0 } ?: 0
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
    val durationState = rememberPickerState(
        initialNumberOfOptions = durationOptions.size,
        initiallySelectedOption = initDurationIdx,
        repeatItems = false,
    )
    val distanceState = rememberPickerState(
        initialNumberOfOptions = distanceOptions.size,
        initiallySelectedOption = initDistanceIdx,
        repeatItems = false,
    )

    var isTimerRunning by remember(exerciseIndex, plannedOrCurrentSet?.wireId) { mutableStateOf(false) }
    var timerElapsedSeconds by remember(exerciseIndex, plannedOrCurrentSet?.wireId) { mutableIntStateOf(0) }
    val coroutineScope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    LaunchedEffect(isTimerRunning) {
        if (isTimerRunning) {
            while (isTimerRunning) {
                delay(1000L)
                timerElapsedSeconds += 1
                val optIdx = durationOptions.indexOfFirst { it >= timerElapsedSeconds }
                if (optIdx >= 0 && optIdx != durationState.selectedOption) {
                    durationState.scrollToOption(optIdx)
                }
            }
        }
    }

    LaunchedEffect(exerciseIndex, currentSetIdx, plannedOrCurrentSet?.weight, plannedOrCurrentSet?.reps, plannedOrCurrentSet?.durationSeconds, plannedOrCurrentSet?.distanceMeters) {
        val targetWeight = plannedOrCurrentSet?.weight?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetWeightKg?.takeIf { it > 0 }
            ?: exercise.template.prevWeight
        val wIdx = weightOptions.indexOfFirst { it >= targetWeight }.takeIf { it >= 0 } ?: 0
        if (wIdx != weightState.selectedOption && wIdx in 0 until weightOptions.size) {
            weightState.scrollToOption(wIdx)
        }

        val targetReps = plannedOrCurrentSet?.reps?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetReps?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetRepsMin?.takeIf { it > 0 }
            ?: exercise.template.prevReps.takeIf { it > 0 }
            ?: 10
        val rIdx = (targetReps - 1).coerceIn(0, repsOptions.size - 1)
        if (rIdx != repsState.selectedOption && rIdx in 0 until repsOptions.size) {
            repsState.scrollToOption(rIdx)
        }

        val targetDur = plannedOrCurrentSet?.durationSeconds?.takeIf { it > 0 }
            ?: currentPlannedSet?.durationSeconds?.takeIf { it > 0 }
            ?: 30
        val dIdx = durationOptions.indexOfFirst { it >= targetDur }.takeIf { it >= 0 } ?: 0
        if (dIdx != durationState.selectedOption && dIdx in 0 until durationOptions.size) {
            durationState.scrollToOption(dIdx)
        }

        val targetDistance = plannedOrCurrentSet?.distanceMeters?.takeIf { it > 0 }
            ?: currentPlannedSet?.targetDistanceMeters?.takeIf { it > 0 }
            ?: 0.0
        val distIdx = distanceOptions.indexOfFirst { it >= targetDistance }.takeIf { it >= 0 } ?: 0
        if (distIdx != distanceState.selectedOption && distIdx in 0 until distanceOptions.size) {
            distanceState.scrollToOption(distIdx)
        }
    }

    var rotaryTarget by remember(exerciseIndex, isBodyweight, isTimeBased) {
        mutableStateOf(
            when {
                isTimeBased -> RotaryTarget.TIME
                isBodyweight -> RotaryTarget.REPS
                // Plain `distance` (no weight, no time) — weight_distance
                // (which also has showsDistanceInValueSlot) keeps the WEIGHT
                // default below since it has a real weight to focus first.
                showsDistanceInValueSlot && !exercise.template.hasRealWeightSlot() -> RotaryTarget.DISTANCE
                else -> RotaryTarget.WEIGHT
            }
        )
    }
    val setPickerFocus = remember { FocusRequester() }

    val selectedWeight = weightOptions.getOrNull(weightState.selectedOption) ?: 0.0
    val selectedReps = repsOptions.getOrNull(repsState.selectedOption) ?: 1
    val selectedDuration = durationOptions.getOrNull(durationState.selectedOption) ?: 30
    val selectedDistance = distanceOptions.getOrNull(distanceState.selectedOption) ?: 0
    val prevWeight = "%.1f".format(exercise.template.prevWeight)

    // Debounced outbound broadcast when user changes values on the watch pickers
    LaunchedEffect(
        exerciseIndex,
        currentSetIdx,
        selectedWeight,
        selectedReps,
        selectedDuration,
        selectedDistance,
        setType.id,
    ) {
        delay(300L)
        if (plannedOrCurrentSet != null && !plannedOrCurrentSet.completed) {
            viewModel.updateActiveSetValues(
                exerciseIndex = exerciseIndex,
                setIndex = currentSetIdx,
                weight = selectedWeight,
                reps = selectedReps,
                durationSeconds = if (isTimeBased) selectedDuration else null,
                distanceMeters = if (showsDistanceInWeightSlot || showsDistanceInValueSlot) selectedDistance.toDouble() else null,
                setType = setType.id,
                isWarmup = setType.id == "warmup",
            )
        }
    }

    val horizontalPagerState = rememberPagerState(pageCount = { 3 })
    // Vertical pager on page 0: 0 = glance (swipe down), 1 = set logger (default), 2 = media controls (swipe up).
    val verticalPagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })

    LaunchedEffect(horizontalPagerState.currentPage, verticalPagerState.currentPage) {
        if (horizontalPagerState.currentPage == 0 && verticalPagerState.currentPage == 1) {
            runCatching { setPickerFocus.requestFocus() }
        }
    }

    // NestedScrollConnection to intercept swipe-right on page 0 and trigger popBackStack()
    val nestedScrollConnection = remember {
        var accumulatedX = 0f
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if ((horizontalPagerState.currentPage == 0 || verticalPagerState.currentPage != 1) && available.x > 0 && kotlin.math.abs(available.y) < available.x) {
                    if (source == NestedScrollSource.Drag) {
                        accumulatedX += available.x
                        if (accumulatedX > 80f) {
                            accumulatedX = -10000f // prevent multiple pops
                            navController.popBackStack()
                        }
                    }
                    return available
                } else {
                    accumulatedX = 0f
                }
                return Offset.Zero
            }
        }
    }

    HorizontalPager(
        state = horizontalPagerState,
        userScrollEnabled = (verticalPagerState.currentPage == 1),
        flingBehavior = PagerDefaults.flingBehavior(
            state = horizontalPagerState,
            pagerSnapDistance = PagerSnapDistance.atMost(1),
        ),
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .nestedScroll(nestedScrollConnection),
    ) { page ->
        when (page) {
            0 -> {
                VerticalPager(
                    state = verticalPagerState,
                    flingBehavior = PagerDefaults.flingBehavior(
                        state = verticalPagerState,
                        pagerSnapDistance = PagerSnapDistance.atMost(1),
                    ),
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                ) { verticalPage ->
                    when (verticalPage) {
                        0 -> {
                            WorkoutGlanceScreen(
                                session = s,
                                heartRate = heartRate,
                                elapsedSeconds = elapsed,
                            )
                        }
                        1 -> {
                            val currentSetIdx = if (s.currentSetIndex in exercise.sets.indices) s.currentSetIndex else (exercise.sets.indexOf(plannedOrCurrentSet).takeIf { it >= 0 } ?: 0)
                            val activeExtraSet = remember(exercise.sets, currentSetIdx, plannedOrCurrentSet) {
                                val set = exercise.sets.getOrNull(currentSetIdx) ?: plannedOrCurrentSet
                                if (set != null && set.completed && (set.setType == "myo_reps" || set.setType == "forced" || set.setType == "cheat")) set else null
                            }
                            val isExtraRepsMode = (setType.id == "myo_reps" || setType.id == "forced" || setType.id == "cheat") && activeExtraSet != null && !isEditingActivation

                            if (activeExtraSet != null && isExtraRepsMode) {
                                ExtraRepsLogger(
                                    exercise = exercise,
                                    exerciseIndex = exerciseIndex,
                                    setIndex = currentSetIdx,
                                    loggedSet = activeExtraSet,
                                    viewModel = viewModel,
                                    isPageFocused = horizontalPagerState.currentPage == 0 && verticalPagerState.currentPage == 1,
                                    onEditActivation = { isEditingActivation = true },
                                    onFinishSet = {
                                        viewModel.finishExtraSet(exerciseIndex, currentSetIdx)
                                        val updatedSession = viewModel.session.value
                                        if (updatedSession != null) {
                                            val lastEx = updatedSession.exercises.last()
                                            if (updatedSession.currentExerciseIndex == updatedSession.exercises.size - 1 && lastEx.completedSets >= lastEx.template.targetSets) {
                                                navController.popBackStack()
                                            }
                                        }
                                    },
                                )
                            } else {
                                // Page 0: Set Logger Screen
                                Column(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .attachWorkoutSetPickerRotary(
                                            weightState = weightState,
                                            weightOptionsCount = weightOptions.size,
                                            repsState = repsState,
                                            repsOptionsCount = repsOptions.size,
                                            timeState = durationState,
                                            timeOptionsCount = durationOptions.size,
                                            distanceState = distanceState,
                                            distanceOptionsCount = distanceOptions.size,
                                            rotaryTarget = rotaryTarget,
                                            focusRequester = setPickerFocus,
                                            isFocused = horizontalPagerState.currentPage == 0 && verticalPagerState.currentPage == 1,
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

                                    val mainNameFontSize = when {
                                        mainName.length > 28 -> 11.sp
                                        mainName.length > 20 -> 12.5.sp
                                        mainName.length > 14 -> 13.5.sp
                                        else -> 15.sp
                                    }

                                    Text(
                                        text = mainName,
                                        color = Color.White,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = mainNameFontSize,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                        textAlign = TextAlign.Center,
                                        modifier = Modifier.padding(horizontal = 10.dp),
                                    )
                                    if (subName.isNotEmpty()) {
                                        Text(
                                            text = subName,
                                            color = Color(0xFFB0BEC5),
                                            fontWeight = FontWeight.Medium,
                                            fontSize = 10.5.sp,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            textAlign = TextAlign.Center,
                                            modifier = Modifier.padding(horizontal = 10.dp),
                                        )
                                    }
                                    
                                    Spacer(Modifier.height(4.dp))
                                    
                                    // Pickers (Weight / Time / Reps) and Set Control in between
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .weight(1f),
                                        horizontalArrangement = Arrangement.SpaceEvenly,
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        // Weight/Distance Picker Column — hidden for bodyweight-only sets
                                        // and for the plain `distance` metric (nothing belongs here; its
                                        // one field renders in the value column below instead).
                                        if (!isBodyweight && (exercise.template.hasRealWeightSlot() || showsDistanceInWeightSlot)) {
                                            Column(
                                                modifier = Modifier
                                                    .width(64.dp)
                                                    .clickable {
                                                        rotaryTarget = if (showsDistanceInWeightSlot) RotaryTarget.DISTANCE else RotaryTarget.WEIGHT
                                                        runCatching { setPickerFocus.requestFocus() }
                                                    },
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                            ) {
                                                if (showsDistanceInWeightSlot) {
                                                    Text(
                                                        "m",
                                                        color = if (rotaryTarget == RotaryTarget.DISTANCE) Color(0xFF42A5F5) else Color.White,
                                                        fontSize = 12.sp,
                                                        fontWeight = FontWeight.Bold,
                                                    )
                                                    Picker(
                                                        state = distanceState,
                                                        contentDescription = "Distance",
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .weight(1f),
                                                    ) { index ->
                                                        val isSelected = index == distanceState.selectedOption
                                                        Text(
                                                            text = "${distanceOptions[index]}",
                                                            color = if (isSelected && rotaryTarget == RotaryTarget.DISTANCE) Color(0xFF42A5F5) else Color.White,
                                                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                                            fontSize = if (isSelected) 19.sp else 13.sp,
                                                        )
                                                    }
                                                } else {
                                                    Text(
                                                        "Kg",
                                                        color = if (rotaryTarget == RotaryTarget.WEIGHT) Color(0xFF42A5F5) else Color.White,
                                                        fontSize = 12.sp,
                                                        fontWeight = FontWeight.Bold,
                                                    )
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
                                            }
                                        }

                                        // Middle Column: Set Indicator (W/D/F/CR/MY if warmup/drop/forced/cheat/myo, 1/3 below)
                                        Column(
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                            verticalArrangement = Arrangement.Center,
                                            modifier = Modifier.padding(horizontal = 4.dp),
                                        ) {
                                            if (isBodyweight) {
                                                Text(
                                                    "BW",
                                                    color = Color(0xFF42A5F5),
                                                    fontSize = 11.sp,
                                                    fontWeight = FontWeight.Bold,
                                                )
                                                Spacer(Modifier.height(1.dp))
                                            }
                                            val indicatorChar = when (setType.id) {
                                                "warmup" -> "W"
                                                "drop" -> "D"
                                                "forced" -> "F"
                                                "cheat" -> "CR"
                                                "rest_pause" -> "RP"
                                                "myo_reps" -> "MY"
                                                else -> if (setType.id != "standard") setType.label.take(1).uppercase() else ""
                                            }
                                            if (indicatorChar.isNotEmpty()) {
                                                Text(
                                                    indicatorChar,
                                                    color = when (setType.id) {
                                                        "myo_reps" -> Color(0xFF81C784)
                                                        "forced" -> Color(0xFFE53935)
                                                        "cheat" -> Color(0xFFFF7043)
                                                        else -> Color(0xFFFFA726)
                                                    },
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

                                        // Value Column: Time (if isTimeBased) or Reps (if not isTimeBased)
                                        if (isTimeBased) {
                                            Column(
                                                modifier = Modifier
                                                    .width(if (isBodyweight) 84.dp else 64.dp)
                                                    .clickable {
                                                        rotaryTarget = RotaryTarget.TIME
                                                        runCatching { setPickerFocus.requestFocus() }
                                                    },
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                            ) {
                                                Text(
                                                    "Time",
                                                    color = if (rotaryTarget == RotaryTarget.TIME) Color(0xFF26A69A) else Color.White,
                                                    fontSize = 12.sp,
                                                    fontWeight = FontWeight.Bold,
                                                )
                                                Picker(
                                                    state = durationState,
                                                    contentDescription = "Duration",
                                                    modifier = Modifier
                                                        .fillMaxWidth()
                                                        .weight(1f),
                                                ) { index ->
                                                    val isSelected = index == durationState.selectedOption
                                                    Text(
                                                        text = formatDuration(durationOptions[index]),
                                                        color = if (isSelected && rotaryTarget == RotaryTarget.TIME) Color(0xFF26A69A) else Color.White,
                                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                                        fontSize = if (isSelected) 19.sp else 13.sp,
                                                    )
                                                }
                                            }
                                        } else if (showsDistanceInValueSlot) {
                                            Column(
                                                modifier = Modifier
                                                    .width(if (isBodyweight) 84.dp else 64.dp)
                                                    .clickable {
                                                        rotaryTarget = RotaryTarget.DISTANCE
                                                        runCatching { setPickerFocus.requestFocus() }
                                                    },
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                            ) {
                                                Text(
                                                    "m",
                                                    color = if (rotaryTarget == RotaryTarget.DISTANCE) Color(0xFF42A5F5) else Color.White,
                                                    fontSize = 12.sp,
                                                    fontWeight = FontWeight.Bold,
                                                )
                                                Picker(
                                                    state = distanceState,
                                                    contentDescription = "Distance",
                                                    modifier = Modifier
                                                        .fillMaxWidth()
                                                        .weight(1f),
                                                ) { index ->
                                                    val isSelected = index == distanceState.selectedOption
                                                    Text(
                                                        text = "${distanceOptions[index]}",
                                                        color = if (isSelected && rotaryTarget == RotaryTarget.DISTANCE) Color(0xFF42A5F5) else Color.White,
                                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                                        fontSize = if (isSelected) 19.sp else 13.sp,
                                                    )
                                                }
                                            }
                                        } else {
                                            Column(
                                                modifier = Modifier
                                                    .width(if (isBodyweight) 84.dp else 64.dp)
                                                    .clickable {
                                                        rotaryTarget = RotaryTarget.REPS
                                                        runCatching { setPickerFocus.requestFocus() }
                                                    },
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                            ) {
                                                Text(
                                                    "Reps",
                                                    color = if (rotaryTarget == RotaryTarget.REPS) Color(0xFF42A5F5) else Color.White,
                                                    fontSize = 12.sp,
                                                    fontWeight = FontWeight.Bold,
                                                )
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
                                    }
                                    
                                    // Start / Stop Timer button for time-based exercises
                                    if (isTimeBased) {
                                        val buttonBg = if (isTimerRunning) Color(0xFFC62828) else Color(0xFF00695C)
                                        val buttonIcon = if (isTimerRunning) "⏹" else "▶"
                                        val buttonLabel = if (isTimerRunning) "STOP (${formatDuration(timerElapsedSeconds)})" else "START TIMER"
                                        Box(
                                            modifier = Modifier
                                                .fillMaxWidth(0.85f)
                                                .background(buttonBg, shape = RoundedCornerShape(14.dp))
                                                .clickable {
                                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                    if (!isTimerRunning) {
                                                        timerElapsedSeconds = 0
                                                        isTimerRunning = true
                                                    } else {
                                                        isTimerRunning = false
                                                        val optIdx = durationOptions.indexOfFirst { it >= timerElapsedSeconds }
                                                        if (optIdx >= 0) {
                                                            coroutineScope.launch { durationState.scrollToOption(optIdx) }
                                                        }
                                                    }
                                                }
                                                .padding(vertical = 5.dp, horizontal = 8.dp),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Row(
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(5.dp),
                                            ) {
                                                Text(buttonIcon, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                                Text(buttonLabel, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                    }

                                    Spacer(Modifier.height(4.dp))

                                    // Set Type & Accessory Indicator & Prev Perf
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.Center,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        val tags = mutableListOf<String>()
                                        val isSuperset = exercise.supersetGroup != null || exercise.template.supersetGroup != null
                                        if (isSuperset) {
                                            val sGroup = exercise.supersetGroup ?: exercise.template.supersetGroup
                                            val gCount = s.exercises.count { (it.supersetGroup ?: it.template.supersetGroup) == sGroup }
                                            tags.add(if (gCount == 2) "SUPERSET" else if (gCount == 3) "TRI-SET" else "GIANT SET")
                                        }
                                        if (isBodyweight) tags.add("BW")
                                        if (setType.id != "standard") {
                                            tags.add(if (setType.id == "myo_reps") "Myo (Activation)" else setType.label)
                                        }
                                        if (!selectedAccessory.isNullOrEmpty() && selectedAccessory != "None") tags.add(selectedAccessory!!)
                                        
                                        if (tags.isNotEmpty()) {
                                            Text("[${tags.joinToString(" / ")}] ", color = Color(0xFF26C6DA), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                        }
                                        val prevDistanceText = exercise.template.plannedSets
                                            .firstOrNull { (it.targetDistanceMeters ?: 0.0) > 0 }
                                            ?.targetDistanceMeters
                                            ?.let { "%.0f".format(it) } ?: "0"
                                        val hintText = exercise.template.performanceHint
                                            ?: when {
                                                isTimeBased && isBodyweight -> "prev. ${exercise.template.plannedSets.firstOrNull()?.durationSeconds?.let { formatDuration(it) } ?: "30s"}"
                                                showsDistanceInWeightSlot -> "prev. ${prevDistanceText}m x ${exercise.template.plannedSets.firstOrNull()?.durationSeconds?.let { formatDuration(it) } ?: "30s"}"
                                                isTimeBased -> "prev. $prevWeight kg x ${exercise.template.plannedSets.firstOrNull()?.durationSeconds?.let { formatDuration(it) } ?: "30s"}"
                                                isBodyweight -> if (exercise.template.prevReps > 0) "prev. BW x ${exercise.template.prevReps}" else null
                                                showsDistanceInValueSlot && exercise.template.hasRealWeightSlot() -> "prev. $prevWeight kg x ${prevDistanceText}m"
                                                showsDistanceInValueSlot -> "prev. ${prevDistanceText}m"
                                                exercise.template.prevWeight > 0 || exercise.template.prevReps > 0 -> "prev. $prevWeight kg x ${exercise.template.prevReps}"
                                                else -> null
                                            }
                                        if (hintText != null) {
                                            Text(hintText, color = Color(0xFF757575), fontSize = 10.sp)
                                        }
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
                        }
                        2 -> {
                            MediaControlsScreen()
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
                        .attachRotaryScroll(
                            state = setTypeListState,
                            isFocused = horizontalPagerState.currentPage == 1,
                        ),
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
                        .attachRotaryScroll(
                            state = accListState,
                            isFocused = horizontalPagerState.currentPage == 2,
                        ),
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
                        isEditingActivation = false
                        val chosenDuration = if (isTimeBased) {
                            if (timerElapsedSeconds > 0) timerElapsedSeconds else selectedDuration
                        } else null
                        viewModel.logSet(
                            exerciseIndex = exerciseIndex,
                            weight = if (isBodyweight || showsDistanceInWeightSlot) 0.0 else selectedWeight,
                            reps = if (isTimeBased || showsDistanceInValueSlot) 0 else selectedReps,
                            durationSeconds = chosenDuration,
                            distanceMeters = if (showsDistanceInWeightSlot || showsDistanceInValueSlot) selectedDistance.toDouble() else null,
                            rpe = rpeOptions[rpeState.selectedOption],
                            setType = setType.id,
                            accessory = selectedAccessory,
                        )
                        if (setType.id != "myo_reps") {
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
}

@Composable
private fun ExtraRepsLogger(
    exercise: ActiveExercise,
    exerciseIndex: Int,
    setIndex: Int,
    loggedSet: LoggedSet,
    viewModel: WorkoutViewModel,
    isPageFocused: Boolean,
    onEditActivation: () -> Unit,
    onFinishSet: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val setType = loggedSet.setType
    val isMyo = setType == "myo_reps"
    val isForced = setType == "forced"
    val isCheat = setType == "cheat"

    val extraList = remember(loggedSet.setTypeMetaJson) {
        if (isMyo) loggedSet.getMiniSets() else loggedSet.getExtraReps()
    }
    var repCount by remember { mutableIntStateOf(extraList.lastOrNull() ?: if (isMyo) 3 else 2) }
    var restSecondsRemaining by remember { mutableIntStateOf(if (isMyo) 15 else 45) }
    var isRestRunning by remember { mutableStateOf(false) }

    LaunchedEffect(isRestRunning, restSecondsRemaining) {
        if (isRestRunning && restSecondsRemaining > 0) {
            delay(1_000)
            restSecondsRemaining -= 1
            if (restSecondsRemaining == 0) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        }
    }

    val listState = rememberScalingLazyListState()

    val badgeTitle = when {
        isMyo -> "MYO REPS"
        isForced -> "FORCED REPS"
        isCheat -> "CHEAT REPS"
        else -> "EXTRA REPS"
    }
    val badgeColor = when {
        isMyo -> Color(0xFF81C784)
        isForced -> Color(0xFFE53935)
        isCheat -> Color(0xFFFF7043)
        else -> Color(0xFF26C6DA)
    }
    val chipLabel = when {
        isMyo -> "mini"
        isForced -> "forced"
        isCheat -> "cheat"
        else -> "extra"
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(
                state = listState,
                isFocused = isPageFocused,
            ),
        autoCentering = null,
        contentPadding = PaddingValues(top = 16.dp, bottom = 28.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            val rawName = exercise.template.name
            val mainName = if (rawName.contains("(")) rawName.substringBefore("(").trim() else rawName
            val mainNameFontSize = when {
                mainName.length > 28 -> 11.sp
                mainName.length > 20 -> 12.sp
                mainName.length > 14 -> 13.sp
                else -> 14.sp
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            ) {
                Text(
                    text = mainName,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = mainNameFontSize,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = badgeTitle,
                    color = badgeColor,
                    fontWeight = FontWeight.ExtraBold,
                    fontSize = 11.sp,
                    letterSpacing = 0.5.sp,
                )
            }
        }

        item {
            OneUiPill(
                title = "Clean: %.1f kg × %d".format(loggedSet.weight, loggedSet.reps),
                subtitle = "Tap to edit full ROM set",
                icon = "⚡",
                style = OneUiPillStyle.SlateNavy,
                onClick = onEditActivation,
            )
        }

        if (extraList.isNotEmpty()) {
            item {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                ) {
                    val totalReps = loggedSet.reps + extraList.sum()
                    Text(
                        text = "Total: ${loggedSet.reps} + ${extraList.sum()} = $totalReps reps",
                        color = badgeColor,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(4.dp))
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        extraList.forEach { count ->
                            Box(
                                modifier = Modifier
                                    .background(badgeColor.copy(alpha = 0.8f), shape = RoundedCornerShape(8.dp))
                                    .padding(horizontal = 8.dp, vertical = 3.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text = "+$count $chipLabel",
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        }
                    }
                }
            }
        }

        item {
            val timerText = if (restSecondsRemaining > 0) "Rest: ${restSecondsRemaining}s" else "⚡ GO!"
            val timerColor = if (restSecondsRemaining > 0) Color(0xFFFFA726) else Color(0xFF81C784)
            
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1E222D), shape = RoundedCornerShape(14.dp))
                    .clickable {
                        restSecondsRemaining = if (isMyo) 15 else 45
                        isRestRunning = true
                    }
                    .padding(vertical = 6.dp, horizontal = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("⏱", fontSize = 13.sp)
                    Text(text = timerText, color = timerColor, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                NavCircleButton(label = "-", bg = Color(0xFF2C2C2E), size = 32) {
                    if (repCount > 1) repCount -= 1
                }
                Spacer(Modifier.width(10.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = "$repCount", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Text(text = chipLabel, color = Color(0xFF90A4AE), fontSize = 9.sp)
                }
                Spacer(Modifier.width(10.dp))
                NavCircleButton(label = "+", bg = Color(0xFF2C2C2E), size = 32) {
                    if (repCount < 20) repCount += 1
                }
            }
        }

        item {
            OneUiPill(
                title = when {
                    isMyo -> "+ Mini Set ($repCount reps)"
                    isForced -> "+ Forced ($repCount reps)"
                    isCheat -> "+ Cheat ($repCount reps)"
                    else -> "+ Extra ($repCount reps)"
                },
                icon = "➕",
                style = OneUiPillStyle.AccentBlue,
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    if (isMyo) {
                        viewModel.addMiniSet(exerciseIndex, setIndex, repCount)
                    } else {
                        viewModel.addExtraReps(exerciseIndex, setIndex, repCount)
                    }
                    restSecondsRemaining = if (isMyo) 15 else 45
                    isRestRunning = true
                },
            )
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (extraList.isNotEmpty()) {
                    Box(modifier = Modifier.weight(1f)) {
                        OneUiPill(
                            title = "- Undo",
                            style = OneUiPillStyle.DangerTransparent,
                            onClick = {
                                if (isMyo) {
                                    viewModel.removeLastMiniSet(exerciseIndex, setIndex)
                                } else {
                                    viewModel.removeLastExtraReps(exerciseIndex, setIndex)
                                }
                            },
                        )
                    }
                }
                Box(modifier = Modifier.weight(if (extraList.isNotEmpty()) 1.2f else 1f)) {
                    OneUiPill(
                        title = "✓ Finish Set",
                        icon = "✓",
                        style = OneUiPillStyle.EmeraldGreen,
                        onClick = onFinishSet,
                    )
                }
            }
        }
    }
}

@Composable
private fun NavCircleButton(label: String, bg: Color, size: Int = 40, onClick: () -> Unit) {
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
