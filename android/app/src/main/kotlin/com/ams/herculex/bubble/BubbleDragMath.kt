package com.ams.herculex.bubble

import kotlin.math.hypot

/**
 * Geometry for the Workout Bubble chat head.
 *
 * Deliberately free of every Android type so it can be unit-tested with plain
 * JUnit — [WorkoutBubbleController] keeps the `WindowManager` plumbing and
 * calls in here for every number it needs.
 */
object BubbleDragMath {

    /**
     * A press that never travelled further than the platform touch slop is a
     * tap, not a drag. Measured as a straight-line distance rather than per
     * axis, so a diagonal wobble of `slop` on both axes still counts as a drag.
     */
    fun isTap(dx: Float, dy: Float, touchSlop: Int): Boolean =
        hypot(dx, dy) <= touchSlop

    /**
     * The x the bubble should settle at after being released: whichever screen
     * edge its centre is nearest, inset by [margin].
     *
     * A bubble dragged exactly to the middle snaps left, which is arbitrary but
     * has to be decided somewhere.
     */
    fun snapTargetX(
        currentX: Int,
        bubbleWidth: Int,
        screenWidth: Int,
        margin: Int,
    ): Int {
        val centreX = currentX + bubbleWidth / 2f
        val rightEdge = screenWidth - bubbleWidth - margin
        // A bubble wider than the screen has no meaningful edge to pick.
        if (rightEdge <= margin) return margin
        return if (centreX <= screenWidth / 2f) margin else rightEdge
    }

    /**
     * Keeps the bubble fully on screen while dragging, so it can never be
     * parked under the status bar or below the navigation bar where it would
     * be unreachable.
     */
    fun clampY(
        y: Int,
        bubbleHeight: Int,
        screenHeight: Int,
        topInset: Int,
        bottomInset: Int,
    ): Int {
        val min = topInset
        val max = screenHeight - bottomInset - bubbleHeight
        if (max <= min) return min
        return y.coerceIn(min, max)
    }

    /**
     * The x that centres a view of [width] horizontally on a screen of
     * [screenWidth]. Shared by the bubble's top-centre resting spot when open
     * and the popup's centred position beneath it.
     */
    fun centeredX(width: Int, screenWidth: Int): Int = (screenWidth - width) / 2

    /**
     * The y the bubble rests at once opened: [restingMargin] below the top of
     * the screen, but never under the status bar on a device where that inset
     * is taller than the margin itself.
     */
    fun restingTopY(topInset: Int, restingMargin: Int): Int = maxOf(topInset, restingMargin)

    /**
     * The y the bubble rests at once opened at the bottom: [restingMargin] above
     * the bottom of the screen, accounting for the navigation bar inset.
     */
    fun restingBottomY(
        bottomInset: Int,
        restingMargin: Int,
        bubbleHeight: Int,
        screenHeight: Int,
    ): Int {
        val bottomOffset = maxOf(bottomInset, restingMargin)
        return screenHeight - bottomOffset - bubbleHeight
    }

    /**
     * Whether the bubble's center is currently on the bottom half of the screen.
     */
    fun isBottomHalf(y: Int, bubbleHeight: Int, screenHeight: Int): Boolean {
        val centerY = y + bubbleHeight / 2f
        return centerY > screenHeight / 2f
    }

    /**
     * Calculates the snap target (X, Y) when releasing or flicking the bubble.
     * Snaps horizontally to the left or right edge.
     * Snaps vertically to top/bottom corners if flicked or close to the top/bottom edges,
     * or docks along the screen side at the momentum-projected clamped Y.
     */
    fun snapTarget(
        currentX: Int,
        currentY: Int,
        velocityX: Float,
        velocityY: Float,
        bubbleWidth: Int,
        bubbleHeight: Int,
        screenWidth: Int,
        screenHeight: Int,
        margin: Int,
        topInset: Int,
        bottomInset: Int,
    ): Pair<Int, Int> {
        val minY = topInset + margin
        val maxY = (screenHeight - bottomInset - bubbleHeight - margin).coerceAtLeast(minY)

        // Momentum projection (~160ms ahead)
        val projectedX = currentX + (velocityX * 0.16f).toInt()
        val projectedY = currentY + (velocityY * 0.16f).toInt()

        // Horizontal snap: if user flicked with high horizontal velocity, snap towards flick direction
        val targetX = if (kotlin.math.abs(velocityX) > 600f) {
            if (velocityX < 0) margin else (screenWidth - bubbleWidth - margin).coerceAtLeast(margin)
        } else {
            snapTargetX(projectedX, bubbleWidth, screenWidth, margin)
        }

        // Vertical snap:
        // Fling up/down or within top/bottom 22% zone snaps directly to corner.
        // Otherwise docks cleanly along the edge.
        val safeHeight = maxY - minY
        val cornerZone = (safeHeight * 0.22f).toInt().coerceAtLeast(margin * 2)

        val targetY = when {
            velocityY < -800f || projectedY <= minY + cornerZone -> minY
            velocityY > 800f || projectedY >= maxY - cornerZone -> maxY
            else -> projectedY.coerceIn(minY, maxY)
        }

        return Pair(targetX, targetY)
    }

    /**
     * Linear interpolation between [start] and [end] at [fraction] (0..1).
     * Drives both axes of the bubble's open/close relocation from a single
     * ValueAnimator, the same way [snapTargetX]'s single axis already does.
     */
    fun lerp(start: Int, end: Int, fraction: Float): Int =
        (start + (end - start) * fraction).toInt()

    /**
     * Whether the bubble is currently sitting over the dismiss target, using
     * centre-to-centre distance against a generous [captureRadius] — the target
     * should grab the bubble slightly before the two visually overlap, which is
     * what makes flinging one onto the other feel forgiving.
     */
    fun isOverDismissTarget(
        bubbleX: Int,
        bubbleY: Int,
        bubbleWidth: Int,
        bubbleHeight: Int,
        dismissCentreX: Int,
        dismissCentreY: Int,
        captureRadius: Int,
    ): Boolean {
        val bubbleCentreX = bubbleX + bubbleWidth / 2f
        val bubbleCentreY = bubbleY + bubbleHeight / 2f
        val distance = hypot(
            bubbleCentreX - dismissCentreX,
            bubbleCentreY - dismissCentreY,
        )
        return distance <= captureRadius
    }
}
