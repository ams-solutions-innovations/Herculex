@file:OptIn(com.google.android.horologist.annotations.ExperimentalHorologistApi::class)

package com.ams.herculex.workout

import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.input.rotary.onPreRotaryScrollEvent
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.material.PickerState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

import com.google.android.horologist.compose.rotaryinput.rotaryWithScroll

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/// Attaches Samsung Galaxy Watch Classic physical bezel, Galaxy Watch touch bezel,
/// and Wear OS digital crown rotary scroll input to any ScalingLazyList.
@Composable
fun Modifier.attachRotaryScroll(
    state: ScalingLazyListState,
    focusRequester: FocusRequester = remember { FocusRequester() }
): Modifier {
    LaunchedEffect(Unit) {
        repeat(15) {
            delay(100)
            try { focusRequester.requestFocus() } catch (_: Exception) {}
        }
    }
    return this.rotaryWithScroll(scrollableState = state, focusRequester = focusRequester)
}

/// Attaches Samsung Galaxy Watch rotary bezel input to Pickers (Weight, Reps, RPE).
fun Modifier.attachPickerRotary(
    pickerState: PickerState,
    maxOptions: Int,
    focusRequester: FocusRequester,
    isFocused: Boolean = true
): Modifier = attachRoutedPickerRotary(
    focusRequester = focusRequester,
    isFocused = isFocused,
    onStep = { steps ->
        val newIdx = (pickerState.selectedOption + steps).coerceIn(0, maxOptions - 1)
        if (newIdx != pickerState.selectedOption) {
            pickerState.scrollToOption(newIdx)
        }
    },
)

/// Root-level rotary router for compact screens where child Picker focus can be
/// stolen by pagers or nested containers. This catches the hardware crown,
/// Samsung physical bezel, and Samsung touch bezel on the whole screen and
/// dispatches to whichever picker is currently highlighted.
fun Modifier.attachWorkoutSetPickerRotary(
    weightState: PickerState,
    weightOptionsCount: Int,
    repsState: PickerState,
    repsOptionsCount: Int,
    rotaryTarget: RotaryTarget,
    focusRequester: FocusRequester,
): Modifier = attachRoutedPickerRotary(
    focusRequester = focusRequester,
    isFocused = true,
    onStep = { steps ->
        val pickerState = if (rotaryTarget == RotaryTarget.WEIGHT) weightState else repsState
        val maxOptions = if (rotaryTarget == RotaryTarget.WEIGHT) weightOptionsCount else repsOptionsCount
        val newIdx = (pickerState.selectedOption + steps).coerceIn(0, maxOptions - 1)
        if (newIdx != pickerState.selectedOption) {
            pickerState.scrollToOption(newIdx)
        }
    },
)

private fun Modifier.attachRoutedPickerRotary(
    focusRequester: FocusRequester,
    isFocused: Boolean,
    onStep: suspend (Int) -> Unit,
): Modifier = composed {
    val coroutineScope = rememberCoroutineScope()
    var accumulatedScroll by remember { mutableFloatStateOf(0f) }
    var scrollJob by remember { mutableStateOf<Job?>(null) }

    LaunchedEffect(isFocused) {
        if (isFocused) {
            repeat(20) {
                delay(100)
                try { focusRequester.requestFocus() } catch (_: Exception) {}
            }
        }
    }

    this
        .onPreRotaryScrollEvent { event ->
            val deltaPixels = if (event.verticalScrollPixels != 0f) event.verticalScrollPixels else event.horizontalScrollPixels
            if (deltaPixels == 0f) return@onPreRotaryScrollEvent false

            val steps = calculateRotarySteps(deltaPixels, accumulatedScroll) { newAccum ->
                accumulatedScroll = newAccum
            }
            if (steps != 0) {
                scrollJob?.cancel()
                scrollJob = coroutineScope.launch {
                    onStep(steps)
                }
            }
            true
        }
        .onRotaryScrollEvent { event ->
            val deltaPixels = if (event.verticalScrollPixels != 0f) event.verticalScrollPixels else event.horizontalScrollPixels
            if (deltaPixels == 0f) return@onRotaryScrollEvent false

            val steps = calculateRotarySteps(deltaPixels, accumulatedScroll) { newAccum ->
                accumulatedScroll = newAccum
            }
            if (steps != 0) {
                scrollJob?.cancel()
                scrollJob = coroutineScope.launch {
                    onStep(steps)
                }
            }
            true
        }
        .focusRequester(focusRequester)
        .focusable()
}

private fun calculateRotarySteps(
    deltaPixels: Float,
    accumulated: Float,
    updateAccumulated: (Float) -> Unit,
): Int {
    val absDelta = kotlin.math.abs(deltaPixels)
    val sign = if (deltaPixels > 0f) 1 else -1

    if (absDelta < 5f) {
        // Notch count mode: one event here is one physical bezel detent,
        // regardless of the magnitude some devices report (e.g. ±1.0f vs ±2.0f).
        updateAccumulated(0f)
        return sign
    } else {
        // Pixel delta mode (e.g. ±24f, ±48f per scroll event)
        val newAccum = accumulated + deltaPixels
        val threshold = 18f
        if (kotlin.math.abs(newAccum) >= threshold) {
            val steps = (newAccum / threshold).toInt()
            updateAccumulated(newAccum - steps * threshold)
            return steps
        } else {
            updateAccumulated(newAccum)
            return 0
        }
    }
}
