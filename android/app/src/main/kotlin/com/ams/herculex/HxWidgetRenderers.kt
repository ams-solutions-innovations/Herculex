package com.ams.herculex

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import com.ams.herculex.HxFonts.Family.MANROPE
import com.ams.herculex.HxFonts.Family.SPACE_GROTESK
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

// Renderers for the Herculex home-screen widgets (design: "Homescreen
// Widgets › 1b"). Each one draws its widget at the given size in dp and is
// free of Android resources, so it can be previewed off-device.

data class HxMacro(val current: Int, val target: Int) {
    val hasTarget: Boolean get() = target > 0
    val fraction: Float get() = if (target > 0) current.toFloat() / target else 0f
}

data class HxNutrition(
    val goal: Int,
    val food: Int,
    val exercise: Int,
    val remaining: Int,
    val protein: HxMacro,
    val carbs: HxMacro,
    val fat: HxMacro,
) {
    val hasGoal: Boolean get() = goal > 0
    val allowance: Int get() = goal + exercise
    val isOver: Boolean get() = hasGoal && remaining < 0
    val fraction: Float get() = if (hasGoal && allowance > 0) food.toFloat() / allowance else 0f
}

data class HxRecovery(val score: Int?, val muscles: List<Pair<String, Int>>)

data class HxCns(val readiness: Int?, val status: String?)

data class HxFasting(
    /** Null when no fast is running. */
    val elapsedSeconds: Long?,
    /** Null for a Quick Fast (no target). */
    val targetSeconds: Long?,
    val planLabel: String?,
    /** Preformatted local end time of the running fast, e.g. "12:30". */
    val endsAt: String?,
)

enum class HxMacroKind(val caption: String, val title: String) {
    PROTEIN("PROTEIN", "Protein"),
    CARBS("CARBS", "Carbs"),
    FAT("FAT", "Fat"),
}

class HxRendered(val bitmap: Bitmap, val description: String)

class HxWidgetRenderer(
    private val fonts: HxFonts,
    private val palette: HxWidgetPalette,
    private val density: Float,
) {
    private val p = palette

    // ── Type scale, as in the design ──────────────────────────────────────
    private val label = HxTextStyle(MANROPE, 10f, 700, p.secondary, tracking = 0.8f)

    private fun grotesk(size: Float, color: Int, tracking: Float = 0f, weight: Int = 700) =
        HxTextStyle(SPACE_GROTESK, size, weight, color, tracking, tabular = true)

    private fun manrope(size: Float, weight: Int, color: Int, tracking: Float = 0f) =
        HxTextStyle(MANROPE, size, weight, color, tracking)

    private fun fmt(n: Int): String = String.format("%,d", n)

    private inline fun draw(w: Float, h: Float, block: HxCanvas.() -> Unit): Bitmap {
        // RemoteViews bitmaps count against a per-widget memory budget; cap the
        // pixel count so a stretched 4×4 placement can't blow through it.
        val maxPixels = 1_600_000f
        var scale = density
        if (w * h * scale * scale > maxPixels) scale = sqrt(maxPixels / (w * h))
        val bitmap = Bitmap.createBitmap(
            (w * scale).toInt().coerceAtLeast(1),
            (h * scale).toInt().coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        HxCanvas(canvas, fonts).block()
        return bitmap
    }

    /** Card header: caps label left, tinted icon chip right, centred on [cy]. */
    private fun HxCanvas.header(w: Float, cy: Float, text: String, icon: HxIcon, accent: Int, iconSize: Float = 16f) {
        this.text(text, 16f, baseline(cy - lineHeight(label) / 2, label), label, maxWidth = w - 32 - 26 - 8)
        iconChip(icon, w - 16 - 13, cy, 26f, iconSize, alpha(accent, 0.15f), accent)
    }

    // ── 4×2 Today ─────────────────────────────────────────────────────────

    fun today(w: Float, h: Float, n: HxNutrition): HxRendered {
        val bitmap = draw(w, h) {
            card(w, h, p, p.kcal)

            // Gauge column: a 270° arc opening at the bottom.
            val size = min(TODAY_RING, h - 32)
            val k = size / TODAY_RING
            val cx = 16 + TODAY_RING / 2
            val cy = h / 2
            ring(cx, cy, 57 * k, 10 * k, 135f, 270f, n.fraction, p.surfaceVariant, p.kcal, roundTrack = true)

            val big = grotesk(28 * k, p.onSurface, tracking = -0.6f * k)
            val unit = manrope(11 * k, 600, p.secondary)
            val unitText = when {
                !n.hasGoal -> "Set a goal"
                n.isOver -> "kcal over"
                else -> "kcal left"
            }
            val blockH = big.size + 2 * k + lineHeight(unit)
            val top = cy - blockH / 2
            text(if (n.hasGoal) fmt(abs(n.remaining)) else "—", cx, baseline(top, big, big.size), big, Paint.Align.CENTER)
            text(unitText, cx, baseline(top + big.size + 2 * k, unit), unit, Paint.Align.CENTER)
            if (n.hasGoal) {
                val of = manrope(10 * k, 700, p.secondary, tracking = 0.4f * k)
                val bottom = cy + size / 2 - 4 * k
                text("of ${fmt(n.allowance)}", cx, baseline(bottom - lineHeight(of), of), of, Paint.Align.CENTER)
            }

            // Macro column. Fixed row metrics so the click overlay in
            // widget_hx_today.xml lines up with the buttons drawn here.
            val x0 = 16 + TODAY_RING + 16
            val cw = w - x0 - 16
            var y = (h - TODAY_COLUMN) / 2
            val name = manrope(12f, 700, p.onSurface)
            val value = grotesk(12f, p.onSurface)
            val target = grotesk(12f, p.secondary, weight = 500)
            for ((kind, m) in macros(n)) {
                val base = baseline(y, name, TODAY_ROW_LABEL)
                text(kind.title, x0, base, name)
                val suffix = if (m.hasTarget) " / ${m.target} g" else ""
                val sw = text(suffix, x0 + cw, base, target, Paint.Align.RIGHT)
                text(if (m.hasTarget) "${m.current}" else "—", x0 + cw - sw, base, value, Paint.Align.RIGHT)
                bar(x0, y + TODAY_ROW_LABEL + 5, cw, 4f, m.fraction, p.surfaceVariant, macroColor(kind))
                y += TODAY_ROW_LABEL + 5 + 4 + 10
            }

            val by = (h - TODAY_COLUMN) / 2 + TODAY_BUTTONS_TOP
            val bw = (cw - 8) / 2
            button(x0, by, bw, 36f, HxIcon.SEARCH, 18f, "Log food", manrope(12f, 700, p.onSurface), p.surfaceVariant)
            button(x0 + bw + 8, by, bw, 36f, HxIcon.BARCODE_SCANNER, 18f, "Scan", manrope(12f, 700, p.onPrimary), p.primary)
        }
        val desc = if (n.hasGoal) {
            "${fmt(abs(n.remaining))} kcal ${if (n.isOver) "over" else "left"} of ${fmt(n.allowance)}"
        } else {
            "No calorie goal set"
        }
        return HxRendered(bitmap, "Today. $desc. ${macroSummary(n)}")
    }

    private fun HxCanvas.button(
        x: Float, y: Float, w: Float, h: Float,
        icon: HxIcon, iconSize: Float, text: String, style: HxTextStyle, bg: Int,
    ) {
        roundRect(x, y, x + w, y + h, h / 2, bg)
        val contentW = iconSize + 6 + width(text, style)
        val left = x + (w - contentW) / 2
        icon(icon, left + iconSize / 2, y + h / 2, iconSize, style.color)
        this.text(text, left + iconSize + 6, baseline(y + (h - lineHeight(style)) / 2, style), style)
    }

    private fun macros(n: HxNutrition) = listOf(
        HxMacroKind.PROTEIN to n.protein,
        HxMacroKind.CARBS to n.carbs,
        HxMacroKind.FAT to n.fat,
    )

    private fun macroColor(kind: HxMacroKind) = when (kind) {
        HxMacroKind.PROTEIN -> p.protein
        HxMacroKind.CARBS -> p.carbs
        HxMacroKind.FAT -> p.fat
    }

    private fun macroSummary(n: HxNutrition) = macros(n).joinToString(". ") { (kind, m) ->
        if (m.hasTarget) "${kind.title} ${m.current} of ${m.target} grams" else "${kind.title} no target"
    }

    // ── 2×2 Calories ──────────────────────────────────────────────────────

    fun calories(w: Float, h: Float, n: HxNutrition): HxRendered {
        val bitmap = draw(w, h) {
            card(w, h, p, p.kcal)
            header(w, 16f + 13, if (n.isOver) "OVER BUDGET" else "REMAINING",
                if (n.isOver) HxIcon.WARNING_FILLED else HxIcon.FIRE_FILLED, p.kcal)

            val foot = grotesk(12f, p.onSurface)
            val footH = maxOf(lineHeight(foot), 15f)
            val midH = 36f + 8 + 6
            val midTop = 16 + 26 + (h - 32 - 26 - midH - footH) / 2

            val big = grotesk(36f, p.kcal, tracking = -0.8f)
            val unit = manrope(12f, 400, p.secondary)
            val base = baseline(midTop, big, 36f)
            val numW = text(if (n.hasGoal) fmt(abs(n.remaining)) else "—", 16f, base, big)
            text(if (n.hasGoal) "kcal" else "Set a goal", 16 + numW + 4, base, unit, maxWidth = w - 32 - numW - 4)
            bar(16f, midTop + 36 + 8, w - 32, 6f, n.fraction, alpha(p.surfaceVariant, 0.7f), p.kcal)

            val footTop = h - 16 - footH
            val footBase = baseline(footTop + (footH - lineHeight(foot)) / 2, foot)
            var x = 16f
            icon(HxIcon.RESTAURANT, x + 7.5f, footTop + footH / 2, 15f, p.protein)
            x += 15 + 4
            x += text(fmt(n.food), x, footBase, foot) + 12
            icon(HxIcon.DIRECTIONS_RUN, x + 7.5f, footTop + footH / 2, 15f, p.success)
            x += 15 + 4
            text("+${fmt(n.exercise)}", x, footBase, foot)
        }
        val desc = if (n.hasGoal) {
            "${fmt(abs(n.remaining))} kcal ${if (n.isOver) "over budget" else "remaining"}"
        } else {
            "No calorie goal set"
        }
        return HxRendered(bitmap, "Calories. $desc. Food ${fmt(n.food)}, exercise ${fmt(n.exercise)}")
    }

    // ── 2×2 Recovery ──────────────────────────────────────────────────────

    fun recovery(w: Float, h: Float, r: HxRecovery): HxRendered {
        val bitmap = draw(w, h) {
            card(w, h, p, p.recovery)
            header(w, 16f + 13, "RECOVERY", HxIcon.BATTERY_CHARGING_FILLED, p.recovery)

            val name = manrope(11f, 600, p.onSurface)
            val rowH = lineHeight(name)
            val footH = if (r.muscles.isEmpty()) rowH else r.muscles.size * rowH + (r.muscles.size - 1) * 6
            val scoreTop = 16 + 26 + (h - 32 - 26 - 36 - footH) / 2
            val score = grotesk(36f, r.score?.let { p.scoreColor(it) } ?: p.secondary, tracking = -0.8f)
            text(r.score?.let { "$it%" } ?: "—", 16f, baseline(scoreTop, score, 36f), score)

            var y = h - 16 - footH
            if (r.muscles.isEmpty()) {
                text("Log a workout to see fatigue", 16f, baseline(y, name), name.withColor(p.secondary), maxWidth = w - 32)
            } else {
                // grid-template-columns: 5fr 4fr 20px, gap 6
                val fr = (w - 32 - 20 - 12) / 9
                val num = manrope(10f, 700, p.secondary)
                for ((muscle, s) in r.muscles) {
                    text(muscle, 16f, baseline(y, name), name, maxWidth = fr * 5)
                    bar(16 + fr * 5 + 6, y + (rowH - 5) / 2, fr * 4, 5f, s / 100f,
                        alpha(p.outlineVariant, 0.6f), p.scoreColor(s), radius = 3f)
                    text("$s", w - 16, baseline(y + (rowH - lineHeight(num)) / 2, num), num, Paint.Align.RIGHT)
                    y += rowH + 6
                }
            }
        }
        val muscles = r.muscles.joinToString(", ") { (m, s) -> "$m $s%" }
        return HxRendered(bitmap, "Recovery ${r.score?.let { "$it%" } ?: "unknown"}. $muscles")
    }

    // ── 4×1 Macros ────────────────────────────────────────────────────────

    fun macros(w: Float, h: Float, n: HxNutrition): HxRendered {
        val bitmap = draw(w, h) {
            card(w, h, p, null)
            val colW = (w - 36 - 36) / 3
            val value = grotesk(18f, p.onSurface)
            val target = grotesk(11f, p.secondary, weight = 500)
            val capH = lineHeight(label)
            val blockH = capH + 4 + value.size * 1.1f + 4 + 4
            val top = (h - blockH) / 2
            macros(n).forEachIndexed { i, (kind, m) ->
                val x = 18 + i * (colW + 18)
                macroColumn(x, top, colW, kind, m, value, target)
            }
        }
        return HxRendered(bitmap, "Macros. ${macroSummary(n)}")
    }

    private fun HxCanvas.macroColumn(
        x: Float, top: Float, colW: Float, kind: HxMacroKind, m: HxMacro,
        value: HxTextStyle, target: HxTextStyle,
    ) {
        val color = macroColor(kind)
        val capH = lineHeight(label)
        circle(x + 3, top + capH / 2, 3f, color)
        text(kind.caption, x + 6 + 5, baseline(top, label), label, maxWidth = colW - 11)
        val vTop = top + capH + 4
        val base = baseline(vTop, value, value.size * 1.1f)
        val vw = text(if (m.hasTarget) "${m.current}" else "—", x, base, value)
        if (m.hasTarget) text(" / ${m.target} g", x + vw, base, target, maxWidth = colW - vw)
        bar(x, vTop + value.size * 1.1f + 4, colW, 4f, m.fraction, p.surfaceVariant, color)
    }

    // ── 2×1 single macro (Protein / Carbs / Fat pills) ────────────────────

    fun macro(w: Float, h: Float, kind: HxMacroKind, m: HxMacro): HxRendered {
        val bitmap = draw(w, h) {
            card(w, h, p, macroColor(kind))
            val value = grotesk(22f, p.onSurface)
            val target = grotesk(11f, p.secondary, weight = 500)
            val blockH = lineHeight(label) + 4 + value.size + 6 + 4
            val top = (h - blockH) / 2
            val color = macroColor(kind)
            val capH = lineHeight(label)
            circle(16f + 3, top + capH / 2, 3f, color)
            text(kind.caption, 16f + 11, baseline(top, label), label)
            val vTop = top + capH + 4
            val base = baseline(vTop, value, value.size)
            val vw = text(if (m.hasTarget) "${m.current}" else "—", 16f, base, value)
            if (m.hasTarget) text(" / ${m.target} g", 16 + vw, base, target, maxWidth = w - 32 - vw)
            bar(16f, vTop + value.size + 6, w - 32, 4f, m.fraction, p.surfaceVariant, color)
        }
        val desc = if (m.hasTarget) "${m.current} of ${m.target} grams" else "no target"
        return HxRendered(bitmap, "${kind.title} $desc")
    }

    // ── 2×2 Fasting ───────────────────────────────────────────────────────

    fun fasting(w: Float, h: Float, f: HxFasting): HxRendered {
        val active = f.elapsedSeconds != null
        val fraction = if (f.elapsedSeconds != null && f.targetSeconds != null && f.targetSeconds > 0) {
            f.elapsedSeconds.toFloat() / f.targetSeconds
        } else {
            0f
        }
        val time = f.elapsedSeconds?.let { "${it / 3600}:${String.format("%02d", (it % 3600) / 60)}" } ?: "—"
        val sub = when {
            !active -> "Tap to start"
            f.targetSeconds == null -> "Quick fast"
            fraction >= 1f -> "Goal reached"
            f.endsAt != null -> "Ends ${f.endsAt}"
            else -> "Fasting"
        }
        val bitmap = draw(w, h) {
            card(w, h, p, p.fasting)
            val badge = HxTextStyle(MANROPE, 10f, 700, p.fasting)
            val headH = lineHeight(badge) + 6
            text("FASTING", 16f, baseline(16 + (headH - lineHeight(label)) / 2, label), label)
            f.planLabel?.let { badge(it, w - 16, 16 + headH / 2, badge, alpha(p.fasting, 0.2f), 8f, 3f) }

            val ringTop = 16 + headH + 6
            val size = min(FASTING_RING, min(h - 16 - ringTop, w - 32))
            val k = size / FASTING_RING
            val cx = w / 2
            val cy = ringTop + size / 2
            ring(cx, cy, 50 * k, 8 * k, -90f, 360f, fraction, p.surfaceVariant, p.fasting, roundTrack = false)

            val big = grotesk(24 * k, p.onSurface, tracking = -0.5f * k)
            val small = manrope(10 * k, 600, p.secondary)
            val blockH = big.size + 2 * k + lineHeight(small)
            val top = cy - blockH / 2
            text(time, cx, baseline(top, big, big.size), big, Paint.Align.CENTER)
            text(sub, cx, baseline(top + big.size + 2 * k, small), small, Paint.Align.CENTER, maxWidth = 84 * k)
        }
        return HxRendered(bitmap, if (active) "Fasting $time. $sub" else "Fasting. Tap to start")
    }

    // ── 2×1 Quick log ─────────────────────────────────────────────────────

    fun quickLog(w: Float, h: Float): HxRendered {
        val bitmap = draw(w, h) {
            card(w, h, p, null)
            val slot = QUICK_LOG_SEARCH
            val scanR = w - 16 - slot - 8
            button(16f, 16f, scanR - 16, h - 32, HxIcon.BARCODE_SCANNER, 20f, "Scan",
                manrope(13f, 700, p.onPrimary), p.primary)
            val d = min(slot, h - 32)
            val cx = w - 16 - slot / 2
            iconChip(HxIcon.SEARCH, cx, h / 2, d, 20f, p.surfaceVariant, p.onSurface)
        }
        return HxRendered(bitmap, "Quick log: scan barcode or search food")
    }

    // ── 2×1 CNS ───────────────────────────────────────────────────────────

    fun cns(w: Float, h: Float, c: HxCns): HxRendered {
        val color = when (c.status) {
            null -> p.secondary
            "FRESH" -> p.success
            "MODERATE" -> p.warning
            else -> p.danger
        }
        val bitmap = draw(w, h) {
            card(w, h, p, p.recovery)
            val cy = h / 2
            iconChip(HxIcon.BOLT_FILLED, 16f + 16, cy, 32f, 18f, alpha(color, 0.15f), color)

            val badge = HxTextStyle(MANROPE, 9f, 700, color)
            val bw = badge(c.status ?: "—", w - 14, cy, badge, alpha(color, 0.2f), 7f, 3f)

            val x = 16f + 32 + 10
            val maxW = w - 14 - bw - 10 - x
            val value = grotesk(20f, color)
            val blockH = lineHeight(label) + 2 + value.size
            val top = cy - blockH / 2
            text("CNS LOAD", x, baseline(top, label), label, maxWidth = maxW)
            text(c.readiness?.let { "$it%" } ?: "—", x, baseline(top + lineHeight(label) + 2, value, value.size), value, maxWidth = maxW)
        }
        return HxRendered(bitmap, "CNS load ${c.readiness?.let { "$it%" } ?: "unknown"}, ${c.status ?: "no data"}")
    }

    companion object {
        const val TODAY_RING = 124f
        const val TODAY_ROW_LABEL = 16f

        /** 3 macro rows (16 + 5 + 4) with 10 gaps, then a 13 gap to the buttons. */
        const val TODAY_BUTTONS_TOP = 3 * (TODAY_ROW_LABEL + 5 + 4) + 2 * 10 + 13
        const val TODAY_COLUMN = TODAY_BUTTONS_TOP + 36

        const val FASTING_RING = 110f
        const val QUICK_LOG_SEARCH = 48f
    }
}
