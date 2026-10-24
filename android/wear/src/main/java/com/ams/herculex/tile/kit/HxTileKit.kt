package com.ams.herculex.tile.kit

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.ColorBuilders.ColorProp
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.DimensionBuilders.DegreesProp
import androidx.wear.protolayout.DimensionBuilders.DpProp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.expression.AnimationParameterBuilders.AnimationParameters
import androidx.wear.protolayout.expression.AnimationParameterBuilders.AnimationSpec
import androidx.wear.protolayout.expression.AnimationParameterBuilders.Easing
import androidx.wear.protolayout.expression.AnimationParameterBuilders.REPEAT_MODE_RESTART
import androidx.wear.protolayout.expression.AnimationParameterBuilders.Repeatable
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicFloat
import com.ams.herculex.ui.HxPillColors
import com.ams.herculex.MainActivity

/**
 * Shared look for every Herculex tile. Mirrors the watch app, not Material:
 *  - OLED black, one soft domain glow (image resource, see res/drawable/hx_glow_*.xml)
 *  - bezel arc like FastingScreen (track + progress), notches for milestones
 *  - stadium pills with a round badge, same colours as `OneUiPillStyle`
 *  - motion = HxMotion.emphasized (easeOutCubic) on arcs, count-ups and stagger
 *
 * Sizes are dp on a 227dp round face (what FastingTileTest uses).
 */
object HxTile {
    // ── Palette: copied from OneUiPillStyle / FastingScreen ─────────
    fun c(argb: Long): ColorProp = ColorBuilders.argb(argb.toInt())
    val White = c(0xFFFFFFFF)
    val Muted = c(HxPillColors.SLATE_SECONDARY)
    val Black = c(0xFF000000)

    class PillStyle(val container: ColorProp, val badge: ColorProp, val secondary: ColorProp, val border: ColorProp? = null)
    val RoyalBlue = PillStyle(c(HxPillColors.ROYAL_CONTAINER), c(HxPillColors.ROYAL_BADGE), c(HxPillColors.ROYAL_SECONDARY))
    val SlateNavy = PillStyle(c(HxPillColors.SLATE_CONTAINER), c(HxPillColors.SLATE_BADGE), c(HxPillColors.SLATE_SECONDARY), c(HxPillColors.SLATE_BORDER))
    val Emerald   = PillStyle(c(HxPillColors.EMERALD_CONTAINER), c(HxPillColors.EMERALD_BADGE), c(HxPillColors.EMERALD_SECONDARY))
    val Violet    = PillStyle(c(0xFF32255C), c(0xFF211742), c(0xFFD1C4E9))
    val StartFast = PillStyle(c(0xFF0B6E4F), c(0xFF064632), c(HxPillColors.EMERALD_SECONDARY))
    val AccentBlue = PillStyle(c(HxPillColors.ACCENT_CONTAINER), c(HxPillColors.ACCENT_BADGE), c(HxPillColors.ACCENT_SECONDARY))

    /** Domain accents → ring / label colours. */
    class Domain(val accent: ColorProp, val track: ColorProp, val label: ColorProp, val glowRes: String)
    val Fasting = Domain(c(0xFF64D2FF), c(0xFF241B3D), c(0xFFD1C4E9), "hx_glow_fasting")
    val Macros  = Domain(c(0xFF42A5F5), c(0xFF14263D), c(0xFF80C4FA), "hx_glow_macros")
    val Water   = Domain(c(0xFF80DEEA), c(0xFF10303A), c(0xFF80DEEA), "hx_glow_water")
    val Volume  = Domain(c(0xFF42A5F5), c(HxPillColors.SLATE_BADGE), c(0xFF9DB4F2), "hx_glow_volume")
    val Workout = Domain(c(0xFF42A5F5), c(HxPillColors.SLATE_BADGE), c(0xFF42A5F5), "hx_glow_workout")

    const val RING_DP = 7.5f

    // ── Motion ──────────────────────────────────────────────────────
    private val emphasized = Easing.cubicBezier(0.215f, 0.61f, 0.355f, 1f)

    fun spec(ms: Int, delayMs: Int = 0): AnimationSpec =
        AnimationSpec.Builder().setAnimationParameters(
            AnimationParameters.Builder().setDurationMillis(ms.toLong()).setDelayMillis(delayMs.toLong()).setEasing(emphasized).build()
        ).build()

    /** Static value is the END state, so hosts without animation support still draw a correct tile. */
    fun animDegrees(from: Float, to: Float, delayMs: Int = 0, ms: Int = 1100): DegreesProp =
        DegreesProp.Builder(to).setDynamicValue(DynamicFloat.animate(from, to, spec(ms, delayMs))).build()

    /**
     * Fade + 12dp slide-up, staggered by [index] (0 = label … 4 = CTA).
     * ProtoLayout's FixedQuotaManagerImpl caps concurrent running animators at 4;
     * keeping duration (130ms) < step (140ms) ensures at most 2 animators run at
     * once for [enter], leaving 2 quota slots free for arc/count-up/shimmer.
     */
    fun LayoutElement.enter(index: Int): LayoutElement {
        val delay = index * 140
        return LayoutElementBuilders.Box.Builder()
            .addContent(this)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setOpacity(floatProp(0f, 1f, delay, 130))
                    .setTransformation(
                        ModifiersBuilders.Transformation.Builder()
                            .setTranslationY(
                                DpProp.Builder(0f)
                                    .setDynamicValue(DynamicFloat.animate(12f, 0f, spec(130, delay)))
                                    .build()
                            ).build()
                    ).build()
            ).build()
    }

    private fun floatProp(from: Float, to: Float, delayMs: Int, ms: Int) =
        androidx.wear.protolayout.TypeBuilders.FloatProp.Builder(to)
            .setDynamicValue(DynamicFloat.animate(from, to, spec(ms, delayMs)))
            .build()

    // ── Structure ───────────────────────────────────────────────────

    /** Black face: glow image, bezel layers, then centred content. */
    fun face(
        glowId: String, bezel: List<LayoutElement>, content: LayoutElement,
        /** Non-null pins [content] to the top of the face with this much padding (dp). */
        topInset: Float? = null,
    ): LayoutElement {
        val box = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand()).setHeight(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(
                LayoutElementBuilders.Image.Builder().setResourceId(glowId)
                    .setWidth(DimensionBuilders.expand()).setHeight(DimensionBuilders.expand())
                    .setContentScaleMode(LayoutElementBuilders.CONTENT_SCALE_MODE_FILL_BOUNDS).build()
            )
        bezel.forEach { box.addContent(it) }
        if (topInset == null) return box.addContent(content).build()
        return box.addContent(
            LayoutElementBuilders.Box.Builder()
                .setWidth(DimensionBuilders.expand()).setHeight(DimensionBuilders.expand())
                .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_TOP)
                .setModifiers(
                    ModifiersBuilders.Modifiers.Builder().setPadding(
                        ModifiersBuilders.Padding.Builder().setTop(DimensionBuilders.dp(topInset)).build()
                    ).build()
                )
                .addContent(content).build()
        ).build()
    }

    /**
     * One ArcLine. An animated [sweep] is a *dynamic* length, and ProtoLayout refuses to
     * build one without layout constraints ("length with dynamic value requires
     * layoutConstraintsForDynamicLength") — which made every animated tile throw and
     * show nothing. The constraint is the widest the line can ever get: a full circle.
     */
    fun arcLine(color: ColorProp, sweep: DegreesProp): LayoutElementBuilders.ArcLine =
        LayoutElementBuilders.ArcLine.Builder()
            .setLength(sweep).setColor(color).setThickness(DimensionBuilders.dp(RING_DP))
            .setLayoutConstraintsForDynamicLength(
                DimensionBuilders.AngularLayoutConstraint.Builder(360f)
                    .setAngularAlignment(LayoutElementBuilders.ANGULAR_ALIGNMENT_START).build()
            )
            // protolayout 1.3: .setStrokeCap(LayoutElementBuilders.STROKE_CAP_ROUND)
            .build()

    /** One bezel arc from 12 o'clock, clockwise. [sweep] may be animated. */
    fun arc(color: ColorProp, sweep: DegreesProp, startAngle: Float = 0f): LayoutElement =
        LayoutElementBuilders.Arc.Builder()
            .setAnchorAngle(DimensionBuilders.degrees(startAngle))
            .setAnchorType(LayoutElementBuilders.ARC_ANCHOR_START)
            .addContent(arcLine(color, sweep)).build()

    fun track(color: ColorProp) = arc(color, DimensionBuilders.degrees(360f))

    /** Tiny black gap on the ring (milestones: 4 / 8 / 12 h). */
    fun notch(angle: Float) = arc(Black, DimensionBuilders.degrees(1.4f), angle - 0.7f)

    fun spacer(h: Float) = LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(h)).build()
    fun hSpacer(w: Float) = LayoutElementBuilders.Spacer.Builder().setWidth(DimensionBuilders.dp(w)).build()

    fun column(vararg items: LayoutElement) = LayoutElementBuilders.Column.Builder()
        .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
        .also { b -> items.forEach { b.addContent(it) } }.build()

    // ── Text (raw ProtoLayout text so we can use tabular figures) ───
    fun text(
        s: String, sp: Float, color: ColorProp, bold: Boolean = false,
        tabular: Boolean = false, caps: Boolean = false, maxLines: Int = 1,
    ): LayoutElement = LayoutElementBuilders.Text.Builder()
        .setText(if (caps) s.uppercase() else s)
        .setMaxLines(maxLines)
        .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
        .setFontStyle(
            LayoutElementBuilders.FontStyle.Builder()
                .setSize(DimensionBuilders.sp(sp)).setColor(color)
                .setWeight(if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL)
                .also { if (tabular) it.setSettings(LayoutElementBuilders.FontSetting.tabularNum()) }
                .also { if (caps) it.setLetterSpacing(DimensionBuilders.em(0.1f)) }
                .build()
        ).build()

    /** "98" in [color] followed by a smaller muted [unit], e.g. 98g, in one text node. */
    fun valueWithUnit(
        value: String, unit: String, valueSp: Float, unitSp: Float,
        valueColor: ColorProp, unitColor: ColorProp,
    ): LayoutElement {
        fun style(sp: Float, color: ColorProp, bold: Boolean) = LayoutElementBuilders.FontStyle.Builder()
            .setSize(DimensionBuilders.sp(sp)).setColor(color)
            .setWeight(if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL)
            .build()
        return LayoutElementBuilders.Spannable.Builder()
            .addSpan(LayoutElementBuilders.SpanText.Builder().setText(value).setFontStyle(style(valueSp, valueColor, true)).build())
            .addSpan(LayoutElementBuilders.SpanText.Builder().setText(unit).setFontStyle(style(unitSp, unitColor, true)).build())
            .setMaxLines(1)
            .build()
    }

    fun icon(id: String, size: Float, tint: ColorProp): LayoutElement =
        LayoutElementBuilders.Image.Builder().setResourceId(id)
            .setWidth(DimensionBuilders.dp(size)).setHeight(DimensionBuilders.dp(size))
            .setColorFilter(LayoutElementBuilders.ColorFilter.Builder().setTint(tint).build()).build()

    /** Icon + caps label, e.g. flame + TODAY. */
    fun label(iconId: String, s: String, color: ColorProp): LayoutElement =
        LayoutElementBuilders.Row.Builder()
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(icon(iconId, 12f, color)).addContent(hSpacer(4f))
            .addContent(text(s, 10f, color, bold = true, caps = true)).build()

    /** Number that counts 0 → [target] on show. Exact formatter class names: verify against protolayout 1.2. */
    fun countUp(target: Int, sp: Float, color: ColorProp, delayMs: Int = 260, maxChars: String = "0,000"): LayoutElement =
        LayoutElementBuilders.Text.Builder()
            .setText(
                androidx.wear.protolayout.TypeBuilders.StringProp.Builder("%,d".format(target))
                    .setDynamicValue(
                        androidx.wear.protolayout.expression.DynamicBuilders.DynamicInt32
                            .animate(0, target, spec(900, delayMs))
                            .format(
                                androidx.wear.protolayout.expression.DynamicBuilders.DynamicInt32.IntFormatter.Builder()
                                    .setGroupingUsed(true).build()
                            )
                    ).build()
            )
            .setLayoutConstraintsForDynamicText(
                androidx.wear.protolayout.TypeBuilders.StringLayoutConstraint.Builder(maxChars)
                    .setAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER).build()
            )
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder().setSize(DimensionBuilders.sp(sp)).setColor(color)
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                    .setSettings(LayoutElementBuilders.FontSetting.tabularNum()).build()
            ).build()

    // ── Pill (same anatomy as OneUiPill) ────────────────────────────
    fun pill(
        width: Float, height: Float, style: PillStyle, iconId: String, title: String,
        subtitle: String? = null, trailing: Boolean = false, clickable: ModifiersBuilders.Clickable,
        shimmer: Boolean = false,
    ): LayoutElement {
        // Design (330px -> 227dp):
        //   wkBig:   258x72px (177.5x50dp), badge 52px (36dp = height - 14dp), icon 28px (19.5dp), pad 10/16px (7/11dp), gap 11px (7.5dp)
        //   wkSmall: 244x52px (168x36dp),   badge 40px (28dp = height - 8dp),  icon 24px (16.5dp), pad 6/12px  (4/8dp),  gap 9px  (6.5dp)
        val isBig = height >= 48f
        val badge = if (isBig) height - 14f else height - 8f
        val iconSize = if (isBig) badge * 0.54f else badge * 0.6f
        val padStart = if (isBig) 7f else 4f
        val padEnd = if (isBig) 11f else 8f
        val gap = if (isBig) 7.5f else 6.5f
        val textW = width - padStart - badge - gap - (if (trailing) 26f else padEnd)
        val badgeBox = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(badge)).setHeight(DimensionBuilders.dp(badge))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder().setBackground(
                    ModifiersBuilders.Background.Builder().setColor(style.badge)
                        .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(badge / 2)).build()).build()
                ).build()
            ).addContent(icon(iconId, iconSize, White)).build()
        val texts = LayoutElementBuilders.Column.Builder().setWidth(DimensionBuilders.dp(textW))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
            .addContent(text(title, if (isBig) 13f else 12f, White, bold = true))
            .also { if (subtitle != null) it.addContent(text(subtitle, 10f, style.secondary)) }.build()
        val row = LayoutElementBuilders.Row.Builder()
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder().setPadding(
                    ModifiersBuilders.Padding.Builder()
                        .setStart(DimensionBuilders.dp(padStart))
                        .setEnd(DimensionBuilders.dp(padEnd)).build()
                ).build()
            )
            .addContent(badgeBox).addContent(hSpacer(gap)).addContent(texts)
            .also { if (trailing) it.addContent(icon("ic_hx_chevron", 14f, style.secondary)) }.build()
        val mods = ModifiersBuilders.Modifiers.Builder()
            .setBackground(
                ModifiersBuilders.Background.Builder().setColor(style.container)
                    .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(height / 2)).build()).build()
            )
            .setClickable(clickable)
        style.border?.let {
            mods.setBorder(ModifiersBuilders.Border.Builder().setWidth(DimensionBuilders.dp(1f)).setColor(it).build())
        }
        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(width)).setHeight(DimensionBuilders.dp(height))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(mods.build())
            .addContent(row)
            .also { if (shimmer) it.addContent(shimmerSweep(width, height)) }
            .build()
    }

    /**
     * Shimmer band (`wkShimmer` in Claude Design) that sweeps across the primary
     * workout pill over 1350ms (`0.26 * 5200ms`) and repeats every 5200ms.
     * Using an infinite [Repeatable] ensures Wear OS's `AnimatableNode` starts/resumes
     * the sweep whenever the user swipes onto the tile in the carousel.
     */
    private fun shimmerSweep(width: Float, height: Float): LayoutElement {
        val shimmerSpec = AnimationSpec.Builder()
            .setAnimationParameters(
                AnimationParameters.Builder()
                    .setDurationMillis(1350L)
                    .setDelayMillis(200L)
                    .setEasing(emphasized)
                    .build()
            )
            .setRepeatable(
                Repeatable.Builder()
                    .setRepeatMode(REPEAT_MODE_RESTART)
                    .setForwardRepeatOverride(
                        AnimationParameters.Builder()
                            .setDurationMillis(1350L)
                            .setDelayMillis(3850L)
                            .setEasing(emphasized)
                            .build()
                    )
                    .build()
            )
            .build()
        return LayoutElementBuilders.Image.Builder()
            .setResourceId("hx_pill_shimmer")
            .setWidth(DimensionBuilders.dp(44f))
            .setHeight(DimensionBuilders.dp(height))
            .setContentScaleMode(LayoutElementBuilders.CONTENT_SCALE_MODE_FILL_BOUNDS)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setTransformation(
                        ModifiersBuilders.Transformation.Builder()
                            .setTranslationX(
                                DpProp.Builder(-56f)
                                    .setDynamicValue(DynamicFloat.animate(-56f, width + 16f, shimmerSpec))
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .build()
    }

    // ── Actions ─────────────────────────────────────────────────────
    fun launch(context: Context, id: String, route: String) = ModifiersBuilders.Clickable.Builder()
        .setId(id)
        .setOnClick(
            ActionBuilders.LaunchAction.Builder().setAndroidActivity(
                ActionBuilders.AndroidActivity.Builder()
                    .setPackageName(context.packageName)
                    .setClassName(MainActivity::class.java.name)
                    .addKeyToExtraMapping("route", ActionBuilders.stringExtra(route)).build()
            ).build()
        ).build()

    /** Runs inside the tile (no app launch): arrives in tileRequest as `currentState.lastClickableId`. */
    fun load(id: String) = ModifiersBuilders.Clickable.Builder()
        .setId(id).setOnClick(ActionBuilders.LoadAction.Builder().build()).build()
}
