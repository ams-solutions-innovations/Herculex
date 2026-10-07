package com.ams.herculex.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncAnimationTest {
    private val d = 2000

    @Test
    fun spinsTwiceWithDipThenSwapsToCheck() {
        val start = syncFrameAt(0f, d)
        assertEquals(SyncPhase.Syncing, start.phase)
        assertEquals(0f, start.spinRotation, 0.01f)
        assertEquals(0f, start.checkAlpha, 0.001f)

        // Dip to 0.88× lands on the first full turn.
        val spin = (0 until 1700).map { syncFrameAt(it.toFloat(), d) }
        val dip = spin.minByOrNull { it.spinScale }!!
        assertEquals(0.88f, dip.spinScale, 0.005f)
        assertEquals(360f, dip.spinRotation, 5f)

        val justBeforeSwap = syncFrameAt(1699f, d)
        assertEquals(SyncPhase.Syncing, justBeforeSwap.phase)
        assertTrue(justBeforeSwap.spinRotation > 715f)
    }

    @Test
    fun successPopsCheckRingAndFlash() {
        // 85 % of 2 s = 1700 ms; success effects start 90 ms later.
        val swap = syncFrameAt(1700f, d)
        assertEquals(SyncPhase.Done, swap.phase)
        assertEquals(0f, swap.checkAlpha, 0.001f)
        assertEquals(0f, swap.ringAlpha, 0.001f)

        val popped = syncFrameAt(1790f + 420f, d)
        assertEquals(0f, popped.spinAlpha, 0.001f)
        assertEquals(1f, popped.checkAlpha, 0.001f)
        assertEquals(1f, popped.checkScale, 0.001f)

        val flashPeak = syncFrameAt(1790f + 275f, d)
        assertEquals(1f, flashPeak.flash, 0.001f)
        assertTrue(flashPeak.ringScale > 1f && flashPeak.ringAlpha > 0f)
    }

    @Test
    fun settlesBackToSyncIcon() {
        val end = syncFrameAt(syncTotalMs(d), d)
        assertEquals(1f, end.spinAlpha, 0.001f)
        assertEquals(1f, end.spinScale, 0.001f)
        assertEquals(0f, end.checkAlpha, 0.001f)
        assertEquals(0f, end.ringAlpha, 0.001f)
        assertEquals(0f, end.flash, 0.001f)
        assertEquals(3500f, syncTotalMs(d), 0.001f)
    }
}
