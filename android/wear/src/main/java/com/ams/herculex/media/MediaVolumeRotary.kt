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

/**
 * Turns the rotating bezel / crown into music volume: clockwise raises it,
 * counter-clockwise lowers it. [onStep] receives +1 or -1 per detent.
 */
fun Modifier.mediaVolumeRotary(onStep: (Int) -> Unit): Modifier = composed {
    val focusRequester = remember { FocusRequester() }
    // Samsung watches deliver the same physical detent through both the pre-pass
    // and main-pass handlers; the originating uptime is identical, so key on it
    // to apply each detent once.
    var lastHandledUptime by remember { mutableLongStateOf(-1L) }

    fun handle(delta: Float, uptime: Long): Boolean {
        if (delta == 0f) return false
        if (uptime == lastHandledUptime) return true
        lastHandledUptime = uptime
        onStep(if (delta > 0f) 1 else -1)
        return true
    }

    LaunchedEffect(Unit) {
        // The focus target may not be attached on the first frame.
        repeat(20) {
            runCatching { focusRequester.requestFocus() }
                .onSuccess { return@LaunchedEffect }
            delay(100)
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
