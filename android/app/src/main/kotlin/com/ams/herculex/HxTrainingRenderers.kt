package com.ams.herculex

import android.graphics.Paint
import com.ams.herculex.HxFonts.Family.MANROPE
import kotlin.math.min

// Renderers for the training, body and habit widgets (design: "Homescreen
// Widgets › 2a"). Same card language as HxWidgetRenderer; the values arrive
// preformatted from Flutter (units, locale), so these only lay them out.

/** Today's Plan button styles. */
enum class HxPlanState { READY, ACTIVE, DONE, NONE }

data class HxPlan(
    val state: HxPlanState,
    val title: String,
    val subtitle: String,
    /** e.g. "Legs 84% ready"; null when readiness doesn't map to the day. */
    val badge: String?,
    val button: String,
)

data class HxWeekDay(val label: String, val day: Int, val today: Boolean, val done: Boolean, val scheduled: Boolean)

data class HxTrend(
    /** Headline value, e.g. "82.4" or "2,310"; null when there's no data. */
    val value: String?,
    /** Unit after the value, e.g. "kg · Oct 6". */
    val unit: String,
    val series: List<Float>,
    val target: Float?,
)

enum class HxStreakKind(val label: String, val icon: HxIcon) {
    WORKOUTS("WORKOUTS", HxIcon.FITNESS_CENTER),
    LOGGING("LOGGING", HxIcon.RESTAURANT),
}

data class HxStreak(val current: Int, val unit: String, val activeToday: Boolean)

data class HxPr(val name: String, val value: String)

data class HxPrs(val unit: String, val items: List<HxPr>)

data class HxNextFocus(val category: String?, val fresh: Int)

data class HxSupplement(val name: String, val detail: String, val taken: Boolean)

data class HxSupplements(val taken: Int, val total: Int, val items: List<HxSupplement>)

data class HxMiniWorkout(val name: String, val done: Int, val total: Int)

enum class HxCyclePhase(val icon: HxIcon) {
    MENSTRUAL(HxIcon.WATER_DROP),
    FOLLICULAR(HxIcon.BOLT),
    OVULATORY(HxIcon.FIRE),
    LUTEAL(HxIcon.SPA),
}

data class HxCycle(
    /** Null when cycle tracking isn't set up. */
    val phase: HxCyclePhase?,
    val title: String,
    val badge: String?,
    val tip: String,
    val footer: String,
    val color: Int?,
)

/** Supplements keep the app's fixed purple, as on the dashboard card. */
private const val SUPPLEMENT = 0xFF9B59B6.toInt()

// ── 4×2 Today's Plan ──────────────────────────────────────────────────────

fun HxWidgetRenderer.todaysPlan(w: Float, h: Float, plan: HxPlan): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, p.primary)
        header(w, 16f + 13, "TODAY'S PLAN", HxIcon.FITNESS_CENTER, p.primary)

        val title = grotesk(30f, p.onSurface, tracking = -0.6f)
        val sub = manrope(12f, 600, p.secondary)
        val badgeStyle = HxTextStyle(MANROPE, 10f, 700, p.success)
        val rowH = maxOf(lineHeight(sub), lineHeight(badgeStyle) + 6)
        val midH = 30f + 4 + rowH
        val midTop = 16 + 26 + (h - 32 - 26 - midH - PLAN_BUTTON) / 2
        text(plan.title, 16f, baseline(midTop, title, 30f), title, maxWidth = w - 32)
        val rowTop = midTop + 30 + 4
        val subW = text(plan.subtitle, 16f, baseline(rowTop + (rowH - lineHeight(sub)) / 2, sub), sub,
            maxWidth = if (plan.badge == null) w - 32 else (w - 32) * 0.55f)
        plan.badge?.let {
            val bw = width(it, badgeStyle) + 16
            badge(it, 16 + subW + 8 + bw, rowTop + rowH / 2, badgeStyle, alpha(p.success, 0.2f), 8f, 3f)
        }

        val primary = plan.state == HxPlanState.READY || plan.state == HxPlanState.ACTIVE
        val icon = when (plan.state) {
            HxPlanState.READY, HxPlanState.ACTIVE -> HxIcon.PLAY_FILLED
            HxPlanState.DONE -> HxIcon.CHECK
            HxPlanState.NONE -> HxIcon.FITNESS_CENTER
        }
        button(16f, h - 16 - PLAN_BUTTON, w - 32, PLAN_BUTTON, icon, 20f, plan.button,
            manrope(14f, 700, if (primary) p.onPrimary else p.onSurface),
            if (primary) p.primary else p.surfaceVariant)
    }
    return HxRendered(bitmap, "Today's plan: ${plan.title}. ${plan.subtitle}. ${plan.badge ?: ""}")
}

/** Height of the Today's Plan button; widget_hx_plan.xml mirrors it. */
const val PLAN_BUTTON = 42f

// ── 4×1 Week ──────────────────────────────────────────────────────────────

fun HxWidgetRenderer.week(w: Float, h: Float, days: List<HxWeekDay>): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, null)
        if (days.isEmpty()) return@draw
        val pad = 12f
        val cellW = (w - pad * 2 - 4 * (days.size - 1)) / days.size
        val cellH = h - pad * 2
        days.forEachIndexed { i, d ->
            val x = pad + i * (cellW + 4)
            val accent = if (d.today) p.primary else null
            roundRect(x, pad, x + cellW, pad + cellH, 16f,
                if (d.today) alpha(p.primary, 0.18f) else alpha(p.surfaceVariant, 0.6f))
            if (accent != null) strokeRoundRect(x, pad, x + cellW, pad + cellH, 16f, accent)

            val lab = manrope(10f, 700, if (d.today) p.primary else p.secondary)
            val num = grotesk(14f, if (d.today) p.primary else p.onSurface)
            val marked = d.today || d.done || d.scheduled
            val dot = if (marked) 6f else 4f
            val blockH = lineHeight(lab) + 3 + 14 + 3 + dot
            var y = pad + (cellH - blockH) / 2
            val cx = x + cellW / 2
            text(d.label, cx, baseline(y, lab), lab, Paint.Align.CENTER)
            y += lineHeight(lab) + 3
            text("${d.day}", cx, baseline(y, num, 14f), num, Paint.Align.CENTER)
            y += 14 + 3
            circle(cx, y + dot / 2, dot / 2, when {
                d.done -> p.success
                marked -> p.primary
                else -> alpha(p.outlineVariant, 0.7f)
            })
        }
    }
    val summary = days.joinToString(", ") { d ->
        "${d.label} ${d.day}${if (d.done) " done" else if (d.scheduled) " planned" else ""}"
    }
    return HxRendered(bitmap, "This week: $summary")
}

// ── 2×2 Bodyweight / Intake trend ─────────────────────────────────────────

fun HxWidgetRenderer.bodyweight(w: Float, h: Float, t: HxTrend): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, p.recovery)
        this.text("BODYWEIGHT", 16f, baseline(29 - lineHeight(label) / 2, label), label)
        iconChip(HxIcon.ADD, w - 16 - 13, 29f, 26f, 18f, alpha(p.primary, 0.12f), p.primary)
        trendBody(this, w, h, t, p.primary, 44f, p.recovery)
    }
    return HxRendered(bitmap, "Bodyweight ${t.value ?: "not logged"} ${t.unit}")
}

fun HxWidgetRenderer.intakeTrend(w: Float, h: Float, t: HxTrend): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, p.nutrition)
        this.text("AVG. INTAKE · 7D", 16f, baseline(29 - lineHeight(label) / 2, label), label, maxWidth = w - 32 - 24)
        icon(HxIcon.CHEVRON_RIGHT, w - 16 - 10, 29f, 20f, p.secondary)
        trendBody(this, w, h, t, p.onSurface, 48f, p.nutrition)
    }
    return HxRendered(bitmap, "Average intake over 7 days ${t.value ?: "not available"} ${t.unit}")
}

/** Value row and sparkline below a 26 dp header, spread like `space-between`. */
private fun HxWidgetRenderer.trendBody(
    c: HxCanvas, w: Float, h: Float, t: HxTrend, valueColor: Int, sparkH: Float, accent: Int,
) = with(c) {
    val big = grotesk(30f, if (t.value == null) p.secondary else valueColor, tracking = -0.6f)
    val unit = manrope(12f, 400, p.secondary)
    val hasSpark = t.series.size >= 2
    // Keep the value where it sits with a chart, so empty and filled line up.
    val gap = (h - 32 - 26 - 30 - sparkH) / 2
    val base = baseline(16 + 26 + gap, big, 30f)
    val vw = text(t.value ?: "—", 16f, base, big)
    text(t.unit, 16 + vw + 4, base, unit, maxWidth = w - 32 - vw - 4)
    if (hasSpark) sparkline(t.series, t.target, 16f, h - 16 - sparkH, w - 32, sparkH, accent)
}

// ── 2×1 Streaks / Volume / Next focus ─────────────────────────────────────

/** The 2×1 stat pill: tinted chip, caps label over a big number and unit. */
private fun HxWidgetRenderer.statPill(
    w: Float, h: Float, accent: Int, icon: HxIcon?, caption: String, value: String, unit: String?,
    trailing: (HxCanvas.(right: Float, cy: Float) -> Float)? = null,
) = draw(w, h) {
    card(w, h, p, accent)
    val cy = h / 2
    var x = 14f
    if (icon != null) {
        iconChip(icon, x + 16, cy, 32f, 18f, alpha(accent, 0.15f), accent)
        x += 32 + 10
    }
    val trailingW = trailing?.invoke(this, w - 14, cy)?.plus(10) ?: 0f
    val maxW = w - 14 - trailingW - x
    val big = grotesk(22f, accent)
    val blockH = lineHeight(label) + 2 + 22
    val top = cy - blockH / 2
    text(caption, x, baseline(top, label), label, maxWidth = maxW)
    val base = baseline(top + lineHeight(label) + 2, big, 22f)
    val vw = text(value, x, base, big, maxWidth = maxW)
    if (unit != null) text(unit, x + vw + 3, base, manrope(11f, 400, p.secondary), maxWidth = maxW - vw - 3)
}

fun HxWidgetRenderer.streak(w: Float, h: Float, kind: HxStreakKind, s: HxStreak): HxRendered {
    val color = if (kind == HxStreakKind.WORKOUTS) p.primary else p.protein
    val bitmap = statPill(w, h, color, kind.icon, kind.label, "${s.current}", s.unit) { right, cy ->
        icon(HxIcon.FIRE_FILLED, right - 9, cy, 18f, if (s.activeToday) color else alpha(color, 0.35f))
        18f
    }
    return HxRendered(bitmap, "${kind.label.lowercase().replaceFirstChar { it.uppercase() }} streak ${s.current} ${s.unit}")
}

fun HxWidgetRenderer.volume(w: Float, h: Float, sets: Int?): HxRendered {
    val bitmap = statPill(w, h, p.primary, HxIcon.BAR_CHART, "VOLUME · WEEK", sets?.toString() ?: "—", sets?.let { "sets" })
    return HxRendered(bitmap, "Volume this week ${sets ?: 0} sets")
}

fun HxWidgetRenderer.nextFocus(w: Float, h: Float, f: HxNextFocus): HxRendered {
    val bitmap = statPill(w, h, p.recovery, null, "NEXT FOCUS", f.category ?: "—", null) { right, cy ->
        if (f.category == null) return@statPill 0f
        badge("${f.fresh} fresh", right, cy, HxTextStyle(MANROPE, 10f, 700, p.recovery), alpha(p.recovery, 0.2f), 8f, 3f)
    }
    return HxRendered(bitmap, "Next focus ${f.category ?: "unknown"}, ${f.fresh} muscles fresh")
}

// ── 2×2 Latest PRs ────────────────────────────────────────────────────────

fun HxWidgetRenderer.latestPrs(w: Float, h: Float, prs: HxPrs): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, p.primary)
        header(w, 16f + 13, "LATEST PRS", HxIcon.TROPHY, p.primary)
        val name = manrope(12f, 600, p.onSurface)
        val value = grotesk(14f, p.primary)
        val unit = grotesk(10f, p.secondary, weight = 500)
        val rowH = maxOf(lineHeight(name), lineHeight(value))
        var y = 16f + 26 + 12
        if (prs.items.isEmpty()) {
            paragraph("Log heavy sets to see your PRs", 16f, y, w - 32, name.withColor(p.secondary), 3)
        }
        for (pr in prs.items.take(3)) {
            val base = baseline(y, value, rowH)
            val uw = text(" ${prs.unit}", w - 16, base, unit, Paint.Align.RIGHT)
            val vw = text(pr.value, w - 16 - uw, base, value, Paint.Align.RIGHT)
            text(pr.name, 16f, base, name, maxWidth = w - 32 - uw - vw - 6)
            y += rowH + 9
        }
        val foot = manrope(10f, 600, p.secondary)
        text("Estimated 1RM", 16f, baseline(h - 16 - lineHeight(foot), foot), foot)
    }
    val list = prs.items.take(3).joinToString(", ") { "${it.name} ${it.value} ${prs.unit}" }
    return HxRendered(bitmap, "Latest PRs, estimated one rep max: $list")
}

// ── 4×2 Supplements ───────────────────────────────────────────────────────

fun HxWidgetRenderer.supplements(w: Float, h: Float, s: HxSupplements): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, SUPPLEMENT)
        val headCy = 16f + 16
        iconChip(HxIcon.MEDICATION, 16f + 16, headCy, 32f, 18f, alpha(SUPPLEMENT, 0.15f), SUPPLEMENT)
        val cap = manrope(10f, 700, SUPPLEMENT, tracking = 1f)
        val sub = manrope(12f, 600, p.secondary)
        val pct = if (s.total > 0) s.taken * 100 / s.total else 0
        val badgeW = if (s.total > 0) {
            badge("$pct%", w - 16, headCy, HxTextStyle(MANROPE, 11f, 700, SUPPLEMENT), alpha(SUPPLEMENT, 0.12f), 10f, 4f)
        } else {
            0f
        }
        val tx = 16f + 32 + 10
        val textW = w - 16 - badgeW - 10 - tx
        val headH = lineHeight(cap) + lineHeight(sub)
        val top = headCy - headH / 2
        text("SUPPLEMENTS", tx, baseline(top, cap), cap, maxWidth = textW)
        text(if (s.total > 0) "${s.taken} of ${s.total} taken today" else "Nothing scheduled yet",
            tx, baseline(top + lineHeight(cap), sub), sub, maxWidth = textW)

        val barTop = 16f + 32 + 10
        bar(16f, barTop, w - 32, 6f, if (s.total > 0) s.taken.toFloat() / s.total else 0f, p.surfaceVariant, SUPPLEMENT, radius = 4f)

        var gridTop = barTop + 6 + 10
        if (s.items.isEmpty()) {
            paragraph("Add supplements in Herculex to tick them off here.", 16f, gridTop, w - 32, sub, 2)
            return@draw
        }
        val colW = (w - 32 - 14) / 2
        s.items.take(SUPPLEMENT_SLOTS).forEachIndexed { i, item ->
            val x = 16 + (i % 2) * (colW + 14)
            val y = gridTop + (i / 2) * (20 + 8)
            val cy = y + 10
            if (item.taken) {
                circle(x + 10, cy, 10f, SUPPLEMENT)
                icon(HxIcon.CHECK, x + 10, cy, 14f, 0xFFFFFFFF.toInt())
            } else {
                ringOutline(x + 10, cy, 10f, 1.8f, p.outlineVariant)
            }
            val detail = manrope(10f, 400, p.secondary)
            val dw = if (item.detail.isNotEmpty()) text(item.detail, x + colW, baseline(cy - lineHeight(detail) / 2, detail), detail, Paint.Align.RIGHT) else 0f
            val nameStyle = manrope(12f, 600, if (item.taken) p.secondary else p.onSurface).copy(strike = item.taken)
            text(item.name, x + 28, baseline(cy - lineHeight(nameStyle) / 2, nameStyle), nameStyle,
                maxWidth = colW - 28 - dw - (if (dw > 0) 8 else 0))
        }
    }
    val list = s.items.joinToString(", ") { "${it.name} ${if (it.taken) "taken" else "not taken"}" }
    return HxRendered(bitmap, "Supplements, ${s.taken} of ${s.total} taken today. $list")
}

/** 2 columns × 3 rows fit a 4×2 cell. */
const val SUPPLEMENT_SLOTS = 6

// ── 4×1 Mini workout ──────────────────────────────────────────────────────

/** Width of the "+1 Done" button; widget_hx_mini.xml mirrors it. */
const val MINI_BUTTON = 88f

fun HxWidgetRenderer.miniWorkout(w: Float, h: Float, m: HxMiniWorkout?): HxRendered {
    val allDone = m != null && m.done >= m.total
    val bitmap = draw(w, h) {
        card(w, h, p, p.primary)
        val cy = h / 2
        iconChip(HxIcon.CHECK_BOX, 16f + 16, cy, 32f, 18f, alpha(p.primary, 0.15f), p.primary)
        val x = 16f + 32 + 12
        val buttonX = w - 14 - MINI_BUTTON
        val title = manrope(14f, 700, p.onSurface)
        val sub = manrope(11f, 600, p.secondary)
        val blockH = lineHeight(title) + 3 + lineHeight(sub)
        val top = cy - blockH / 2
        val maxW = buttonX - 12 - x
        text(m?.name ?: "No mini workouts", x, baseline(top, title), title, maxWidth = maxW)
        val rowTop = top + lineHeight(title) + 3
        if (m == null) {
            text("Tap to set one up", x, baseline(rowTop, sub), sub, maxWidth = maxW)
        } else {
            var sx = x
            if (m.total in 1..8) {
                repeat(m.total) { i ->
                    roundRect(sx, rowTop + (lineHeight(sub) - 5) / 2, sx + 14, rowTop + (lineHeight(sub) + 5) / 2, 999f,
                        if (i < m.done) p.primary else p.surfaceVariant)
                    sx += 14 + 6
                }
            }
            text(if (allDone) "All ${m.total} rounds done" else "${m.done} of ${m.total} rounds",
                sx, baseline(rowTop, sub), sub, maxWidth = buttonX - 12 - sx)
            val bTop = cy - 20
            roundRect(buttonX, bTop, buttonX + MINI_BUTTON, bTop + 40, 20f,
                if (allDone) p.surfaceVariant else alpha(p.primary, 0.18f))
            val bs = manrope(13f, 700, if (allDone) p.secondary else p.primary)
            text(if (allDone) "Done" else "+1 Done", buttonX + MINI_BUTTON / 2,
                baseline(cy - lineHeight(bs) / 2, bs), bs, Paint.Align.CENTER)
        }
    }
    val desc = m?.let { "${it.name}, ${it.done} of ${it.total} rounds" } ?: "No mini workouts set up"
    return HxRendered(bitmap, "Mini workout: $desc")
}

// ── 2×2 Cycle ─────────────────────────────────────────────────────────────

fun HxWidgetRenderer.cycle(w: Float, h: Float, c: HxCycle): HxRendered {
    val color = c.color ?: p.secondary
    val bitmap = draw(w, h) {
        card(w, h, p, color)
        val headCy = 16f + 16
        iconChip(c.phase?.icon ?: HxIcon.SPA, 16f + 16, headCy, 32f, 18f, alpha(color, 0.2f), color)
        c.badge?.let {
            badge(it, w - 16, headCy, HxTextStyle(MANROPE, 10f, 700, color), alpha(color, 0.2f), 8f, 3f, radius = 8f)
        }

        val foot = manrope(11f, 700, color)
        val footTop = h - 16 - lineHeight(foot)
        text(c.footer, 16f, baseline(footTop, foot), foot, maxWidth = w - 32)

        val title = grotesk(22f, p.onSurface, tracking = -0.4f)
        val tip = manrope(11f, 500, p.secondary)
        val tipLine = 11f * 1.35f
        val space = footTop - (16f + 32)
        // Phase name plus as many tip lines as fit, centred between header and footer.
        val lines = ((space - 22 - 4 - 8) / tipLine).toInt().coerceIn(1, 3)
        val blockH = 22 + 4 + lines * tipLine
        val top = 16f + 32 + (space - blockH) / 2
        text(c.title, 16f, baseline(top, title, 22f), title, maxWidth = w - 32)
        paragraph(c.tip, 16f, top + 22 + 4, w - 32, tip, lines, tipLine)
    }
    return HxRendered(bitmap, "Cycle: ${c.title}. ${c.badge ?: ""}. ${c.tip}. ${c.footer}")
}
