package com.ams.herculex.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Icon

/**
 * "Sync with Phone" badge motion:
 *  - 0 → 85 % of [SyncAnimationState.durationMs]: ⟳ turns twice (ease-in-out), dipping to 0.88× mid-turn
 *  - at 85 %: ⟳ shrinks out, ✓ pops in (1.2× overshoot), a ripple ring expands and the badge flashes green
 *  - duration + 1 s: ✓ fades out and ⟳ settles back in; idle again at duration + 1.5 s
 */
enum class SyncPhase { Idle, Syncing, Done }

val SyncDoneColor = Color(0xFFA5D6A7)
private val SyncFlashColor = Color(0xFF1B4D3E)

/** Everything the badge needs to draw one moment of the animation. */
data class SyncFrame(
    val phase: SyncPhase,
    val spinRotation: Float = 0f,
    val spinScale: Float = 1f,
    val spinAlpha: Float = 1f,
    val checkScale: Float = 1f,
    val checkAlpha: Float = 0f,
    val ringScale: Float = 1f,
    val ringAlpha: Float = 0f,
    /** 0 = badge colour, 1 = full green flash. */
    val flash: Float = 0f,
)

private val SpinEasing = CubicBezierEasing(0.6f, 0f, 0.2f, 1f)
private val PopEasing = CubicBezierEasing(0.2f, 0.8f, 0.3f, 1f)
private val EaseIn = CubicBezierEasing(0.42f, 0f, 1f, 1f)
private val EaseOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)

private const val SPIN_OUT_MS = 180f
private const val SUCCESS_DELAY_MS = 90f
private const val CHECK_IN_MS = 420f
private const val RING_MS = 700f
private const val FLASH_MS = 1100f
private const val HOLD_MS = 1000f
private const val CHECK_OUT_MS = 200f
private const val SPIN_IN_DELAY_MS = 120f
private const val SPIN_IN_MS = 280f
private const val SETTLE_MS = 500f

fun syncTotalMs(durationMs: Int): Float = durationMs + HOLD_MS + SETTLE_MS

private fun progress(t: Float, start: Float, length: Float, easing: Easing = LinearEasing): Float =
    easing.transform(((t - start) / length).coerceIn(0f, 1f))

private fun lerp(a: Float, b: Float, f: Float) = a + (b - a) * f

/** Linear keyframes a → b at [mid] → c, like a three-stop WAAPI animation. */
private fun keyframes(a: Float, b: Float, c: Float, p: Float, mid: Float) =
    if (p < mid) lerp(a, b, p / mid) else lerp(b, c, (p - mid) / (1f - mid))

/** The frame [t] ms after the tap; [durationMs] matches the sync request window. */
fun syncFrameAt(t: Float, durationMs: Int): SyncFrame {
    val spinEnd = durationMs * 0.85f
    val restore = durationMs + HOLD_MS
    if (t < spinEnd) {
        val p = progress(t, 0f, spinEnd, SpinEasing)
        return SyncFrame(
            phase = SyncPhase.Syncing,
            spinRotation = 720f * p,
            spinScale = keyframes(1f, 0.88f, 1f, p, 0.5f),
        )
    }
    val success = spinEnd + SUCCESS_DELAY_MS
    val ringP = progress(t, success, RING_MS, EaseOut)
    val ringOn = t >= success && ringP < 1f
    val flashP = progress(t, success, FLASH_MS)
    val flash = if (t < success || flashP >= 1f) 0f else keyframes(0f, 1f, 0f, flashP, 0.25f)

    if (t < restore) {
        val out = progress(t, spinEnd, SPIN_OUT_MS, EaseIn)
        val pop = progress(t, success, CHECK_IN_MS, PopEasing)
        return SyncFrame(
            phase = SyncPhase.Done,
            spinScale = lerp(1f, 0.5f, out),
            spinAlpha = 1f - out,
            checkScale = keyframes(0.4f, 1.2f, 1f, pop, 0.6f),
            checkAlpha = if (t < success) 0f else keyframes(0f, 1f, 1f, pop, 0.6f),
            ringAlpha = if (ringOn) 0.85f * (1f - ringP) else 0f,
            ringScale = if (ringOn) 1f + 0.65f * ringP else 1f,
            flash = flash,
        )
    }
    val checkOut = progress(t, restore, CHECK_OUT_MS)
    val spinIn = progress(t, restore + SPIN_IN_DELAY_MS, SPIN_IN_MS, PopEasing)
    return SyncFrame(
        phase = SyncPhase.Done,
        spinScale = lerp(0.5f, 1f, spinIn),
        spinAlpha = spinIn,
        checkScale = lerp(1f, 0.7f, checkOut),
        checkAlpha = 1f - checkOut,
    )
}

class SyncAnimationState(val durationMs: Int) {
    private val clock = Animatable(0f)
    private var running by mutableStateOf(false)

    val frame: SyncFrame
        get() = if (running) syncFrameAt(clock.value, durationMs) else SyncFrame(SyncPhase.Idle)

    val isIdle: Boolean get() = !running

    /** Plays the whole sequence; returns once the badge is idle again. */
    suspend fun play() {
        if (running) return
        running = true
        try {
            clock.snapTo(0f)
            val total = syncTotalMs(durationMs)
            clock.animateTo(total, tween(total.toInt(), easing = LinearEasing))
        } finally {
            running = false
        }
    }
}

@Composable
fun rememberSyncAnimationState(durationMs: Int = 2000): SyncAnimationState =
    remember(durationMs) { SyncAnimationState(durationMs) }

/** Badge content for [OneUiPill]'s `iconComposable`: fills the badge circle. */
@Composable
fun SyncBadge(
    state: SyncAnimationState,
    badgeColor: Color,
    iconSize: Dp = 22.dp,
    contentColor: Color = Color.White,
) {
    val f = state.frame
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(lerp(badgeColor, SyncFlashColor, f.flash), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    alpha = f.ringAlpha
                    scaleX = f.ringScale
                    scaleY = f.ringScale
                }
                .border(2.dp, SyncDoneColor, CircleShape),
        )
        Icon(
            imageVector = HxIcons.Sync,
            contentDescription = null,
            tint = contentColor,
            modifier = Modifier
                .size(iconSize)
                .graphicsLayer {
                    alpha = f.spinAlpha
                    rotationZ = f.spinRotation
                    scaleX = f.spinScale
                    scaleY = f.spinScale
                },
        )
        Icon(
            imageVector = HxIcons.Check,
            contentDescription = null,
            tint = SyncDoneColor,
            modifier = Modifier
                .size(iconSize)
                .graphicsLayer {
                    alpha = f.checkAlpha
                    scaleX = f.checkScale
                    scaleY = f.checkScale
                },
        )
    }
}
