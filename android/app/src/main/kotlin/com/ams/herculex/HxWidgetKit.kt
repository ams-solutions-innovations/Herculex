package com.ams.herculex

import android.content.res.AssetManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
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
    val strike: Boolean = false,
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
    FITNESS_CENTER("M268-650 147-529q-9 9-21 9t-21-9q-8-8-8.5-20.5T104-571l36-37-35-35q-9-9-9-21t9-21l64-64-21-21q-9-9-9-21t9-21q8-8 20.5-8.5T190-813l22 21 63-63q9-9 21-9t21 9l35 35 37-36q9-8 21-8t21 9q9 9 9 21t-9 21L310-692l382 382 121-121q9-9 21-9t21 9q8 8 8.5 20.5T856-389l-36 37 35 35q9 9 9 21t-9 21l-65 65 21 21q9 9 9 21t-9 21q-9 9-21 9t-21-9l-21-21-63 63q-9 9-21 9t-21-9l-35-35-37 36q-9 8-21 8t-21-9q-9-9-9-21t9-21l121-121-382-382Z"),
    PLAY_FILLED("M320-258v-450q0-14 9-22t21-8q4 0 8 1t8 3l354 226q7 5 10.5 11t3.5 14q0 8-3.5 14T720-458L366-232q-4 2-8 3t-8 1q-12 0-21-8t-9-22Z"),
    ADD("M450-450H230q-12.75 0-21.37-8.68-8.63-8.67-8.63-21.5 0-12.82 8.63-21.32 8.62-8.5 21.37-8.5h220v-220q0-12.75 8.68-21.38 8.67-8.62 21.5-8.62 12.82 0 21.32 8.62 8.5 8.63 8.5 21.38v220h220q12.75 0 21.38 8.68 8.62 8.67 8.62 21.5 0 12.82-8.62 21.32-8.63 8.5-21.38 8.5H510v220q0 12.75-8.68 21.37-8.67 8.63-21.5 8.63-12.82 0-21.32-8.63-8.5-8.62-8.5-21.37v-220Z"),
    TROPHY("M450-180v-148q-54-11-96-46.5T296-463q-74-8-125-60t-51-125v-44q0-24.75 17.63-42.38Q155.25-752 180-752h104v-28q0-24.75 17.63-42.38Q319.25-840 344-840h272q24.75 0 42.38 17.62Q676-804.75 676-780v28h104q24.75 0 42.38 17.62Q840-716.75 840-692v44q0 73-51 125t-125 60q-16 53-58 88.5T510-328v148h122q12.75 0 21.38 8.68 8.62 8.67 8.62 21.5 0 12.82-8.62 21.32-8.63 8.5-21.38 8.5H328q-12.75 0-21.37-8.68-8.63-8.67-8.63-21.5 0-12.82 8.63-21.32 8.62-8.5 21.37-8.5h122ZM284-526v-166H180v44q0 45 29.5 78.5T284-526Zm292.5 101.04Q616-464.92 616-522v-258H344v258q0 57.08 39.74 97.04Q423.47-385 480.24-385q56.76 0 96.26-39.96ZM676-526q45-10 74.5-43.5T780-648v-44H676v166Zm-196-57Z"),
    BAR_CHART("M690-160q-12.75 0-21.37-8.63Q660-177.25 660-190v-220q0-12.75 8.63-21.38Q677.25-440 690-440h80q12.75 0 21.38 8.62Q800-422.75 800-410v220q0 12.75-8.62 21.37Q782.75-160 770-160h-80Zm-250 0q-12.75 0-21.37-8.63Q410-177.25 410-190v-580q0-12.75 8.63-21.38Q427.25-800 440-800h80q12.75 0 21.38 8.62Q550-782.75 550-770v580q0 12.75-8.62 21.37Q532.75-160 520-160h-80Zm-250 0q-12.75 0-21.37-8.63Q160-177.25 160-190v-380q0-12.75 8.63-21.38Q177.25-600 190-600h80q12.75 0 21.38 8.62Q300-582.75 300-570v380q0 12.75-8.62 21.37Q282.75-160 270-160h-80Z"),
    MEDICATION("M440-380v72q0 17 11.74 28 11.73 11 28.5 11Q497-269 508-280.67q11-11.66 11-28.33v-71h74q16.67 0 28.33-11.74Q633-403.47 633-420.24q0-16.76-11.67-28.26Q609.67-460 593-460h-74v-72q0-17-11-28t-27.76-11q-16.77 0-28.5 11Q440-549 440-532v72h-73q-16.67 0-28.33 11.74Q327-436.53 327-419.76q0 16.76 11.67 28.26Q350.33-380 367-380h73ZM260-120q-24.75 0-42.37-17.63Q200-155.25 200-180v-479q0-24.75 17.63-42.38Q235.25-719 260-719h440q24.75 0 42.38 17.62Q760-683.75 760-659v479q0 24.75-17.62 42.37Q724.75-120 700-120H260Zm0-60h440v-479H260v479Zm10-600q-12.75 0-21.37-8.68-8.63-8.67-8.63-21.5 0-12.82 8.63-21.32 8.62-8.5 21.37-8.5h421q12.75 0 21.38 8.68 8.62 8.67 8.62 21.5 0 12.82-8.62 21.32-8.63 8.5-21.38 8.5H270Zm-10 121v479-479Z"),
    CHECK("m378-332 363-363q9-9 21.5-9t21.5 9q9 9 9 21.5t-9 21.5L399-267q-9 9-21 9t-21-9L175-449q-9-9-8.5-21.5T176-492q9-9 21.5-9t21.5 9l159 160Z"),
    CHECK_BOX("m419-407-98-98q-9-9-21.5-8.5T278-504q-9 9-9 21.5t9 21.5l120 119q9 9 21 9t21-9l247-247q9-9 9-21.5t-9-21.5q-9-9-21.5-9t-21.5 9L419-407ZM180-120q-24 0-42-18t-18-42v-600q0-24 18-42t42-18h600q24 0 42 18t18 42v600q0 24-18 42t-42 18H180Zm0-60h600v-600H180v600Zm0-600v600-600Z"),
    CHEVRON_RIGHT("M530-481 353-658q-9-9-8.5-21t9.5-21q9-9 21.5-9t21.5 9l198 198q5 5 7 10t2 11q0 6-2 11t-7 10L396-261q-9 9-21 8.5t-21-9.5q-9-9-9-21.5t9-21.5l176-176Z"),
    WATER_DROP("M251.5-174Q160-268 160-408q0-64 29-127t72.5-121q43.5-58 94-108.5T450-854q7-6 14.5-8.5T480-865q8 0 15.5 2.5T510-854q44 39 94.5 89.5t94 108.5Q742-598 771-535t29 127q0 140-91.5 234T480-80q-137 0-228.5-94ZM666-216.5Q740-293 740-408q0-79-66.5-179.5T480-800Q353-688 286.5-587.5T220-408q0 115 74 191.5T480-140q112 0 186-76.5ZM480-480Zm-1 272q16 0 24.5-5.5T512-230q0-11-8.5-17t-25.5-6q-42 0-85.5-26.5T337-373q-2-9-9-14.5t-15-5.5q-11 0-17 8.5t-4 17.5q15 84 71 121.5T479-208Z"),
    BOLT("m393-165 279-335H492l36-286-253 366h154l-36 255Zm-33-195H217q-18 0-26.5-16t2.5-31l338-488q8-11 20-15t24 1q12 5 19 16t5 24l-39 309h176q19 0 27 17t-4 32L388-66q-8 10-20.5 13T344-55q-11-5-17.5-16T322-95l38-265Zm113-115Z"),
    FIRE("M253-173q-93-93-93-227 0-116 71.5-225T428-811q17-11 34.5-.5T480-780v72q0 34 23.5 57t57.5 23q18 0 33.5-7.5T622-658q8-9 18-12.5t19 2.5q66 45 103.5 116T800-400q0 134-93 227T480-80q-134 0-227-93Zm-33-227q0 63 28.5 118.5T328-189q-4-12-6-24.5t-2-24.5q0-32 12-60t35-51l113-111 113 111q23 23 35 51t12 60q0 12-2 24.5t-6 24.5q51-37 79.5-92.5T740-400q0-54-23-105.5T651-600q-21 15-44 23.5t-46 8.5q-61 0-101-41.5T420-714v-20q-92 66-146 156.5T220-400Zm260 24-71 70q-14 14-21.5 31t-7.5 37q0 41 29 69.5t71 28.5q42 0 71-28.5t29-69.5q0-20-7.5-37T551-306l-71-70Z"),
    SPA("M452-84q-69-12-136-47.5t-119.5-95Q144-286 112-370T80-565v-10q0-11 8.5-19.5T108-603h10q53 0 113 20.5T337-530q8-79 40-163.5T455-845q10-14 25-14t25 14q46 67 78 151.5T623-530q46-30 106-51.5T842-603h10q11 0 19.5 8.5T880-575v10q0 111-32 195t-84.5 143.5Q711-167 644-131.5T508-84q-11 2-28 2t-28-2Zm36-57q-11-185-108.5-281T141-542q-2 0 0 0 13 191 113 286.5T488-141q1 1-.5.5t.5-.5Zm-93-351q23 20 46.5 50t37.5 56q14-26 38.5-56t47.5-50q5-67-20.5-138T480-775q-1-1 0 0-40 75-65 145t-20 138Zm118 170q12 38 21 76.5t14 87.5q47-17 93-45.5t83.5-74.5q37.5-46 63-111T819-542q0-2 0 0-106 17-187 75.5T513-322Z"),
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
        isStrikeThruText = style.strike
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

    /**
     * Wrapped text, at most [maxLines] lines with an ellipsis, starting at
     * [top]. [lineHeight] is the CSS line-height in dp. Returns its height.
     */
    fun paragraph(
        s: String, x: Float, top: Float, width: Float, style: HxTextStyle,
        maxLines: Int, lineHeight: Float = lineHeight(style),
    ): Float {
        val p = TextPaint(apply(style))
        val layout = StaticLayout.Builder.obtain(s, 0, s.length, p, width.toInt().coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setIncludePad(false)
            .setLineSpacing(lineHeight - (ascent(style) + descent(style)), 1f)
            .build()
        canvas.save()
        // StaticLayout puts the extra spacing below each line; CSS splits it.
        canvas.translate(x, top + (lineHeight - (ascent(style) + descent(style))) / 2)
        layout.draw(canvas)
        canvas.restore()
        return layout.lineCount * lineHeight
    }

    /**
     * The dashboard's trend sparkline: area, dashed [target] line and a 2.5 dp
     * line, scaled to include the target with 15 % headroom.
     */
    fun sparkline(values: List<Float>, target: Float?, x: Float, y: Float, w: Float, h: Float, color: Int) {
        if (values.size < 2) return
        var lo = minOf(values.min(), target ?: values.min())
        var hi = maxOf(values.max(), target ?: values.max())
        val pad = ((hi - lo) * 0.15f).takeIf { it > 0f } ?: 1f
        lo -= pad
        hi += pad
        fun py(v: Float) = y + h - (v - lo) / (hi - lo) * h
        val line = Path()
        values.forEachIndexed { i, v ->
            val px = x + i * w / (values.size - 1)
            if (i == 0) line.moveTo(px, py(v)) else line.lineTo(px, py(v))
        }
        val area = Path(line).apply {
            lineTo(x + w, y + h)
            lineTo(x, y + h)
            close()
        }
        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = alpha(color, 0.15f)
        canvas.drawPath(area, fill)

        fill.style = Paint.Style.STROKE
        if (target != null) {
            fill.strokeWidth = 1.5f
            fill.color = alpha(color, 0.5f)
            fill.pathEffect = DashPathEffect(floatArrayOf(4f, 4f), 0f)
            canvas.drawLine(x, py(target), x + w, py(target), fill)
            fill.pathEffect = null
        }
        fill.strokeWidth = 2.5f
        fill.strokeCap = Paint.Cap.ROUND
        fill.strokeJoin = Paint.Join.ROUND
        fill.color = color
        canvas.drawPath(line, fill)
        fill.strokeCap = Paint.Cap.BUTT
        fill.strokeJoin = Paint.Join.MITER
        fill.style = Paint.Style.FILL
    }

    /** A ring outline, e.g. an unticked checkbox. */
    fun ringOutline(cx: Float, cy: Float, radius: Float, stroke: Float, color: Int) {
        fill.shader = null
        fill.style = Paint.Style.STROKE
        fill.strokeWidth = stroke
        fill.color = color
        canvas.drawCircle(cx, cy, radius - stroke / 2, fill)
        fill.style = Paint.Style.FILL
    }

    fun roundRect(l: Float, t: Float, r: Float, b: Float, radius: Float, color: Int) {
        if (Color.alpha(color) == 0) return
        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = color
        rect.set(l, t, r, b)
        canvas.drawRoundRect(rect, radius, radius, fill)
    }

    /** A 1 dp hairline round rect, inside the given bounds. */
    fun strokeRoundRect(l: Float, t: Float, r: Float, b: Float, radius: Float, color: Int) {
        fill.shader = null
        fill.style = Paint.Style.STROKE
        fill.strokeWidth = 1f
        fill.color = color
        rect.set(l + 0.5f, t + 0.5f, r - 0.5f, b - 0.5f)
        canvas.drawRoundRect(rect, radius - 0.5f, radius - 0.5f, fill)
        fill.style = Paint.Style.FILL
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
