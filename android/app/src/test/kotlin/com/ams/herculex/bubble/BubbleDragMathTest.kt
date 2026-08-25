package com.ams.herculex.bubble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BubbleDragMathTest {

    // ── isTap ────────────────────────────────────────────────────────────────

    @Test
    fun `a press that never moves is a tap`() {
        assertTrue(BubbleDragMath.isTap(dx = 0f, dy = 0f, touchSlop = 24))
    }

    @Test
    fun `movement exactly at the slop is still a tap`() {
        assertTrue(BubbleDragMath.isTap(dx = 24f, dy = 0f, touchSlop = 24))
    }

    @Test
    fun `movement past the slop on one axis is a drag`() {
        assertFalse(BubbleDragMath.isTap(dx = 25f, dy = 0f, touchSlop = 24))
    }

    @Test
    fun `a diagonal wobble within the slop on each axis is still a drag`() {
        // 20,20 is under the slop per axis but 28.3 away in a straight line.
        // Measuring per axis here would let the bubble slide while the tap
        // handler still fired on release.
        assertFalse(BubbleDragMath.isTap(dx = 20f, dy = 20f, touchSlop = 24))
    }

    // ── snapTargetX ──────────────────────────────────────────────────────────

    @Test
    fun `a bubble on the left half snaps to the left margin`() {
        val x = BubbleDragMath.snapTargetX(
            currentX = 100,
            bubbleWidth = 168,
            screenWidth = 1080,
            margin = 24,
        )
        assertEquals(24, x)
    }

    @Test
    fun `a bubble on the right half snaps to the right margin`() {
        val x = BubbleDragMath.snapTargetX(
            currentX = 800,
            bubbleWidth = 168,
            screenWidth = 1080,
            margin = 24,
        )
        assertEquals(1080 - 168 - 24, x)
    }

    @Test
    fun `a bubble centred exactly on the midline snaps left`() {
        val bubbleWidth = 168
        val screenWidth = 1080
        val x = BubbleDragMath.snapTargetX(
            currentX = screenWidth / 2 - bubbleWidth / 2,
            bubbleWidth = bubbleWidth,
            screenWidth = screenWidth,
            margin = 24,
        )
        assertEquals(24, x)
    }

    @Test
    fun `a bubble wider than the screen falls back to the left margin`() {
        val x = BubbleDragMath.snapTargetX(
            currentX = 0,
            bubbleWidth = 400,
            screenWidth = 300,
            margin = 24,
        )
        assertEquals(24, x)
    }

    // ── clampY ───────────────────────────────────────────────────────────────

    @Test
    fun `a y inside the safe area is left alone`() {
        val y = BubbleDragMath.clampY(
            y = 500,
            bubbleHeight = 168,
            screenHeight = 2400,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(500, y)
    }

    @Test
    fun `dragging above the status bar clamps to the top inset`() {
        val y = BubbleDragMath.clampY(
            y = -300,
            bubbleHeight = 168,
            screenHeight = 2400,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(80, y)
    }

    @Test
    fun `dragging below the navigation bar keeps the bubble fully visible`() {
        val y = BubbleDragMath.clampY(
            y = 9000,
            bubbleHeight = 168,
            screenHeight = 2400,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(2400 - 120 - 168, y)
    }

    @Test
    fun `a screen too short for the bubble pins it to the top inset`() {
        val y = BubbleDragMath.clampY(
            y = 50,
            bubbleHeight = 500,
            screenHeight = 400,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(80, y)
    }

    // ── centeredX ────────────────────────────────────────────────────────────

    @Test
    fun `centres a view with an even width difference exactly`() {
        assertEquals(150, BubbleDragMath.centeredX(width = 180, screenWidth = 480))
    }

    @Test
    fun `centres a view with an odd width difference by truncating`() {
        // (1081 - 168) / 2 = 456.5 -> truncates to 456, never rounds up past centre.
        assertEquals(456, BubbleDragMath.centeredX(width = 168, screenWidth = 1081))
    }

    // ── restingTopY ──────────────────────────────────────────────────────────

    @Test
    fun `the resting margin wins when the status bar inset is shorter`() {
        assertEquals(120, BubbleDragMath.restingTopY(topInset = 80, restingMargin = 120))
    }

    @Test
    fun `the status bar inset wins when it is taller than the resting margin`() {
        // A tall cutout/status bar must never be covered by the bubble.
        assertEquals(140, BubbleDragMath.restingTopY(topInset = 140, restingMargin = 120))
    }

    @Test
    fun `an equal inset and margin agree`() {
        assertEquals(100, BubbleDragMath.restingTopY(topInset = 100, restingMargin = 100))
    }

    // ── restingBottomY ───────────────────────────────────────────────────────

    @Test
    fun `the resting margin wins when the navigation bar inset is shorter`() {
        // screenHeight 2400, bottomInset 80, restingMargin 120, bubbleHeight 168 -> 2400 - 120 - 168 = 2112
        assertEquals(2112, BubbleDragMath.restingBottomY(bottomInset = 80, restingMargin = 120, bubbleHeight = 168, screenHeight = 2400))
    }

    @Test
    fun `the navigation bar inset wins when it is taller than the resting margin`() {
        // screenHeight 2400, bottomInset 140, restingMargin 120, bubbleHeight 168 -> 2400 - 140 - 168 = 2092
        assertEquals(2092, BubbleDragMath.restingBottomY(bottomInset = 140, restingMargin = 120, bubbleHeight = 168, screenHeight = 2400))
    }

    // ── isBottomHalf ─────────────────────────────────────────────────────────

    @Test
    fun `detects when bubble is in upper half of screen`() {
        assertFalse(BubbleDragMath.isBottomHalf(y = 500, bubbleHeight = 168, screenHeight = 2400))
    }

    @Test
    fun `detects when bubble is in lower half of screen`() {
        assertTrue(BubbleDragMath.isBottomHalf(y = 1500, bubbleHeight = 168, screenHeight = 2400))
    }

    // ── snapTarget (flick and corner snapping) ───────────────────────────────

    @Test
    fun `flicking strongly to top-left snaps to top-left corner`() {
        val (targetX, targetY) = BubbleDragMath.snapTarget(
            currentX = 400,
            currentY = 1000,
            velocityX = -1200f,
            velocityY = -1500f,
            bubbleWidth = 168,
            bubbleHeight = 168,
            screenWidth = 1080,
            screenHeight = 2400,
            margin = 24,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(24, targetX)
        assertEquals(80 + 24, targetY)
    }

    @Test
    fun `flicking strongly to bottom-right snaps to bottom-right corner`() {
        val (targetX, targetY) = BubbleDragMath.snapTarget(
            currentX = 400,
            currentY = 1000,
            velocityX = 1200f,
            velocityY = 1500f,
            bubbleWidth = 168,
            bubbleHeight = 168,
            screenWidth = 1080,
            screenHeight = 2400,
            margin = 24,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(1080 - 168 - 24, targetX)
        assertEquals(2400 - 120 - 168 - 24, targetY)
    }

    @Test
    fun `flicking strongly to bottom-left snaps to bottom-left corner`() {
        val (targetX, targetY) = BubbleDragMath.snapTarget(
            currentX = 600,
            currentY = 1000,
            velocityX = -1200f,
            velocityY = 1500f,
            bubbleWidth = 168,
            bubbleHeight = 168,
            screenWidth = 1080,
            screenHeight = 2400,
            margin = 24,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(24, targetX)
        assertEquals(2400 - 120 - 168 - 24, targetY)
    }

    @Test
    fun `flicking strongly to top-right snaps to top-right corner`() {
        val (targetX, targetY) = BubbleDragMath.snapTarget(
            currentX = 200,
            currentY = 1000,
            velocityX = 1200f,
            velocityY = -1500f,
            bubbleWidth = 168,
            bubbleHeight = 168,
            screenWidth = 1080,
            screenHeight = 2400,
            margin = 24,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(1080 - 168 - 24, targetX)
        assertEquals(80 + 24, targetY)
    }

    @Test
    fun `releasing in middle side edge without flick snaps to edge at current y`() {
        val (targetX, targetY) = BubbleDragMath.snapTarget(
            currentX = 100,
            currentY = 1100,
            velocityX = 0f,
            velocityY = 0f,
            bubbleWidth = 168,
            bubbleHeight = 168,
            screenWidth = 1080,
            screenHeight = 2400,
            margin = 24,
            topInset = 80,
            bottomInset = 120,
        )
        assertEquals(24, targetX)
        assertEquals(1100, targetY)
    }

    // ── lerp ─────────────────────────────────────────────────────────────────

    @Test
    fun `lerp at fraction zero is the start value`() {
        assertEquals(10, BubbleDragMath.lerp(start = 10, end = 200, fraction = 0f))
    }

    @Test
    fun `lerp at fraction one is the end value`() {
        assertEquals(200, BubbleDragMath.lerp(start = 10, end = 200, fraction = 1f))
    }

    @Test
    fun `lerp at the midpoint of an even delta is exact`() {
        assertEquals(105, BubbleDragMath.lerp(start = 10, end = 200, fraction = 0.5f))
    }

    @Test
    fun `lerp runs in reverse for a close animation`() {
        assertEquals(105, BubbleDragMath.lerp(start = 200, end = 10, fraction = 0.5f))
        assertEquals(10, BubbleDragMath.lerp(start = 200, end = 10, fraction = 1f))
    }

    // ── isOverDismissTarget ──────────────────────────────────────────────────

    @Test
    fun `a bubble sitting on the target is captured`() {
        val captured = BubbleDragMath.isOverDismissTarget(
            bubbleX = 540 - 84,
            bubbleY = 2100 - 84,
            bubbleWidth = 168,
            bubbleHeight = 168,
            dismissCentreX = 540,
            dismissCentreY = 2100,
            captureRadius = 240,
        )
        assertTrue(captured)
    }

    @Test
    fun `a bubble just inside the capture radius is captured`() {
        val captured = BubbleDragMath.isOverDismissTarget(
            bubbleX = 540 - 84 + 200,
            bubbleY = 2100 - 84,
            bubbleWidth = 168,
            bubbleHeight = 168,
            dismissCentreX = 540,
            dismissCentreY = 2100,
            captureRadius = 240,
        )
        assertTrue(captured)
    }

    @Test
    fun `a bubble parked far from the target is not captured`() {
        val captured = BubbleDragMath.isOverDismissTarget(
            bubbleX = 24,
            bubbleY = 300,
            bubbleWidth = 168,
            bubbleHeight = 168,
            dismissCentreX = 540,
            dismissCentreY = 2100,
            captureRadius = 240,
        )
        assertFalse(captured)
    }
}
