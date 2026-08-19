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
    focusRequester: FocusRequester = remember { FocusRequester() },
    isFocused: Boolean = true,
): Modifier {
    LaunchedEffect(isFocused) {
        if (isFocused) {
            repeat(15) {
                delay(100)
                try { focusRequester.requestFocus() } catch (_: Exception) {}
            }
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
    isFocused: Boolean = true,
): Modifier = attachRoutedPickerRotary(
    focusRequester = focusRequester,
    isFocused = isFocused,
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
    // Both the pre-pass and main-pass handlers below are registered so we still
    // catch the event regardless of which phase a given device/OEM delivers it
    // in — but on devices that dispatch through BOTH phases for the same
    // physical detent (observed on Samsung Galaxy Watch), that duplicate
    // delivery was processed twice, doubling (or worse, compounding with
    // multi-event bursts) the steps applied per bezel click. RotaryScrollEvent
    // carries the originating input event's uptimeMillis, which is identical
    // across both deliveries of the same physical event, so we key on it to
    // process each physical event exactly once.
    var lastHandledUptimeMillis by remember { mutableStateOf(-1L) }

    fun handle(event: androidx.compose.ui.input.rotary.RotaryScrollEvent): Boolean {
        val deltaPixels = if (event.verticalScrollPixels != 0f) event.verticalScrollPixels else event.horizontalScrollPixels
        if (deltaPixels == 0f) return false
        if (event.uptimeMillis == lastHandledUptimeMillis) return true
        lastHandledUptimeMillis = event.uptimeMillis

        val steps = calculateRotarySteps(deltaPixels, accumulatedScroll) { newAccum ->
            accumulatedScroll = newAccum
        }
        if (steps != 0) {
            scrollJob?.cancel()
            scrollJob = coroutineScope.launch {
                onStep(steps)
            }
        }
        return true
    }

    LaunchedEffect(isFocused) {
        if (isFocused) {
            repeat(20) {
                delay(100)
                try { focusRequester.requestFocus() } catch (_: Exception) {}
            }
        }
    }

    this
        .onPreRotaryScrollEvent { event -> handle(event) }
        .onRotaryScrollEvent { event -> handle(event) }
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
        // Pixel delta mode (e.g. ±24f, ±48f per scroll event). Some devices'
        // physical rotating bezel (notably Samsung Galaxy Watch) report a much
        // larger single-event delta than that (~90f+) for what is physically
        // one detent of rotation. Dividing that straight through the old 18f
        // threshold produced 4-5 steps per detent instead of 1 (reps jumping
        // by 5 on one bezel click). Capping each event to a single step fixes
        // that while still supporting fine-grained continuous input (crown /
        // touch bezel): a sustained rotation just fires this callback
        // repeatedly, each contributing its own single step.
        val newAccum = accumulated + deltaPixels
        val threshold = 18f
        if (kotlin.math.abs(newAccum) >= threshold) {
            val step = if (newAccum > 0) 1 else -1
            // A single event whose own delta already clears the threshold is
            // one physical notch reported as one big number (Samsung), not
            // several small ones accumulating toward it — drop the remainder
            // instead of carrying it forward, or the next notch would inherit
            // this one's leftover and eventually over-step too.
            updateAccumulated(if (absDelta >= threshold) 0f else newAccum - step * threshold)
            return step
        } else {
            updateAccumulated(newAccum)
            return 0
        }
    }
}
