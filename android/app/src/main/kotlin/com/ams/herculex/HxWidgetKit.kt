package com.ams.herculex

import android.content.res.AssetManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import java.io.File
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

// Drawing kit for the Herculex home-screen widgets.
//
// RemoteViews can't tint gradients, mix theme colours with alpha or use the
// app's variable fonts before API 31, so every widget is drawn onto a single
// bitmap at its real size. Coordinates are in dp; [HxCanvas] scales to px.

/** The app's two typefaces, read straight from the Flutter asset bundle. */
class HxFonts private constructor(private val load: (Family, Int) -> Typeface) {

    enum class Family(val file: String) {
        MANROPE("Manrope-Variable.ttf"),
        SPACE_GROTESK("SpaceGrotesk-Variable.ttf"),
    }

    private val cache = HashMap<Pair<Family, Int>, Typeface>()

    fun get(family: Family, weight: Int): Typeface =
        cache.getOrPut(family to weight) {
            try {
                load(family, weight)
            } catch (_: Exception) {
                Typeface.create(Typeface.DEFAULT, weight, false)
            }
        }

    companion object {
        private const val FLUTTER_FONT_DIR = "flutter_assets/assets/fonts/"

        @Volatile private var shared: HxFonts? = null

        fun fromAssets(assets: AssetManager): HxFonts =
            shared ?: HxFonts { family, weight ->
                Typeface.Builder(assets, FLUTTER_FONT_DIR + family.file)
                    .setFontVariationSettings("'wght' $weight")
                    .build()
            }.also { shared = it }

        fun fromDirectory(dir: File): HxFonts = HxFonts { family, weight ->
            Typeface.Builder(File(dir, family.file))
                .setFontVariationSettings("'wght' $weight")
                .build()
        }
    }
}

data class HxTextStyle(
    val family: HxFonts.Family,
    val size: Float,
    val weight: Int,
    val color: Int,
    /** CSS letter-spacing, in dp. */
    val tracking: Float = 0f,
    val tabular: Boolean = false,
) {
    fun withColor(c: Int) = copy(color = c)
}

/** Material Symbols Rounded (400, 24 opsz) outlines, viewBox `0 -960 960 960`. */
enum class HxIcon(val pathData: String) {
    SEARCH("M378-329q-108.16 0-183.08-75Q120-479 120-585t75-181q75-75 181.5-75t181 75Q632-691 632-584.85 632-542 618-502q-14 40-42 75l242 240q9 8.56 9 21.78T818-143q-9 9-22.22 9-13.22 0-21.78-9L533-384q-30 26-69.96 40.5Q423.08-329 378-329Zm-1-60q81.25 0 138.13-57.5Q572-504 572-585t-56.87-138.5Q458.25-781 377-781q-82.08 0-139.54 57.5Q180-666 180-585t57.46 138.5Q294.92-389 377-389Z"),
    BARCODE_SCANNER("M213.38-128.5Q204.75-120 192-120H70q-12.75 0-21.37-8.63Q40-137.25 40-150v-122q0-12.75 8.68-21.38 8.67-8.62 21.5-8.62 12.82 0 21.32 8.62 8.5 8.63 8.5 21.38v92h92q12.75 0 21.38 8.68 8.62 8.67 8.62 21.5 0 12.82-8.62 21.32ZM910.5-293.38q8.5 8.63 8.5 21.38v122q0 12.75-8.62 21.37Q901.75-120 889-120H767q-12.75 0-21.37-8.68-8.63-8.67-8.63-21.5 0-12.82 8.63-21.32 8.62-8.5 21.37-8.5h92v-92q0-12.75 8.68-21.38 8.67-8.62 21.5-8.62 12.82 0 21.32 8.62ZM168-231q-6 0-10.5-4.5T153-246v-469q0-6 4.5-10.5T168-730h50q6 0 10.5 4.5T233-715v469q0 6-4.5 10.5T218-231h-50Zm112-6.24q-6-6.24-6-14.55v-457.42q0-8.32 6-14.55 6-6.24 15-6.24t15 6.24q6 6.23 6 14.55v457.42q0 8.31-6 14.55T295-231q-9 0-15-6.24ZM411-231q-6 0-10.5-4.5T396-246v-469q0-6 4.5-10.5T411-730h53q6 0 10.5 4.5T479-715v469q0 6-4.5 10.5T464-231h-53Zm125 0q-6 0-10.5-4.5T521-246v-469q0-6 4.5-10.5T536-730h91q6 0 10.5 4.5T642-715v469q0 6-4.5 10.5T627-231h-91Zm154-6.24q-6-6.24-6-14.55v-457.42q0-8.32 6-14.55 6-6.24 15-6.24t15 6.24q6 6.23 6 14.55v457.42q0 8.31-6 14.55T705-231q-9 0-15-6.24Zm82.5.54q-5.5-5.7-5.5-13.3v-460.63q0-8.37 5.7-13.87T786-730q7.6 0 13.3 5.7 5.7 5.7 5.7 13.3v460.62q0 8.38-5.5 13.88T786-231q-8 0-13.5-5.7ZM213.38-788.5Q204.75-780 192-780h-92v92q0 12.75-8.68 21.37-8.67 8.63-21.5 8.63-12.82 0-21.32-8.63Q40-675.25 40-688v-122q0-12.75 8.63-21.38Q57.25-840 70-840h122q12.75 0 21.38 8.68 8.62 8.67 8.62 21.5 0 12.82-8.62 21.32Zm532.25-43q8.62-8.5 21.37-8.5h122q12.75 0 21.38 8.62Q919-822.75 919-810v122q0 12.75-8.68 21.37-8.67 8.63-21.5 8.63-12.82 0-21.32-8.63-8.5-8.62-8.5-21.37v-92h-92q-12.75 0-21.37-8.68-8.63-8.67-8.63-21.5 0-12.82 8.63-21.32Z"),
    FIRE_FILLED("M160-400q0-116 71.5-225T428-811q17-11 34.5-.5T480-780v72q0 34 23.5 57t57.5 23q18 0 33.5-7.5T622-658q8-9 18-12.5t19 2.5q66 45 103.5 116T800-400q0 95-49 171.5T622-113q23-26 35.5-58t12.5-67q0-38-14-71.5T615-370L480-502 346-370q-28 27-42 60.5T290-238q0 35 12.5 67t35.5 58q-80-39-129-115.5T160-400Zm320-18 92 90q18 18 28 41t10 49q0 53-38 90.5T480-110q-54 0-92-37.5T350-238q0-26 9.5-49t28.5-41l92-90Z"),
    WARNING_FILLED("M92-120q-9 0-15.5-4T66-135q-4-7-4.5-14.5T66-165l388-670q5-8 11.5-11.5T480-850q8 0 14.5 3.5T506-835l388 670q5 8 4.5 15.5T894-135q-4 7-10.5 11t-15.5 4H92Zm413.5-125.5Q514-254 514-267t-8.5-21.5Q497-297 484-297t-21.5 8.5Q454-280 454-267t8.5 21.5Q471-237 484-237t21.5-8.5Zm0-111Q514-365 514-378v-164q0-13-8.5-21.5T484-572q-13 0-21.5 8.5T454-542v164q0 13 8.5 21.5T484-348q13 0 21.5-8.5Z"),
    RESTAURANT("M285-600v-250q0-12.75 8.68-21.38 8.67-8.62 21.5-8.62 12.82 0 21.32 8.62 8.5 8.63 8.5 21.38v250h65v-250q0-12.75 8.68-21.38 8.67-8.62 21.5-8.62 12.82 0 21.32 8.62 8.5 8.63 8.5 21.38v249.73q0 58.27-36.5 99.77Q397-459 345-448v338q0 12.75-8.68 21.37-8.67 8.63-21.5 8.63-12.82 0-21.32-8.63Q285-97.25 285-110v-338q-52-11-88.5-52.5T160-600.27V-850q0-12.75 8.68-21.38 8.67-8.62 21.5-8.62 12.82 0 21.32 8.62 8.5 8.63 8.5 21.38v250h65Zm415 200h-85q-12.75 0-21.37-8.63Q585-417.25 585-430v-275q0-69 42.5-122t98.5-53q14 0 24 10.13T760-846v736q0 12.75-8.68 21.37-8.67 8.63-21.5 8.63-12.82 0-21.32-8.63Q700-97.25 700-110v-290Z"),
    DIRECTIONS_RUN("M535-70v-209l-108-99-36 159q-3 12-13 18.5t-22 4.5l-208-43q-11-2-18-12t-5-22q2-12 12.5-18t21.5-4l171 34 73-369-100 47v104q0 13-8.5 21.5T273-449q-13 0-21.5-8.5T243-479v-125q0-9 5-16.5t13-11.5l146-61q32-14 45.5-17.5T480-714q20 0 35.5 8.5T542-680l42 67q23 37 60 65.5t86 36.5q13 2 21.5 10.5T760-479q0 12-8.5 21t-20.5 7q-57-6-102.5-36.5T543-573l-39 158 81 75q5 5 7.5 10.5T595-318v248q0 13-8.5 21.5T565-40q-13 0-21.5-8.5T535-70Zm-46.5-705.5Q467-797 467-827t21.5-51.5Q510-900 540-900t51.5 21.5Q613-857 613-827t-21.5 51.5Q570-754 540-754t-51.5-21.5Z"),
    BATTERY_CHARGING_FILLED("M660-200h-53q-9.39 0-13.7-7.5-4.3-7.5.7-15.5l92-147q3-5 8.5-3.5t5.5 7.5v86h53q9.39 0 13.7 7.5 4.3 7.5-.7 15.5l-92 148q-3 5-8.5 3.5T660-113v-87ZM310-80q-12.75 0-21.37-8.63Q280-97.25 280-110v-676q0-12.75 8.63-21.38Q297.25-816 310-816h90v-34q0-12.75 8.63-21.38Q417.25-880 430-880h100q12.75 0 21.38 8.62Q560-862.75 560-850v34h90q12.75 0 21.38 8.62Q680-798.75 680-786v313q0 7.97-5.93 13.76-5.92 5.79-14.07 7.24-38 4-71 20.03-33 16.02-58.67 41.66Q501-361 484-322.54q-17 38.45-17 83.54 0 35 11 66.5t30 57.5q8 11 2.5 23T492-80H310Z"),
    BOLT_FILLED("M360-360H217q-18 0-26.5-16t2.5-31l338-488q8-11 20-15t24 1q12 5 19 16t5 24l-39 309h176q19 0 27 17t-4 32L388-66q-8 10-20.5 13T344-55q-11-5-17.5-16T322-95l38-265Z");

    internal val path: Path by lazy { SvgPath.parse(pathData) }
}

/** Minimal SVG path-data parser (M L H V C S Q T Z, absolute and relative). */
internal object SvgPath {
    fun parse(d: String): Path {
        val path = Path()
        val tokens = tokenize(d)
        var i = 0
        var cmd = 'M'
        var x = 0f; var y = 0f
        var startX = 0f; var startY = 0f
        var ctrlX = 0f; var ctrlY = 0f
        var prev = ' '
        fun num(): Float = (tokens[i++] as Float)
        while (i < tokens.size) {
            val t = tokens[i]
            if (t is Char) { cmd = t; i++ }
            val rel = cmd.isLowerCase()
            val ox = if (rel) x else 0f
            val oy = if (rel) y else 0f
            when (cmd.uppercaseChar()) {
                'M' -> {
                    x = ox + num(); y = oy + num()
                    path.moveTo(x, y); startX = x; startY = y
                    // Subsequent pairs after a moveto are implicit linetos.
                    cmd = if (rel) 'l' else 'L'
                }
                'L' -> { x = ox + num(); y = oy + num(); path.lineTo(x, y) }
                'H' -> { x = ox + num(); path.lineTo(x, y) }
                'V' -> { y = oy + num(); path.lineTo(x, y) }
                'C' -> {
                    val x1 = ox + num(); val y1 = oy + num()
                    ctrlX = ox + num(); ctrlY = oy + num()
                    x = ox + num(); y = oy + num()
                    path.cubicTo(x1, y1, ctrlX, ctrlY, x, y)
                }
                'S' -> {
                    val (x1, y1) = if (prev.uppercaseChar() in "CS") (2 * x - ctrlX) to (2 * y - ctrlY) else x to y
                    ctrlX = ox + num(); ctrlY = oy + num()
                    x = ox + num(); y = oy + num()
                    path.cubicTo(x1, y1, ctrlX, ctrlY, x, y)
                }
                'Q' -> {
                    ctrlX = ox + num(); ctrlY = oy + num()
                    x = ox + num(); y = oy + num()
                    path.quadTo(ctrlX, ctrlY, x, y)
                }
                'T' -> {
                    if (prev.uppercaseChar() in "QT") { ctrlX = 2 * x - ctrlX; ctrlY = 2 * y - ctrlY } else { ctrlX = x; ctrlY = y }
                    x = ox + num(); y = oy + num()
                    path.quadTo(ctrlX, ctrlY, x, y)
                }
                'Z' -> { path.close(); x = startX; y = startY }
                else -> throw IllegalArgumentException("Unsupported path command $cmd")
            }
            prev = cmd
        }
        return path
    }

    private fun tokenize(d: String): List<Any> {
        val out = ArrayList<Any>()
        var i = 0
        while (i < d.length) {
            val c = d[i]
            when {
                c.isLetter() -> { out.add(c); i++ }
                c == '-' || c == '.' || c.isDigit() -> {
                    val start = i
                    i++
                    var seenDot = c == '.'
                    while (i < d.length) {
                        val n = d[i]
                        if (n.isDigit()) i++
                        else if (n == '.' && !seenDot) { seenDot = true; i++ }
                        else break
                    }
                    out.add(d.substring(start, i).toFloat())
                }
                else -> i++
            }
        }
        return out
    }
}

/** CSS `color-mix(in srgb, a p, b)`. */
fun mix(a: Int, b: Int, p: Float): Int {
    fun ch(shift: Int) = (((a ushr shift) and 0xFF) * p + ((b ushr shift) and 0xFF) * (1 - p) + 0.5f).toInt()
    return (ch(24) shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
}

/** CSS `color-mix(in srgb, a p, transparent)`. */
fun alpha(a: Int, p: Float): Int = (a and 0x00FFFFFF) or ((Color.alpha(a) * p + 0.5f).toInt() shl 24)

class HxCanvas(val canvas: Canvas, val fonts: HxFonts) {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val rect = RectF()
    private val matrix = Matrix()
    private val iconPath = Path()

    private fun apply(style: HxTextStyle): TextPaint = text.apply {
        typeface = fonts.get(style.family, style.weight)
        textSize = style.size
        color = style.color
        letterSpacing = if (style.size > 0) style.tracking / style.size else 0f
        fontFeatureSettings = if (style.tabular) "'tnum'" else null
    }

    fun width(s: String, style: HxTextStyle): Float = apply(style).measureText(s)

    /** Ascent of the style's font, as a positive number. */
    fun ascent(style: HxTextStyle): Float = -apply(style).fontMetrics.ascent

    fun descent(style: HxTextStyle): Float = apply(style).fontMetrics.descent

    /** CSS `line-height: normal` for this style. */
    fun lineHeight(style: HxTextStyle): Float = ascent(style) + descent(style)

    /** Baseline of a line box of [lineHeight] (default `normal`) starting at [top]. */
    fun baseline(top: Float, style: HxTextStyle, lineHeight: Float = lineHeight(style)): Float {
        val a = ascent(style)
        val content = a + descent(style)
        return top + (lineHeight - content) / 2f + a
    }

    fun text(
        s: String,
        x: Float,
        baseline: Float,
        style: HxTextStyle,
        align: Paint.Align = Paint.Align.LEFT,
        maxWidth: Float = Float.MAX_VALUE,
    ): Float {
        val p = apply(style)
        p.textAlign = align
        val shown = if (p.measureText(s) > maxWidth) {
            TextUtils.ellipsize(s, p, maxWidth, TextUtils.TruncateAt.END).toString()
        } else {
            s
        }
        canvas.drawText(shown, x, baseline, p)
        p.textAlign = Paint.Align.LEFT
        return p.measureText(shown)
    }

    fun roundRect(l: Float, t: Float, r: Float, b: Float, radius: Float, color: Int) {
        if (Color.alpha(color) == 0) return
        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = color
        rect.set(l, t, r, b)
        canvas.drawRoundRect(rect, radius, radius, fill)
    }

    fun circle(cx: Float, cy: Float, radius: Float, color: Int) {
        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = color
        canvas.drawCircle(cx, cy, radius, fill)
    }

    /** A fully rounded progress bar, as the app's `LinearProgressIndicator`s. */
    fun bar(l: Float, t: Float, w: Float, h: Float, fraction: Float, track: Int, color: Int, radius: Float = h / 2f) {
        roundRect(l, t, l + w, t + h, radius, track)
        val f = fraction.coerceIn(0f, 1f)
        if (f <= 0f) return
        canvas.save()
        rect.set(l, t, l + w, t + h)
        val clip = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }
        canvas.clipPath(clip)
        roundRect(l, t, l + w * f, t + h, radius, color)
        canvas.restore()
    }

    /** Circular gauge stroke: [sweep] degrees of track, [fraction] of it filled. */
    fun ring(
        cx: Float, cy: Float, radius: Float, stroke: Float,
        startAngle: Float, sweep: Float, fraction: Float,
        track: Int, color: Int, roundTrack: Boolean,
    ) {
        fill.shader = null
        fill.style = Paint.Style.STROKE
        fill.strokeWidth = stroke
        rect.set(cx - radius, cy - radius, cx + radius, cy + radius)
        fill.strokeCap = if (roundTrack) Paint.Cap.ROUND else Paint.Cap.BUTT
        fill.color = track
        canvas.drawArc(rect, startAngle, sweep, false, fill)
        val f = fraction.coerceIn(0f, 1f)
        if (f > 0f) {
            fill.strokeCap = Paint.Cap.ROUND
            fill.color = color
            canvas.drawArc(rect, startAngle, sweep * f, false, fill)
        }
        fill.style = Paint.Style.FILL
        fill.strokeCap = Paint.Cap.BUTT
    }

    fun icon(icon: HxIcon, cx: Float, cy: Float, size: Float, color: Int) {
        val s = size / 960f
        matrix.reset()
        matrix.setScale(s, s)
        matrix.postTranslate(cx - size / 2f, cy + size / 2f)
        icon.path.transform(matrix, iconPath)
        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = color
        canvas.drawPath(iconPath, fill)
    }

    /** A filled circle with a centred icon — the app's tinted icon chips. */
    fun iconChip(icon: HxIcon, cx: Float, cy: Float, diameter: Float, iconSize: Float, bg: Int, color: Int) {
        circle(cx, cy, diameter / 2f, bg)
        icon(icon, cx, cy, iconSize, color)
    }

    /**
     * A pill badge whose right edge sits at [right] and is vertically centred on
     * [cy]. Returns its width.
     */
    fun badge(
        label: String, right: Float, cy: Float, style: HxTextStyle,
        bg: Int, padH: Float, padV: Float, radius: Float = 999f,
    ): Float {
        val w = width(label, style) + padH * 2
        val h = lineHeight(style) + padV * 2
        roundRect(right - w, cy - h / 2, right, cy + h / 2, minOf(radius, h / 2), bg)
        text(label, right - w + padH, baseline(cy - h / 2 + padV, style), style)
        return w
    }

    /**
     * The `HxCard` surface: [accent]-tinted 135° gradient into the surface,
     * 30 % accent hairline, radius 28. A null accent draws the neutral card.
     */
    fun card(w: Float, h: Float, palette: HxWidgetPalette, accent: Int?) {
        rect.set(0f, 0f, w, h)
        fill.style = Paint.Style.FILL
        if (accent == null) {
            fill.shader = null
            fill.color = palette.surface
        } else {
            // CSS gradient-line geometry: corners land exactly on 0 % and 100 %.
            val a = Math.toRadians(135.0)
            val dx = sin(a).toFloat()
            val dy = -cos(a).toFloat()
            val half = (abs(w * dx) + abs(h * dy)) / 2f
            fill.shader = LinearGradient(
                w / 2f - dx * half, h / 2f - dy * half,
                w / 2f + dx * half, h / 2f + dy * half,
                mix(accent, palette.surface, palette.gradientAmount), palette.surface,
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRoundRect(rect, CARD_RADIUS, CARD_RADIUS, fill)
        fill.shader = null

        fill.style = Paint.Style.STROKE
        fill.strokeWidth = 1f
        fill.color = alpha(accent ?: palette.outlineVariant, 0.30f)
        rect.set(0.5f, 0.5f, w - 0.5f, h - 0.5f)
        canvas.drawRoundRect(rect, CARD_RADIUS - 0.5f, CARD_RADIUS - 0.5f, fill)
        fill.style = Paint.Style.FILL
    }

    companion object {
        const val CARD_RADIUS = 28f
    }
}
