package com.ams.herculex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class HxWidgetLookTest {

    @Test
    fun `each transparency level is more see-through than the last`() {
        val opacities = (1..3).map { HxWidgetLook(transparency = it).opacity }

        assertEquals(listOf(0.85f, 0.65f, 0.45f), opacities)
    }

    @Test
    fun `an out-of-range level is clamped, not trusted`() {
        assertEquals(0.85f, HxWidgetLook(transparency = 0).opacity)
        assertEquals(0.45f, HxWidgetLook(transparency = 99).opacity)
    }

    @Test
    fun `the default is the lightest glass in a squircle`() {
        val look = HxWidgetLook()

        assertEquals(1, look.transparency)
        assertEquals(HxCornerShape.SQUIRCLE, look.shape)
    }

    @Test
    fun `only the word pill selects the pill shape`() {
        assertEquals(HxCornerShape.PILL, HxCornerShape.parse("pill"))
        assertEquals(HxCornerShape.SQUIRCLE, HxCornerShape.parse("squircle"))
        assertEquals(HxCornerShape.SQUIRCLE, HxCornerShape.parse("hexagon"))
        assertEquals(HxCornerShape.SQUIRCLE, HxCornerShape.parse(null))
    }

    @Test
    fun `a squircle keeps the 28dp card radius at any height`() {
        val look = HxWidgetLook(shape = HxCornerShape.SQUIRCLE)

        assertEquals(28f, look.cornerRadius(80f))
        assertEquals(28f, look.cornerRadius(176f))
    }

    @Test
    fun `a pill is half the height, capped at 40dp`() {
        val look = HxWidgetLook(shape = HxCornerShape.PILL)

        assertEquals(40f, look.cornerRadius(80f))
        assertEquals(28f, look.cornerRadius(56f))
        // A 2x1 the launcher stretched tall must not turn into a huge round shape.
        assertEquals(40f, look.cornerRadius(200f))
    }

    @Test
    fun `only the one-row widgets get the pill`() {
        val pill = HxWidgetPalette.CLASSIC_BLUE_DARK.copy(
            look = HxWidgetLook(transparency = 2, shape = HxCornerShape.PILL),
        )

        assertSame(pill, pill.forWidget(pillEligible = true))
        val big = pill.forWidget(pillEligible = false)
        assertEquals(HxCornerShape.SQUIRCLE, big.look.shape)
        // Transparency is not shape-specific: every widget keeps it.
        assertEquals(2, big.look.transparency)
    }
}
