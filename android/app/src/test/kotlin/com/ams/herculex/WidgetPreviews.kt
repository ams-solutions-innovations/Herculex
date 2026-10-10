package com.ams.herculex

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Bundle
import java.io.File

/**
 * Renders the widget-picker previews, `res/drawable-nodpi/widget_preview_*.png`,
 * which each `res/xml/widget_info_*.xml` points at with `android:previewImage`.
 *
 * The images are the real renderers ([HxWidgetRenderer]) run on demo data with
 * the app's fonts, so a redesigned widget is one command away from an honest
 * preview. They need a real Android graphics stack, which a JVM unit test does
 * not have (Robolectric's native graphics has no Windows runtime, and a bare
 * `app_process` has no system fonts), so `tool/widget_previews.ps1` packs this
 * and [PreviewRunner] into a throwaway APK and runs it on an emulator. It lives
 * in the test source set to stay out of the real APK.
 */
object WidgetPreviews {

    /** Cell sizes in dp, as the providers' `defaultSize`s. */
    private const val W2 = 182f
    private const val W4 = 364f
    private const val H1 = 80f
    private const val H2 = 176f

    /** xxhdpi: sharp in a picker on a phone without bloating the APK. */
    private const val DENSITY = 3f

    /**
     * HxFonts quietly falls back to the system font when one won't load, which
     * would make these images lie; load them here without that net.
     */
    private fun checkFonts(fontsDir: File) {
        require(fontsDir.isDirectory) { "no fonts at $fontsDir" }
        for (family in HxFonts.Family.entries) {
            val file = File(fontsDir, family.file)
            checkNotNull(
                Typeface.Builder(file).setFontVariationSettings("'wght' 700").build(),
            ) { "${family.file} did not load (exists=${file.exists()}, ${file.length()} bytes)" }
        }
    }

    /**
     * Contact sheets for judging the glass: every transparency level down the
     * side, squircle and pill 2x1 plus a 2x2 across, over a loud stand-in for a
     * wallpaper. `looks_dark.png` and `looks_light.png` go into [out]. Review
     * only; never shipped.
     */
    fun renderLooks(fontsDir: File, out: File): Int {
        checkFonts(fontsDir)
        out.mkdirs()
        val fonts = HxFonts.fromDirectory(fontsDir)
        val density = 2f
        val gap = 16f
        val cols = 4
        val widthDp = gap + cols * (W2 + gap)
        val heightDp = gap + 3 * (H2 + gap)

        for ((name, base) in listOf(
            "dark" to HxWidgetPalette.CLASSIC_BLUE_DARK,
            "light" to HxWidgetPalette.CLASSIC_BLUE_LIGHT,
        )) {
            val sheet = Bitmap.createBitmap((widthDp * density).toInt(), (heightDp * density).toInt(), Bitmap.Config.ARGB_8888)
            val canvas = Canvas(sheet)
            canvas.scale(density, density)
            drawBusyBackdrop(canvas, widthDp, heightDp)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)

            fun place(rendered: HxRendered, x: Float, y: Float, w: Float, h: Float) {
                canvas.drawBitmap(rendered.bitmap, null, RectF(x, y, x + w, y + h), paint)
            }
            for (level in 1..3) {
                val rowY = gap + (level - 1) * (H2 + gap)
                fun renderer(shape: HxCornerShape, pillEligible: Boolean) = HxWidgetRenderer(
                    fonts,
                    base.copy(look = HxWidgetLook(level, shape)).forWidget(pillEligible),
                    density,
                )
                val protein = HxMacro(112, 160)
                val midY = rowY + (H2 - H1) / 2
                place(renderer(HxCornerShape.SQUIRCLE, true).macro(W2, H1, HxMacroKind.PROTEIN, protein), gap, midY, W2, H1)
                place(renderer(HxCornerShape.PILL, true).macro(W2, H1, HxMacroKind.PROTEIN, protein), gap * 2 + W2, midY, W2, H1)
                place(renderer(HxCornerShape.PILL, true).quickLog(W2, H1), gap * 3 + W2 * 2, midY, W2, H1)
                // A 2x2 under a pill setting must stay a squircle.
                place(
                    renderer(HxCornerShape.PILL, false).recovery(W2, H2, HxRecovery(78, listOf("Quads" to 42, "Chest" to 61))),
                    gap * 4 + W2 * 3, rowY, W2, H2,
                )
            }
            File(out, "looks_$name.png").outputStream().use {
                check(sheet.compress(Bitmap.CompressFormat.PNG, 100, it)) { "PNG encode failed for looks_$name" }
            }
        }
        return 2
    }

    /** Bright diagonal bands, rings and stripes: the worst case for a see-through card. */
    private fun drawBusyBackdrop(canvas: Canvas, w: Float, h: Float) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(
            0f, 0f, w, h,
            intArrayOf(0xFFFF7A18.toInt(), 0xFFAF002D.toInt(), 0xFF319197.toInt(), 0xFFFFD60A.toInt()),
            null, Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, w, h, paint)
        paint.shader = null
        paint.color = 0xFFFFFFFF.toInt()
        for (i in 0 until 14) canvas.drawRect(i * 62f - 20f, 0f, i * 62f - 6f, h, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 14f
        paint.color = 0xFF111111.toInt()
        for (i in 0 until 6) canvas.drawCircle(w * (0.1f + 0.17f * i), h * (0.18f + 0.13f * i), 60f, paint)
    }

    /** Draws every preview into [out] as `widget_preview_<name>.png`. */
    fun render(fontsDir: File, out: File): Int {
        checkFonts(fontsDir)
        out.mkdirs()
        val r = HxWidgetRenderer(HxFonts.fromDirectory(fontsDir), HxWidgetPalette.CLASSIC_BLUE_DARK, DENSITY)
        val previews = previews(r)
        for ((name, rendered) in previews) {
            File(out, "widget_preview_$name.png").outputStream().use {
                check(rendered.bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) { "PNG encode failed for $name" }
            }
        }
        return previews.size
    }

    /** Keyed by the `widget_info_<name>.xml` each one belongs to. */
    private fun previews(r: HxWidgetRenderer): Map<String, HxRendered> {
        val nutrition = HxNutrition(
            goal = 2400, food = 1480, exercise = 320, remaining = 1240,
            protein = HxMacro(112, 160), carbs = HxMacro(168, 260), fat = HxMacro(46, 70),
        )
        val week = listOf(
            HxWeekDay("M", 5, today = false, done = true, scheduled = false),
            HxWeekDay("T", 6, today = false, done = true, scheduled = false),
            HxWeekDay("W", 7, today = true, done = false, scheduled = true),
            HxWeekDay("T", 8, today = false, done = false, scheduled = true),
            HxWeekDay("F", 9, today = false, done = false, scheduled = false),
            HxWeekDay("S", 10, today = false, done = false, scheduled = true),
            HxWeekDay("S", 11, today = false, done = false, scheduled = false),
        )
        val weight = HxTrend("82.4", "kg · Oct 6", listOf(83.6f, 83.4f, 83.1f, 83.2f, 82.8f, 82.6f, 82.4f), 80f)
        val intake = HxTrend("2,310", "kcal/day", listOf(2480f, 2210f, 2390f, 2150f, 2520f, 2260f, 2310f), 2400f)

        return mapOf(
            "today_calories_medium" to r.today(W4, H2, nutrition),
            "today_calories_small" to r.calories(W2, H2, nutrition),
            "today_macros_medium" to r.macros(W4, H1, nutrition),
            "recovery" to r.recovery(W2, H2, HxRecovery(78, listOf("Quads" to 42, "Chest" to 61))),
            "fasting" to r.fasting(W2, H2, HxFasting(11 * 3600L + 20 * 60, 16 * 3600L, "16:8", "20:30")),
            "scanner" to r.quickLog(W2, H1),
            "cns" to r.cns(W2, H1, HxCns(82, "FRESH")),
            "protein" to r.macro(W2, H1, HxMacroKind.PROTEIN, nutrition.protein),
            "carbs" to r.macro(W2, H1, HxMacroKind.CARBS, nutrition.carbs),
            "fat" to r.macro(W2, H1, HxMacroKind.FAT, nutrition.fat),
            "todays_plan" to r.todaysPlan(
                W4, H2,
                HxPlan(HxPlanState.READY, "Push Day", "6 exercises planned", "Chest 84% ready", "Start Push Day"),
            ),
            "week" to r.week(W4, H1, week),
            "bodyweight" to r.bodyweight(W2, H2, weight),
            "workout_streak" to r.streak(W2, H1, HxStreakKind.WORKOUTS, HxStreak(6, "weeks", activeToday = true)),
            "logging_streak" to r.streak(W2, H1, HxStreakKind.LOGGING, HxStreak(14, "days", activeToday = true)),
            "latest_prs" to r.latestPrs(
                W2, H2,
                HxPrs("kg", listOf(HxPr("Bench Press", "112"), HxPr("Squat", "150"), HxPr("Deadlift", "182"))),
            ),
            "volume" to r.volume(W2, H1, 42),
            "next_focus" to r.nextFocus(W2, H1, HxNextFocus("Legs", 9)),
            "supplements" to r.supplements(
                W4, H2,
                HxSupplements(
                    3, 5,
                    listOf(
                        HxSupplement("Creatine", "5 g", true),
                        HxSupplement("Vitamin D", "08:00", true),
                        HxSupplement("Omega-3", "08:00", true),
                        HxSupplement("Magnesium", "22:00", false),
                        HxSupplement("Whey", "Post-wo", false),
                    ),
                ),
            ),
            "mini_workout" to r.miniWorkout(W4, H1, HxMiniWorkout("Desk mobility", 1, 3)),
            "intake_trend" to r.intakeTrend(W2, H2, intake),
            "cycle" to r.cycle(
                W2, H2,
                HxCycle(
                    HxCyclePhase.FOLLICULAR, "Follicular", "DAY 8",
                    "Energy is rising, a good week to push intensity.", "+5% volume", 0xFFFFAB40.toInt(),
                ),
            ),
        )
    }
}

/**
 * Entry point of the throwaway APK `tool/widget_previews.ps1` builds. Copies
 * the fonts it was packed with out of its assets, renders into
 * `getExternalFilesDir()/out` and leaves `DONE` or `FAILED` (with the stack)
 * there for the script to find.
 */
class PreviewRunner : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val out = File(getExternalFilesDir(null), "out").apply { deleteRecursively(); mkdirs() }
        try {
            val fonts = File(filesDir, "fonts").apply { mkdirs() }
            // Straight in assets/: aapt2 on Windows writes nested names as
            // "assets/fonts\x.ttf", which AssetManager can't find.
            for (family in HxFonts.Family.entries) {
                assets.open(family.file).use { input ->
                    File(fonts, family.file).outputStream().use { input.copyTo(it) }
                }
            }
            val n = if (intent.getBooleanExtra("looks", false)) {
                WidgetPreviews.renderLooks(fonts, out)
            } else {
                WidgetPreviews.render(fonts, out)
            }
            File(out, "DONE").writeText("$n previews")
        } catch (t: Throwable) {
            File(out, "FAILED").writeText(t.stackTraceToString())
        }
        finish()
    }
}
