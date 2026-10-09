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
import androidx.wear.protolayout.expression.AnimationParameterBuilders.CubicBezierEasing
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicFloat
import com.ams.herculex.MainActivity

/**
 * Shared look for every Herculex tile. Mirrors the watch app, not Material:
 *  - OLED black, one soft domain glow (image resource, see res/drawable/hx_glow_*.xml)
 *  - bezel arc like FastingScreen (track + progress), notches for milestones
 *  - stadium pills with a round badge, same colours as `OneUiPillStyle`
 *  - motion = HxMotion.emphasized (easeOutCubic) on arcs, count-ups and a 110 ms stagger
 *
 * Sizes are dp on a 227dp round face (what FastingTileTest uses).
 */
object HxTile {
    // ── Palette: copied from OneUiPillStyle / FastingScreen ─────────
    fun c(argb: Long): ColorProp = ColorBuilders.argb(argb.toInt())
    val White = c(0xFFFFFFFF)
    val Muted = c(0xFFA0AABF)
    val Black = c(0xFF000000)

    class PillStyle(val container: ColorProp, val badge: ColorProp, val secondary: ColorProp, val border: ColorProp? = null)
    val RoyalBlue = PillStyle(c(0xFF1E44AA), c(0xFF132E78), c(0xFFC0CCEC))
    val SlateNavy = PillStyle(c(0xFF202636), c(0xFF141926), c(0xFFA0AABF), c(0xFF323B52))
    val Emerald   = PillStyle(c(0xFF1B4D3E), c(0xFF113329), c(0xFFA5D6A7))
    val Violet    = PillStyle(c(0xFF32255C), c(0xFF211742), c(0xFFD1C4E9))
    val StartFast = PillStyle(c(0xFF0B6E4F), c(0xFF064632), c(0xFFA5D6A7))

    /** Domain accents → ring / label colours. */
    class Domain(val accent: ColorProp, val track: ColorProp, val label: ColorProp, val glowRes: String)
    val Fasting = Domain(c(0xFF64D2FF), c(0xFF241B3D), c(0xFFD1C4E9), "hx_glow_fasting")
    val Macros  = Domain(c(0xFF42A5F5), c(0xFF14263D), c(0xFF80C4FA), "hx_glow_macros")
    val Water   = Domain(c(0xFF80DEEA), c(0xFF10303A), c(0xFF80DEEA), "hx_glow_water")
    val Volume  = Domain(c(0xFF42A5F5), c(0xFF141926), c(0xFF9DB4F2), "hx_glow_volume")
    val Workout = Domain(c(0xFF42A5F5), c(0xFF141926), c(0xFF42A5F5), "hx_glow_workout")

    const val RING_DP = 7.5f

    // ── Motion ──────────────────────────────────────────────────────
    private val emphasized = CubicBezierEasing.Builder().setX1(0.215f).setY1(0.61f).setX2(0.355f).setY2(1f).build()

    fun spec(ms: Int, delayMs: Int = 0): AnimationSpec =
        AnimationSpec.Builder().setAnimationParameters(
            AnimationParameters.Builder().setDurationMillis(ms).setDelayMillis(delayMs).setEasing(emphasized).build()
        ).build()

    /** Static value is the END state, so hosts without animation support still draw a correct tile. */
    fun animDegrees(from: Float, to: Float, delayMs: Int = 0, ms: Int = 1100): DegreesProp =
        DegreesProp.Builder(to).setDynamicValue(DynamicFloat.animate(from, to, spec(ms, delayMs))).build()

    /** Fade + 12dp slide-up, staggered by [index] (0 = label … 4 = CTA). */
    fun LayoutElement.enter(index: Int): LayoutElement {
        val delay = 150 + index * 110
        return LayoutElementBuilders.Box.Builder()
            .addContent(this)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setOpacity(floatProp(0f, 1f, delay, 450))
                    .setTransformation(
                        ModifiersBuilders.Transformation.Builder()
                            .setTranslationY(
                                DpProp.Builder(0f)
                                    .setDynamicValue(DynamicFloat.animate(12f, 0f, spec(500, delay)))
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
    fun face(glowId: String, bezel: List<LayoutElement>, content: LayoutElement): LayoutElement {
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
        return box.addContent(content).build()
    }

    /** One bezel arc from 12 o'clock, clockwise. [sweep] may be animated. */
    fun arc(color: ColorProp, sweep: DegreesProp, startAngle: Float = 0f): LayoutElement =
        LayoutElementBuilders.Arc.Builder()
            .setAnchorAngle(DimensionBuilders.degrees(startAngle))
            .setAnchorType(LayoutElementBuilders.ARC_ANCHOR_START)
            .addContent(
                LayoutElementBuilders.ArcLine.Builder()
                    .setLength(sweep).setColor(color).setThickness(DimensionBuilders.dp(RING_DP))
                    // protolayout 1.3: .setStrokeCap(LayoutElementBuilders.STROKE_CAP_ROUND)
                    .build()
            ).build()

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
                // tabular: FontSetting.tnum() needs a newer ProtoLayout than 1.2.1 — re-enable when bumped.
                .also { if (caps) it.setLetterSpacing(DimensionBuilders.em(0.1f)) }
                .build()
        ).build()

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
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD).build()
            ).build()

    // ── Pill (same anatomy as OneUiPill) ────────────────────────────
    fun pill(
        width: Float, height: Float, style: PillStyle, iconId: String, title: String,
        subtitle: String? = null, trailing: Boolean = false, clickable: ModifiersBuilders.Clickable,
    ): LayoutElement {
        val badge = height - 12f
        val textW = width - 5f - badge - 8f - (if (trailing) 26f else 12f)
        val badgeBox = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(badge)).setHeight(DimensionBuilders.dp(badge))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder().setBackground(
                    ModifiersBuilders.Background.Builder().setColor(style.badge)
                        .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(badge / 2)).build()).build()
                ).build()
            ).addContent(icon(iconId, badge * 0.6f, White)).build()
        val texts = LayoutElementBuilders.Column.Builder().setWidth(DimensionBuilders.dp(textW))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
            .addContent(text(title, if (height >= 44f) 13f else 12f, White, bold = true))
            .also { if (subtitle != null) it.addContent(text(subtitle, 10f, style.secondary)) }.build()
        val row = LayoutElementBuilders.Row.Builder()
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(badgeBox).addContent(hSpacer(8f)).addContent(texts)
            .also { if (trailing) it.addContent(icon("ic_hx_chevron", 14f, style.secondary)) }.build()
        val mods = ModifiersBuilders.Modifiers.Builder()
            .setBackground(
                ModifiersBuilders.Background.Builder().setColor(style.container)
                    .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(height / 2)).build()).build()
            )
            .setPadding(ModifiersBuilders.Padding.Builder().setStart(DimensionBuilders.dp(5f)).setEnd(DimensionBuilders.dp(8f)).build())
            .setClickable(clickable)
        style.border?.let {
            mods.setBorder(ModifiersBuilders.Border.Builder().setWidth(DimensionBuilders.dp(1f)).setColor(it).build())
        }
        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(width)).setHeight(DimensionBuilders.dp(height))
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(mods.build()).addContent(row).build()
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
