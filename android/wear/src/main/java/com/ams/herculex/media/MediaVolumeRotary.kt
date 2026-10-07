package com.ams.herculex.media

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.focusable
import androidx.compose.ui.input.rotary.onPreRotaryScrollEvent
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.delay

import androidx.compose.runtime.mutableFloatStateOf

/**
 * Turns the rotating bezel / crown into music volume: clockwise raises it,
 * counter-clockwise lowers it. [onStep] receives +1 or -1 per detent.
 */
fun Modifier.mediaVolumeRotary(
    isFocused: Boolean = true,
    onStep: (Int) -> Unit,
): Modifier = composed {
    val focusRequester = remember { FocusRequester() }
    var lastHandledUptime by remember { mutableLongStateOf(-1L) }
    var accumulatedScroll by remember { mutableFloatStateOf(0f) }

    fun handle(deltaPixels: Float, uptime: Long): Boolean {
        if (deltaPixels == 0f) return false
        if (uptime == lastHandledUptime) return true
        lastHandledUptime = uptime

        val absDelta = kotlin.math.abs(deltaPixels)
        val sign = if (deltaPixels > 0f) 1 else -1

        val steps = if (absDelta < 5f) {
            accumulatedScroll = 0f
            sign
        } else {
            val newAccum = accumulatedScroll + deltaPixels
            val threshold = 18f
            if (kotlin.math.abs(newAccum) >= threshold) {
                val step = if (newAccum > 0) 1 else -1
                accumulatedScroll = if (absDelta >= threshold) 0f else newAccum - step * threshold
                step
            } else {
                accumulatedScroll = newAccum
                0
            }
        }

        if (steps != 0) {
            onStep(steps)
        }
        return true
    }

    LaunchedEffect(isFocused) {
        if (isFocused) {
            repeat(15) {
                delay(100)
                try { focusRequester.requestFocus() } catch (_: Exception) {}
            }
        }
    }

    this
        .onPreRotaryScrollEvent {
            handle(
                if (it.verticalScrollPixels != 0f) it.verticalScrollPixels else it.horizontalScrollPixels,
                it.uptimeMillis,
            )
        }
        .onRotaryScrollEvent {
            handle(
                if (it.verticalScrollPixels != 0f) it.verticalScrollPixels else it.horizontalScrollPixels,
                it.uptimeMillis,
            )
        }
        .focusRequester(focusRequester)
        .focusable()
}
