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
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.material.PickerState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

import com.google.android.horologist.compose.rotaryinput.rotaryWithScroll

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
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
): Modifier = composed {
    val coroutineScope = rememberCoroutineScope()
    var accumulatedScroll by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(isFocused) {
        if (isFocused) {
            repeat(15) {
                delay(100)
                try { focusRequester.requestFocus() } catch (_: Exception) {}
            }
        }
    }

    this
        .focusRequester(focusRequester)
        .focusable()
        .onRotaryScrollEvent { event ->
            if (!isFocused) return@onRotaryScrollEvent false
            val deltaPixels = if (event.verticalScrollPixels != 0f) event.verticalScrollPixels else event.horizontalScrollPixels
            if (deltaPixels == 0f) return@onRotaryScrollEvent false

            accumulatedScroll += deltaPixels
            val threshold = 15f
            if (kotlin.math.abs(accumulatedScroll) >= threshold) {
                val steps = (accumulatedScroll / threshold).toInt()
                accumulatedScroll -= steps * threshold
                val newIdx = (pickerState.selectedOption + steps).coerceIn(0, maxOptions - 1)
                if (newIdx != pickerState.selectedOption) {
                    coroutineScope.launch {
                        pickerState.scrollToOption(newIdx)
                    }
                }
            }
            true
        }
}
