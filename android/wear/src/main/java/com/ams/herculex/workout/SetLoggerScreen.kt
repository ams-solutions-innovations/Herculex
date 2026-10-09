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
import androidx.compose.runtime.mutableLongStateOf
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
import com.ams.herculex.ui.HxIcons
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.ui.OneUiPillTrailingIcon
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

private val accessoryIcons = mapOf(
    "None" to HxIcons.None,
    "Belt" to HxIcons.Belt,
    "Straps" to HxIcons.Straps,
    "Bands" to HxIcons.Bands,
    "Chains" to HxIcons.Chains,
)

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
    var rowedMeters by remember(exerciseIndex, plannedOrCurrentSet?.wireId) { mutableIntStateOf(0) }
    val coroutineScope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    LaunchedEffect(isTimerRunning) {
        if (isTimerRunning) {
            while (isTimerRunning) {
                delay(1000L)
                timerElapsedSeconds += 1
            }
        }
    }

    var isProgrammaticSync by remember { mutableStateOf(false) }
    var userInteractedWeight by remember(exerciseIndex, currentSetIdx) { mutableStateOf(false) }
    var userInteractedReps by remember(exerciseIndex, currentSetIdx) { mutableStateOf(false) }
    var userInteractedDuration by remember(exerciseIndex, currentSetIdx) { mutableStateOf(false) }
    var userInteractedDistance by remember(exerciseIndex, currentSetIdx) { mutableStateOf(false) }

    LaunchedEffect(weightState.isScrollInProgress) {
        if (weightState.isScrollInProgress && !isProgrammaticSync) {
            userInteractedWeight = true
        }
    }
    LaunchedEffect(repsState.isScrollInProgress) {
        if (repsState.isScrollInProgress && !isProgrammaticSync) {
            userInteractedReps = true
        }
    }
    LaunchedEffect(durationState.isScrollInProgress) {
        if (durationState.isScrollInProgress && !isProgrammaticSync) {
            userInteractedDuration = true
        }
    }
    LaunchedEffect(distanceState.isScrollInProgress) {
        if (distanceState.isScrollInProgress && !isProgrammaticSync) {
            userInteractedDistance = true
        }
    }

    LaunchedEffect(exerciseIndex, currentSetIdx, plannedOrCurrentSet?.weight, plannedOrCurrentSet?.reps, plannedOrCurrentSet?.durationSeconds, plannedOrCurrentSet?.distanceMeters) {
        isProgrammaticSync = true
        try {
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
        } finally {
            delay(50L)
            isProgrammaticSync = false
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

    val hasUserInteraction = userInteractedWeight || userInteractedReps || userInteractedDuration || userInteractedDistance

    // Debounced outbound broadcast ONLY when user explicitly changes values on the watch pickers (rotary or touch drag)
    LaunchedEffect(
        hasUserInteraction,
        userInteractedWeight,
        userInteractedReps,
        userInteractedDuration,
        userInteractedDistance,
        selectedWeight,
        selectedReps,
        selectedDuration,
        selectedDistance,
    ) {
        if (!hasUserInteraction || isProgrammaticSync) return@LaunchedEffect
        delay(300L)
        if (plannedOrCurrentSet != null && !plannedOrCurrentSet.completed) {
            viewModel.updateActiveSetValues(
                exerciseIndex = exerciseIndex,
                setIndex = currentSetIdx,
                weight = if (userInteractedWeight) selectedWeight else plannedOrCurrentSet.weight,
                reps = if (userInteractedReps) selectedReps else plannedOrCurrentSet.reps,
                durationSeconds = if (isTimeBased && userInteractedDuration) selectedDuration else plannedOrCurrentSet.durationSeconds,
                distanceMeters = if ((showsDistanceInWeightSlot || showsDistanceInValueSlot) && userInteractedDistance) selectedDistance.toDouble() else plannedOrCurrentSet.distanceMeters,
                setType = setType.id,
                isWarmup = setType.id == "warmup",
            )
            userInteractedWeight = false
            userInteractedReps = false
            userInteractedDuration = false
            userInteractedDistance = false
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
                                ExtraRepsScreen(
                                    exercise = exercise,
                                    exerciseIndex = exerciseIndex,
                                    setIndex = currentSetIdx,
                                    loggedSet = activeExtraSet,
                                    viewModel = viewModel,
                                    onEditActivation = { isEditingActivation = true },
                                    onFinishSet = {
                                        viewModel.finishExtraSet(exerciseIndex, currentSetIdx)
                                        val updatedSession = viewModel.session.value
                                        if (updatedSession != null) {
                                            val lastEx = updatedSession.exercises.last()
                                            val allDone = lastEx.sets.isNotEmpty() && lastEx.sets.all { it.completed }
                                            if (updatedSession.currentExerciseIndex == updatedSession.exercises.size - 1 && allDone) {
                                                navController.popBackStack()
                                            }
                                        }
                                    },
                                )
                            } else {
                                // Page 0: Set Logger Screen
                                val accent = if (isTimeBased) (if (showsDistanceInWeightSlot) HxBlue else HxTeal) else HxBlue
                                val sGroup = exercise.supersetGroup ?: exercise.template.supersetGroup
                                val groupMembers = if (sGroup != null) {
                                    s.exercises.withIndex().filter { (it.value.supersetGroup ?: it.value.template.supersetGroup) == sGroup }
                                } else emptyList()
                                val groupPos = groupMembers.indexOfFirst { it.index == exerciseIndex } + 1
                                val thenName = if (groupMembers.size > 1 && groupPos > 0) {
                                    groupMembers[groupPos % groupMembers.size].value.template.name.substringBefore("(").trim()
                                } else null
                                val hasNext = exerciseIndex < s.exercises.size - 1
                                val warmDone = exercise.sets.count { it.completed && it.isWarmup }
                                val workDone = exercise.sets.count { it.completed && !it.isWarmup }
                                val nextIsWarmup = setType.id == "warmup"
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
                                val goPrev = {
                                    if (exerciseIndex > 0) {
                                        exerciseIndex -= 1
                                        viewModel.selectExerciseInSession(exerciseIndex)
                                    } else {
                                        navController.popBackStack()
                                    }
                                }
                                val goNext = {
                                    if (hasNext) {
                                        exerciseIndex += 1
                                        viewModel.selectExerciseInSession(exerciseIndex)
                                    }
                                }
                                Box(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .domainGlow(
                                            accent.copy(alpha = if (isTimeBased) 0.24f else 0.22f),
                                            (if (groupMembers.isNotEmpty()) HxCyan else Color(0xFF1E44AA)).copy(alpha = 0.16f),
                                        )
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
                                            onUserStep = { target ->
                                                when (target) {
                                                    RotaryTarget.WEIGHT -> userInteractedWeight = true
                                                    RotaryTarget.REPS -> userInteractedReps = true
                                                    RotaryTarget.TIME -> userInteractedDuration = true
                                                    RotaryTarget.DISTANCE -> userInteractedDistance = true
                                                }
                                            },
                                        ),
                                ) {
                                if (isTimeBased) {
                                    val numberIdx = exercise.sets.indexOfFirst { !it.completed }
                                        .let { if (it >= 0) it else exercise.sets.size }
                                    val timerRunning = isTimerRunning
                                    TimedSetBody(
                                        name = exercise.template.name.substringBefore("(").trim(),
                                        setLabel = exercise.setNumberLabel(numberIdx, asWarmup = nextIsWarmup).substringBefore("/"),
                                        dotsTotal = exercise.workingSetTotal,
                                        dotsDone = workDone,
                                        isBodyweight = isBodyweight,
                                        isRow = showsDistanceInWeightSlot,
                                        targetSeconds = selectedDuration,
                                        elapsedSeconds = timerElapsedSeconds,
                                        running = timerRunning,
                                        targetMeters = selectedDistance,
                                        rowedMeters = rowedMeters,
                                        hint = hintText,
                                        hasNext = hasNext,
                                        onTargetStep = { d ->
                                            val idx = (durationState.selectedOption + d).coerceIn(0, durationOptions.size - 1)
                                            userInteractedDuration = true
                                            coroutineScope.launch { durationState.scrollToOption(idx) }
                                        },
                                        onMetersStep = { d ->
                                            if (timerRunning || timerElapsedSeconds > 0) {
                                                rowedMeters = (rowedMeters + d * 100).coerceAtLeast(0)
                                            } else {
                                                val target = (selectedDistance + d * 100).coerceAtLeast(0)
                                                val idx = distanceOptions.indexOfFirst { it >= target }
                                                    .let { if (it >= 0) it else distanceOptions.lastIndex }
                                                userInteractedDistance = true
                                                coroutineScope.launch { distanceState.scrollToOption(idx) }
                                            }
                                        },
                                        onPrimary = {
                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                            when {
                                                timerRunning -> isTimerRunning = false
                                                timerElapsedSeconds > 0 -> showRpeDialog = true
                                                else -> {
                                                    rowedMeters = 0
                                                    isTimerRunning = true
                                                }
                                            }
                                        },
                                        onPrev = { goPrev() },
                                        onNext = { goNext() },
                                    )
                                } else {
                                SetBezel(
                                    warmupTotal = exercise.warmupSetTotal,
                                    workingTotal = exercise.workingSetTotal,
                                    completed = if (nextIsWarmup) warmDone else exercise.warmupSetTotal + workDone,
                                    accent = accent,
                                )
                                Column(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .padding(top = 30.dp, bottom = 4.dp, start = 16.dp, end = 16.dp),
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

                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.Center,
                                        modifier = Modifier.padding(horizontal = 8.dp),
                                    ) {
                                        Text(
                                            text = mainName,
                                            color = Color.White,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = mainNameFontSize,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            textAlign = TextAlign.Center,
                                        )
                                    }
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
                                            if (setType.id != "standard") {
                                                SetTypeBadge(setType.id, size = 26)
                                                Spacer(Modifier.height(2.dp))
                                            }
                                            // Next set to log: the first open one, or a new
                                            // one past the end. Warmups count separately.
                                            val numberIdx = exercise.sets.indexOfFirst { !it.completed }
                                                .let { if (it >= 0) it else exercise.sets.size }
                                            Text(
                                                exercise.setNumberLabel(numberIdx, asWarmup = setType.id == "warmup"),
                                                color = Color.White,
                                                fontSize = 14.sp,
                                                fontWeight = FontWeight.Bold,
                                            )
                                            RestCountdownLabel()
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
                                    
                                    Spacer(Modifier.height(4.dp))

                                    // Chips (superset position, set type, accessory) + previous result
                                    Row(
                                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        if (groupMembers.size > 1) {
                                            HxChip(
                                                (if (groupMembers.size == 2) "SUPERSET" else if (groupMembers.size == 3) "TRI-SET" else "GIANT SET") +
                                                    " $groupPos/${groupMembers.size}",
                                                HxCyan,
                                            )
                                        }
                                        if (setType.id != "standard" && setType.id != "warmup") {
                                            HxChip(
                                                (if (setType.id == "myo_reps") "Myo (Activation)" else setType.label).uppercase(),
                                                setTypeStyle(setType.id).color,
                                            )
                                        }
                                        if (!selectedAccessory.isNullOrEmpty() && selectedAccessory != "None") {
                                            HxChip(selectedAccessory!!.uppercase(), HxCyan)
                                        }
                                    }
                                    if (hintText != null) {
                                        Text(hintText, color = HxMuted, fontSize = 9.sp, maxLines = 1)
                                    }
                                    if (thenName != null) {
                                        Text("› Then · $thenName", color = HxCyan, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 24.dp))
                                    }
                                    Spacer(Modifier.height(4.dp))
                                    
                                    // Bottom nav: ‹ prev exercise · OK · › next exercise
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(bottom = 6.dp),
                                        horizontalArrangement = Arrangement.Center,
                                        verticalAlignment = Alignment.Bottom,
                                    ) {
                                        Box(modifier = Modifier.offset(y = (-10).dp)) {
                                            NavCircleButton(label = "‹", bg = Color(0xFF2C2C2E), size = 34) { goPrev() }
                                        }
                                        Spacer(Modifier.width(10.dp))
                                        NavCircleButton(
                                            label = "OK",
                                            bg = OneUiPillStyle.RoyalBlue.containerColor,
                                            size = 40,
                                        ) {
                                            showRpeDialog = true
                                        }
                                        Spacer(Modifier.width(10.dp))
                                        Box(modifier = Modifier.offset(y = (-10).dp)) {
                                            NavCircleButton(label = "›", bg = Color(0xFF2C2C2E), size = 34, enabled = hasNext) { goNext() }
                                        }
                                    }
                                }
                                }
                                }
                            }
                        }
                        2 -> {
                            MediaControlsScreen(isFocused = horizontalPagerState.currentPage == 0 && verticalPagerState.currentPage == 2)
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
                            iconComposable = { SetTypeBadge(type.id, selected = isSel, size = 38) },
                            rightContent = if (isSel) {
                                { OneUiPillTrailingIcon(HxIcons.Check, OneUiPillStyle.RoyalBlue) }
                            } else null,
                            style = if (isSel) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy,
                            onClick = {
                                if (setType.id != type.id) {
                                    setType = type
                                    if (plannedOrCurrentSet != null && !plannedOrCurrentSet.completed) {
                                        viewModel.updateActiveSetValues(
                                            exerciseIndex = exerciseIndex,
                                            setIndex = currentSetIdx,
                                            weight = plannedOrCurrentSet.weight,
                                            reps = plannedOrCurrentSet.reps,
                                            durationSeconds = plannedOrCurrentSet.durationSeconds,
                                            distanceMeters = plannedOrCurrentSet.distanceMeters,
                                            setType = type.id,
                                            isWarmup = type.id == "warmup",
                                        )
                                    }
                                }
                            },
                        )
                    }
                    item {
                        Spacer(Modifier.height(6.dp))
                        OneUiPill(
                            title = "Add Set",
                            icon = "+",
                            style = OneUiPillStyle.AccentBlue,
                            onClick = { viewModel.addSetToExercise(exerciseIndex) },
                        )
                    }
                    item {
                        OneUiPill(
                            title = "Remove Set",
                            icon = "✕",
                            style = OneUiPillStyle.DangerTransparent,
                            onClick = { viewModel.removeSetFromExercise(exerciseIndex) },
                        )
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
                        val accStyle = if (isSelected) OneUiPillStyle.RoyalBlue else OneUiPillStyle.SlateNavy
                        OneUiPill(
                            title = acc,
                            iconVector = accessoryIcons.getValue(acc),
                            style = accStyle,
                            rightContent = if (isSelected) {
                                { OneUiPillTrailingIcon(HxIcons.Check, accStyle) }
                            } else null,
                            onClick = {
                                selectedAccessory = if (acc == "None") null else acc
                            },
                        )
                    }
                    if (selectedAccessory != null) {
                        item {
                            Spacer(Modifier.height(4.dp))
                            OneUiPill(
                                title = "Remove Accessory",
                                icon = "✕",
                                style = OneUiPillStyle.DangerTransparent,
                                onClick = { selectedAccessory = null },
                            )
                        }
                    }
                }
            }
        }
    }

    if (showRpeDialog) {
        Dialog(showDialog = showRpeDialog, onDismissRequest = { showRpeDialog = false }) {
            val rpeState = rememberPickerState(initialNumberOfOptions = rpeOptions.size, initiallySelectedOption = 14)
            val rpeFocus = remember { FocusRequester() }
            
            val rpeNow = rpeOptions.getOrNull(rpeState.selectedOption) ?: 8.0
            val rpeHeat = Math.pow(((rpeNow - 2.0) / 8.0).coerceIn(0.0, 1.0), 1.2).toFloat()
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
                    .background(Color(0xFFC81414).copy(alpha = 0.22f * rpeHeat))
                    .domainGlow(Color(0xFFFF3B30).copy(alpha = 0.85f * rpeHeat), Color(0xFFFF5A3C).copy(alpha = 0.4f * rpeHeat))
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
                            distanceMeters = when {
                                showsDistanceInWeightSlot && rowedMeters > 0 -> rowedMeters.toDouble()
                                showsDistanceInWeightSlot || showsDistanceInValueSlot -> selectedDistance.toDouble()
                                else -> null
                            },
                            rpe = rpeOptions[rpeState.selectedOption],
                            setType = setType.id,
                            accessory = selectedAccessory,
                        )
                        if (setType.id != "myo_reps") {
                            val updatedSession = viewModel.session.value
                            if (updatedSession != null) {
                                val lastEx = updatedSession.exercises.last()
                                val allDone = lastEx.sets.isNotEmpty() && lastEx.sets.all { it.completed }
                                if (updatedSession.currentExerciseIndex == updatedSession.exercises.size - 1 && allDone) {
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
internal fun NavCircleButton(
    label: String,
    bg: Color,
    size: Int = 40,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .background(
                if (enabled) bg else bg.copy(alpha = 0.35f),
                shape = CircleShape,
            )
            .then(
                if (enabled) Modifier.clickable(onClick = onClick) else Modifier
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (enabled) Color.White else Color.White.copy(alpha = 0.35f),
            fontSize = (size / 2.4).sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

/// Rest left before the next set, small and amber under the set number —
/// only while the phone's rest timer (Workout settings) is running.
@Composable
private fun RestCountdownLabel() {
    val timer by RestTimerStore.timer.collectAsState()
    val active = timer?.takeIf { it.showOnWatch } ?: return
    var now by remember(active.endsAtEpochMs) { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(active.endsAtEpochMs) {
        while (now < active.endsAtEpochMs) {
            delay(1000L - (System.currentTimeMillis() % 1000L))
            now = System.currentTimeMillis()
        }
    }
    val remaining = active.remainingSeconds(now)
    if (remaining <= 0) return
    Text(
        "%d:%02d".format(remaining / 60, remaining % 60),
        color = Color(0xFFFFA726),
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
    )
}
