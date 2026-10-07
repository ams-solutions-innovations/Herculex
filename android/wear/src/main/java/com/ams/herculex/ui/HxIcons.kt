package com.ams.herculex.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

/**
 * Herculex watch icon set: 41 glyphs on a 24 grid, 1.75 stroke, round caps,
 * soft fill accents. Drawn in black and meant to be tinted (wear `Icon`'s
 * `tint`), so the fill accents keep their opacity in any colour.
 *
 * Paths are generated from the Claude Design handoff
 * ("Herculex Watch Icons", symbol ids `i-*`).
 */
object HxIcons {
    // ── Accessories ─────────────────────────────────────────────────

    val None: ImageVector by lazy {
        glyph("None") {
            glyphPath("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0Z")
            glyphPath("M6 18L18 6")
        }
    }

    val Belt: ImageVector by lazy {
        glyph("Belt") {
            glyphPath("M2.5 8.5Q12 5.5 21.5 8.5V16Q12 13 2.5 16Z", fill = 0.24f)
            glyphPath("M10.2,8.2H13.8A1.2,1.2 0 0,1 15,9.4V12.4A1.2,1.2 0 0,1 13.8,13.6H10.2A1.2,1.2 0 0,1 9,12.4V9.4A1.2,1.2 0 0,1 10.2,8.2Z")
            glyphPath("M12 9.6v2.6")
            glyphPath("M4.2,11.7a0.8,0.8 0 1,0 1.6,0a0.8,0.8 0 1,0 -1.6,0Z", fill = 1f, stroke = null)
            glyphPath("M6.2,11.1a0.8,0.8 0 1,0 1.6,0a0.8,0.8 0 1,0 -1.6,0Z", fill = 1f, stroke = null)
        }
    }

    val KneeSleeves: ImageVector by lazy {
        glyph("KneeSleeves") {
            glyphPath("M6.5 3.5Q12 5.5 17.5 3.5L16.3 20.3Q12 22 7.7 20.3Z", fill = 0.24f)
            glyphPath("M6.9 7.2Q12 9 17.1 7.2")
            glyphPath("M7.3 17.2Q12 19 16.7 17.2")
            glyphPath("M9.4,12.4a2.6,2.9 0 1,0 5.2,0a2.6,2.9 0 1,0 -5.2,0Z")
        }
    }

    val WristWraps: ImageVector by lazy {
        glyph("WristWraps") {
            glyphPath("M8.1,6.5H15.4A2.6,2.6 0 0,1 18,9.1V14.9A2.6,2.6 0 0,1 15.4,17.5H8.1A2.6,2.6 0 0,1 5.5,14.9V9.1A2.6,2.6 0 0,1 8.1,6.5Z", fill = 0.24f)
            glyphPath("M9.2 6.5L8.2 17.5M13.2 6.5L12.2 17.5")
            glyphPath("M5.5 10.2H3.9a1.8 1.8 0 0 0 0 3.6H5.5")
            glyphPath("M18 9.5h3v5h-3")
        }
    }

    val Straps: ImageVector by lazy {
        glyph("Straps") {
            glyphPath("M4.8,10H19.2A2.3,2.3 0 0,1 21.5,12.3V12.3A2.3,2.3 0 0,1 19.2,14.6H4.8A2.3,2.3 0 0,1 2.5,12.3V12.3A2.3,2.3 0 0,1 4.8,10Z", fill = 0.24f)
            glyphPath("M10,7.6H14A1.4,1.4 0 0,1 15.4,9V15.6A1.4,1.4 0 0,1 14,17H10A1.4,1.4 0 0,1 8.6,15.6V9A1.4,1.4 0 0,1 10,7.6Z", fill = 0.4f)
            glyphPath("M10.6 17V19.3a1.4 1.4 0 0 0 2.8 0V17")
        }
    }

    val FatGrips: ImageVector by lazy {
        glyph("FatGrips") {
            glyphPath("M9.6,6.5H14.4A3.6,3.6 0 0,1 18,10.1V13.9A3.6,3.6 0 0,1 14.4,17.5H9.6A3.6,3.6 0 0,1 6,13.9V10.1A3.6,3.6 0 0,1 9.6,6.5Z", fill = 0.24f)
            glyphPath("M2.5 12H6M18 12h3.5")
            glyphPath("M9.6 9.6v4.8M12 9.6v4.8M14.4 9.6v4.8")
        }
    }

    val Chains: ImageVector by lazy {
        glyph("Chains") {
            group(rotate = -45f, pivotX = 7f, pivotY = 17f) {
                glyphPath("M5,14.5H9A2.5,2.5 0 0,1 11.5,17V17A2.5,2.5 0 0,1 9,19.5H5A2.5,2.5 0 0,1 2.5,17V17A2.5,2.5 0 0,1 5,14.5Z")
            }
            group(rotate = -45f, pivotX = 12f, pivotY = 12f) {
                glyphPath("M9.9,10.9H14.1A1.1,1.1 0 0,1 15.2,12V12A1.1,1.1 0 0,1 14.1,13.1H9.9A1.1,1.1 0 0,1 8.8,12V12A1.1,1.1 0 0,1 9.9,10.9Z", fill = 1f)
            }
            group(rotate = -45f, pivotX = 17f, pivotY = 7f) {
                glyphPath("M15,4.5H19A2.5,2.5 0 0,1 21.5,7V7A2.5,2.5 0 0,1 19,9.5H15A2.5,2.5 0 0,1 12.5,7V7A2.5,2.5 0 0,1 15,4.5Z")
            }
        }
    }

    val Bands: ImageVector by lazy {
        glyph("Bands") {
            glyphPath("M5.3 7.2C1.5 12 2.9 19.2 10.1 20.2C18.7 21.1 22.6 14.9 18.7 8.2C15.8 2.9 9.1 2.4 5.3 7.2Z", fill = 0.2f)
            glyphPath("M7.2 8.6C4.8 12 5.8 16.8 10.6 17.8C16.3 18.2 19.2 13.9 16.8 9.6C14.4 5.3 10.1 5.3 7.2 8.6", stroke = 1.1f, strokeAlpha = 0.7f)
        }
    }

    // ── Food & macros ───────────────────────────────────────────────

    val Utensils: ImageVector by lazy {
        glyph("Utensils") {
            glyphPath("M5 3.5V8.5a2.4 2.4 0 0 0 4.8 0V3.5")
            glyphPath("M7.4 3.5V20.5")
            glyphPath("M17.5 20.5V3.5c-2.4 1.4-3.6 4-3.6 7.2 0 1.2.6 1.8 1.6 1.8h2", fill = 0.24f)
        }
    }

    val Apple: ImageVector by lazy {
        glyph("Apple") {
            glyphPath("M12 8c-1.6-1.3-6.5-1.5-6.5 3.8 0 4.2 2.7 8.7 5 8.7.7 0 1.1-.4 1.5-.4s.8.4 1.5.4c2.3 0 5-4.5 5-8.7C18.5 6.5 13.6 6.7 12 8z", fill = 0.24f)
            glyphPath("M12 7.6C12 5.6 13.2 4 15 3.4")
        }
    }

    val Nutrients: ImageVector by lazy {
        glyph("Nutrients") {
            glyphPath("M9.5 6.5h10.5M9.5 12h10.5M9.5 17.5h10.5")
            glyphPath("M3.6,6.5a1.2,1.2 0 1,0 2.4,0a1.2,1.2 0 1,0 -2.4,0Z", fill = 1f, stroke = null)
            glyphPath("M3.6,12a1.2,1.2 0 1,0 2.4,0a1.2,1.2 0 1,0 -2.4,0Z", fill = 1f, stroke = null)
            glyphPath("M3.6,17.5a1.2,1.2 0 1,0 2.4,0a1.2,1.2 0 1,0 -2.4,0Z", fill = 1f, stroke = null)
        }
    }

    val Flame: ImageVector by lazy {
        glyph("Flame") {
            glyphPath("M12 3c.6 3.3 5.6 5.7 5.6 11a5.6 5.6 0 0 1-11.2 0c0-2.1.9-3.6 2.1-4.7.3 1.5 1.1 2.3 1.9 2.6C10.2 8.7 10.6 5.6 12 3z", fill = 0.24f)
            glyphPath("M12 20a2.7 2.7 0 0 1-2.7-2.7c0-1.7 1.5-2.5 2.7-4.3 1.2 1.8 2.7 2.6 2.7 4.3A2.7 2.7 0 0 1 12 20z", fill = 1f, stroke = null)
        }
    }

    val Drop: ImageVector by lazy {
        glyph("Drop") {
            glyphPath("M12 3.4c3 3.6 6 6.9 6 10.4a6 6 0 0 1-12 0c0-3.5 3-6.8 6-10.4z", fill = 0.24f)
            glyphPath("M9.3 14.4a3 3 0 0 0 2.3 2.8")
        }
    }

    val Mic: ImageVector by lazy {
        glyph("Mic") {
            glyphPath("M12,3H12A3,3 0 0,1 15,6V11A3,3 0 0,1 12,14H12A3,3 0 0,1 9,11V6A3,3 0 0,1 12,3Z", fill = 0.24f)
            glyphPath("M5.6 11.2a6.4 6.4 0 0 0 12.8 0M12 17.6V21M9 21h6")
        }
    }

    val Protein: ImageVector by lazy {
        glyph("Protein") {
            glyphPath("M4.4 12.3C4.4 7.8 8 4.7 12.6 5.1c4.6.4 7.3 3.6 6.9 7.6-.4 4-3.5 6.6-7.6 6.4-4.6-.2-7.5-2.7-7.5-6.8z", fill = 0.24f)
            glyphPath("M11.8,11.8a2.4,2.4 0 1,0 4.8,0a2.4,2.4 0 1,0 -4.8,0Z")
            glyphPath("M7.4 12.2c.8-1.6 2-2.2 3.2-1.8")
        }
    }

    val Carbs: ImageVector by lazy {
        glyph("Carbs") {
            glyphPath("M12 21V8.1")
            glyphPath("M10.3,5.4a1.7,2.7 0 1,0 3.4,0a1.7,2.7 0 1,0 -3.4,0Z", fill = 0.24f)
            glyphPath("M12 12.2C9.4 12.4 7.6 10.8 7.4 8.4C10 8.4 12 9.8 12 12.2ZM12 12.2C14.6 12.4 16.4 10.8 16.6 8.4C14 8.4 12 9.8 12 12.2Z", fill = 0.24f)
            group(translationY = 4f) {
                glyphPath("M12 12.2C9.4 12.4 7.6 10.8 7.4 8.4C10 8.4 12 9.8 12 12.2ZM12 12.2C14.6 12.4 16.4 10.8 16.6 8.4C14 8.4 12 9.8 12 12.2Z", fill = 0.24f)
            }
            group(translationY = 8f) {
                glyphPath("M12 12.2C9.4 12.4 7.6 10.8 7.4 8.4C10 8.4 12 9.8 12 12.2ZM12 12.2C14.6 12.4 16.4 10.8 16.6 8.4C14 8.4 12 9.8 12 12.2Z", fill = 0.24f)
            }
        }
    }

    val Fat: ImageVector by lazy {
        glyph("Fat") {
            glyphPath("M12 3.4c2 0 2.8 1.6 3.2 3.2.4 1.5 1.4 2.5 2.2 3.8 1.2 1.9 1.1 3.9.3 5.6-1.2 2.3-3.1 4.4-5.7 4.4s-4.5-2.1-5.7-4.4c-.8-1.7-.9-3.7.3-5.6.8-1.3 1.8-2.3 2.2-3.8C9.2 5 10 3.4 12 3.4z", fill = 0.24f)
            glyphPath("M9.3,14.3a2.7,2.7 0 1,0 5.4,0a2.7,2.7 0 1,0 -5.4,0Z", fill = 1f, stroke = null)
        }
    }

    // ── App ─────────────────────────────────────────────────────────

    val Sync: ImageVector by lazy {
        glyph("Sync") {
            glyphPath("M4.5 12a7.5 7.5 0 0 1 12.8-5.3L19.5 8.8")
            glyphPath("M19.5 4v4.8h-4.8")
            glyphPath("M19.5 12a7.5 7.5 0 0 1-12.8 5.3L4.5 15.2")
            glyphPath("M4.5 20v-4.8h4.8")
        }
    }

    val Fasting: ImageVector by lazy {
        glyph("Fasting") {
            glyphPath("M7.5 3.5h9c0 3.8-2.6 5.6-4.5 8.5 1.9 2.9 4.5 4.7 4.5 8.5h-9c0-3.8 2.6-5.6 4.5-8.5C10.1 9.1 7.5 7.3 7.5 3.5z")
            glyphPath("M5.8 3.5h12.4M5.8 20.5h12.4")
            glyphPath("M9.6 6.3h4.8c-.5 1.4-1.5 2.4-2.4 3.5-.9-1.1-1.9-2.1-2.4-3.5z", fill = 1f, stroke = null)
            glyphPath("M9.4 19h5.2c-.3-1.6-1.4-2.7-2.6-4-1.2 1.3-2.3 2.4-2.6 4z", fill = 1f, stroke = null)
        }
    }

    val Dumbbell: ImageVector by lazy {
        glyph("Dumbbell") {
            glyphPath("M6 5h2v14H6zM3 8h2v8H3zM16 5h2v14h-2zM19 8h2v8h-2zM8 11h8v2H8z", fill = 1f, stroke = 1f, cap = StrokeCap.Butt)
        }
    }

    val Timer: ImageVector by lazy {
        glyph("Timer") {
            glyphPath("M4.5,13.5a7.5,7.5 0 1,0 15,0a7.5,7.5 0 1,0 -15,0Z", fill = 0.16f)
            glyphPath("M10 2.8h4M12 2.8V6M12 13.5v-4M18.2 7.3l1.3-1.3")
            glyphPath("M10.9,13.5a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0Z", fill = 1f, stroke = null)
        }
    }

    val Barbell: ImageVector by lazy {
        glyph("Barbell") {
            glyphPath("M3 12h18")
            glyphPath("M6.1,5.5H6.5A0.9,0.9 0 0,1 7.4,6.4V17.6A0.9,0.9 0 0,1 6.5,18.5H6.1A0.9,0.9 0 0,1 5.2,17.6V6.4A0.9,0.9 0 0,1 6.1,5.5Z", fill = 1f, stroke = null)
            glyphPath("M3.4,8H3.6A0.8,0.8 0 0,1 4.4,8.8V15.2A0.8,0.8 0 0,1 3.6,16H3.4A0.8,0.8 0 0,1 2.6,15.2V8.8A0.8,0.8 0 0,1 3.4,8Z", fill = 1f, stroke = null)
            glyphPath("M17.5,5.5H17.9A0.9,0.9 0 0,1 18.8,6.4V17.6A0.9,0.9 0 0,1 17.9,18.5H17.5A0.9,0.9 0 0,1 16.6,17.6V6.4A0.9,0.9 0 0,1 17.5,5.5Z", fill = 1f, stroke = null)
            glyphPath("M20.4,8H20.6A0.8,0.8 0 0,1 21.4,8.8V15.2A0.8,0.8 0 0,1 20.6,16H20.4A0.8,0.8 0 0,1 19.6,15.2V8.8A0.8,0.8 0 0,1 20.4,8Z", fill = 1f, stroke = null)
        }
    }

    // ── Volume ──────────────────────────────────────────────────────

    val VolumeMute: ImageVector by lazy {
        glyph("VolumeMute") {
            glyphPath("M4 9.5h3.2L12 5.5v13l-4.8-4H4z", fill = 0.24f)
            glyphPath("M15.8 9.6l5 5M20.8 9.6l-5 5")
        }
    }

    val VolumeLow: ImageVector by lazy {
        glyph("VolumeLow") {
            glyphPath("M4 9.5h3.2L12 5.5v13l-4.8-4H4z", fill = 0.24f)
            glyphPath("M15.5 9.3a4 4 0 0 1 0 5.4")
        }
    }

    val VolumeHigh: ImageVector by lazy {
        glyph("VolumeHigh") {
            glyphPath("M4 9.5h3.2L12 5.5v13l-4.8-4H4z", fill = 0.24f)
            glyphPath("M15.5 9.3a4 4 0 0 1 0 5.4M18.2 6.6a8 8 0 0 1 0 10.8")
        }
    }

    val Minus: ImageVector by lazy {
        glyph("Minus") {
            glyphPath("M5.5 12h13")
        }
    }

    val Plus: ImageVector by lazy {
        glyph("Plus") {
            glyphPath("M12 5.5v13M5.5 12h13")
        }
    }

    // ── Actions & status ────────────────────────────────────────────

    val Check: ImageVector by lazy {
        glyph("Check") {
            glyphPath("M5 12.5l4.5 4.5L19 7.5")
        }
    }

    val Close: ImageVector by lazy {
        glyph("Close") {
            glyphPath("M6.5 6.5l11 11M17.5 6.5l-11 11")
        }
    }

    val Play: ImageVector by lazy {
        glyph("Play") {
            glyphPath("M8 5.6v12.8L19 12z", fill = 1f, stroke = 2f, cap = StrokeCap.Butt)
        }
    }

    val Stop: ImageVector by lazy {
        glyph("Stop") {
            glyphPath("M9,6.5H15A2.5,2.5 0 0,1 17.5,9V15A2.5,2.5 0 0,1 15,17.5H9A2.5,2.5 0 0,1 6.5,15V9A2.5,2.5 0 0,1 9,6.5Z", fill = 1f, stroke = 1.5f, cap = StrokeCap.Butt)
        }
    }

    val Swap: ImageVector by lazy {
        glyph("Swap") {
            glyphPath("M4 8h14M14.5 4.5L18 8l-3.5 3.5M20 16H6M9.5 12.5L6 16l3.5 3.5")
        }
    }

    val Sliders: ImageVector by lazy {
        glyph("Sliders") {
            glyphPath("M4 7h8.2M16.8 7H20M4 17h3.2M11.8 17H20")
            glyphPath("M12.2,7a2.3,2.3 0 1,0 4.6,0a2.3,2.3 0 1,0 -4.6,0Z")
            glyphPath("M7.2,17a2.3,2.3 0 1,0 4.6,0a2.3,2.3 0 1,0 -4.6,0Z")
        }
    }

    val Trash: ImageVector by lazy {
        glyph("Trash") {
            glyphPath("M4.5 6.5h15M9.5 6.5V4.5h5v2")
            glyphPath("M6.5 6.5l.9 13.2c.05.5.45.8.9.8h7.4c.45 0 .85-.3.9-.8l.9-13.2", fill = 0.24f)
            glyphPath("M10 10.5v6.2M14 10.5v6.2")
        }
    }

    val Save: ImageVector by lazy {
        glyph("Save") {
            glyphPath("M5.5 4.5h10.3l3.7 3.7V19a1 1 0 0 1-1 1H5.5a1 1 0 0 1-1-1V5.5a1 1 0 0 1 1-1z", fill = 0.24f)
            glyphPath("M8 4.8V8.5h6.5V4.8")
            glyphPath("M7.5 20v-6.2a.8.8 0 0 1 .8-.8h7.4a.8.8 0 0 1 .8.8V20")
        }
    }

    val Chevron: ImageVector by lazy {
        glyph("Chevron") {
            glyphPath("M9.5 6l6 6-6 6")
        }
    }

    val Search: ImageVector by lazy {
        glyph("Search") {
            glyphPath("M4.5,10.5a6,6 0 1,0 12,0a6,6 0 1,0 -12,0Z", fill = 0.16f)
            glyphPath("M15 15l5 5")
        }
    }

    val Star: ImageVector by lazy {
        glyph("Star") {
            glyphPath("M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9l-5.2 2.8 1-5.9-4.3-4.1 5.9-.8z", fill = 0.24f)
        }
    }

    val Clock: ImageVector by lazy {
        glyph("Clock") {
            glyphPath("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0Z", fill = 0.16f)
            glyphPath("M12 7.5V12l3.2 2")
        }
    }

    val Heart: ImageVector by lazy {
        glyph("Heart") {
            glyphPath("M12 20.2C7.6 17.4 4.5 14 4.5 10.2 4.5 7.8 6.3 6 8.5 6c1.4 0 2.6.7 3.5 1.9C12.9 6.7 14.1 6 15.5 6c2.2 0 4 1.8 4 4.2 0 3.8-3.1 7.2-7.5 10z", fill = 0.24f)
        }
    }

    val Trophy: ImageVector by lazy {
        glyph("Trophy") {
            glyphPath("M7.5 4.5h9v5a4.5 4.5 0 0 1-9 0z", fill = 0.24f)
            glyphPath("M7.5 6.5H4.6v1.3a3 3 0 0 0 3 3M16.5 6.5h2.9v1.3a3 3 0 0 1-3 3")
            glyphPath("M12 14v3.5M9.9 20.5h4.2M10.5 17.5h3")
        }
    }
}

private const val STROKE = 1.75f
private val Ink = SolidColor(Color.Black)

private fun glyph(name: String, block: ImageVector.Builder.() -> Unit): ImageVector =
    ImageVector.Builder(
        name = "Hx.$name",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply(block).build()

/**
 * One SVG path. [fill] is the fill opacity (null = no fill); [stroke] is the
 * stroke width (null = no stroke).
 */
private fun ImageVector.Builder.glyphPath(
    d: String,
    fill: Float? = null,
    stroke: Float? = STROKE,
    strokeAlpha: Float = 1f,
    cap: StrokeCap = StrokeCap.Round,
) {
    addPath(
        pathData = addPathNodes(d),
        fill = if (fill != null) Ink else null,
        fillAlpha = fill ?: 1f,
        stroke = if (stroke != null) Ink else null,
        strokeAlpha = strokeAlpha,
        strokeLineWidth = stroke ?: 0f,
        strokeLineCap = cap,
        strokeLineJoin = StrokeJoin.Round,
    )
}

