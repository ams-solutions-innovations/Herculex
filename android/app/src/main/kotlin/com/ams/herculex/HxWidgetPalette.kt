package com.ams.herculex

import android.content.Context
import android.content.res.Configuration
import org.json.JSONObject

/** Corner shape of a widget card. [PILL] and [ROUNDED] apply to the one-row 2x1 widgets. */
enum class HxCornerShape {
    SQUIRCLE,
    ROUNDED,
    PILL;

    companion object {
        fun parse(value: String?): HxCornerShape = when (value) {
            "pill" -> PILL
            "rounded", "ellipse" -> ROUNDED
            else -> SQUIRCLE
        }
    }
}

/**
 * The user's Widgets settings as the renderer sees them: how transparent the
 * glass card is, and its corner shape.
 */
data class HxWidgetLook(
    /** 1 (light glass) to 3 (most transparent). */
    val transparency: Int = DEFAULT_TRANSPARENCY,
    val shape: HxCornerShape = HxCornerShape.SQUIRCLE,
) {
    /** Share of the card surface that is opaque; the rest lets the wallpaper through. */
    val opacity: Float
        get() = when (transparency.coerceIn(MIN_TRANSPARENCY, MAX_TRANSPARENCY)) {
            1 -> 0.85f
            2 -> 0.65f
            else -> 0.45f
        }

    /**
     * Corner radius of a card [h] dp tall (and optional width [w]).
     * A pill (stadium/capsule) has semicircular ends, so its radius is
     * exactly half the height (minOf(w, h) / 2f).
     */
    fun cornerRadius(w: Float, h: Float): Float = when (shape) {
        HxCornerShape.PILL -> minOf(w, h) / 2f
        HxCornerShape.ROUNDED -> 38f
        HxCornerShape.SQUIRCLE -> HxCanvas.CARD_RADIUS
    }

    fun cornerRadius(h: Float): Float = when (shape) {
        HxCornerShape.PILL -> h / 2f
        HxCornerShape.ROUNDED -> 38f
        HxCornerShape.SQUIRCLE -> HxCanvas.CARD_RADIUS
    }

    companion object {
        const val MIN_TRANSPARENCY = 1
        const val MAX_TRANSPARENCY = 3
        const val DEFAULT_TRANSPARENCY = 1
    }
}

/** What a widget draws: [light] and [dark] are the same palette unless it [followsSystem]. */
data class HxWidgetThemes(
    val light: HxWidgetPalette,
    val dark: HxWidgetPalette,
    val followsSystem: Boolean,
)

/**
 * The slice of `HxColors` the home-screen widgets draw with.
 *
 * Flutter pushes both the light and dark palette of the selected app theme via
 * `syncTheme` (see `WidgetSyncService`), so the widgets follow the 5 app
 * themes and the light/dark setting without duplicating `hx_colors.dart` here.
 * [CLASSIC_BLUE_DARK] / [CLASSIC_BLUE_LIGHT] only cover the window before the
 * app has run once.
 */
data class HxWidgetPalette(
    val isDark: Boolean,
    /** surfaceContainerLowest — the HxCard surface. */
    val surface: Int,
    /** surfaceVariant — progress tracks, secondary buttons. */
    val surfaceVariant: Int,
    /** outlineVariant — neutral card border. */
    val outlineVariant: Int,
    val onSurface: Int,
    /** secondary — labels and units. */
    val secondary: Int,
    val primary: Int,
    val onPrimary: Int,
    val kcal: Int,
    val protein: Int,
    val carbs: Int,
    val fat: Int,
    val success: Int,
    val warning: Int,
    val danger: Int,
    val recovery: Int,
    val fasting: Int,
    /** domainNutrition. */
    val nutrition: Int,
    /** The user's glass and shape settings; the same for every palette. */
    val look: HxWidgetLook = HxWidgetLook(),
) {
    /**
     * This palette for a widget that may [pillEligible] take the pill shape;
     * every other widget stays a squircle whatever the setting says.
     */
    fun forWidget(pillEligible: Boolean): HxWidgetPalette =
        if (pillEligible || look.shape == HxCornerShape.SQUIRCLE) this
        else copy(look = look.copy(shape = HxCornerShape.SQUIRCLE))

    /** Strength of the domain tint at the gradient's start, as in `HxCard`. */
    val gradientAmount: Float get() = if (isDark) 0.16f else 0.12f

    /** Readiness colour shared by recovery and muscle scores. */
    fun scoreColor(score: Int): Int = when {
        score >= 70 -> success
        score >= 30 -> warning
        else -> danger
    }

    companion object {
        const val KEY_THEME_MODE = "widget_theme_mode"
        const val KEY_THEME_DARK = "widget_theme_dark"
        const val KEY_THEME_LIGHT = "widget_theme_light"
        const val KEY_TRANSPARENCY = "widget_transparency"
        const val KEY_SHAPE = "widget_shape"

        val CLASSIC_BLUE_DARK = HxWidgetPalette(
            isDark = true,
            surface = 0xFF111824.toInt(),
            surfaceVariant = 0xFF202A3C.toInt(),
            outlineVariant = 0xFF2B374E.toInt(),
            onSurface = 0xFFFFFFFF.toInt(),
            secondary = 0xFF94A3B8.toInt(),
            primary = 0xFF0A84FF.toInt(),
            onPrimary = 0xFFFFFFFF.toInt(),
            kcal = 0xFFFF453A.toInt(),
            protein = 0xFF4DA3FF.toInt(),
            carbs = 0xFF34C759.toInt(),
            fat = 0xFFFFD60A.toInt(),
            success = 0xFF30D158.toInt(),
            warning = 0xFFFF9F0A.toInt(),
            danger = 0xFFFF453A.toInt(),
            recovery = 0xFFBF5AF2.toInt(),
            fasting = 0xFF64D2FF.toInt(),
            nutrition = 0xFF30D158.toInt(),
        )

        val CLASSIC_BLUE_LIGHT = HxWidgetPalette(
            isDark = false,
            surface = 0xFFF5F9FF.toInt(),
            surfaceVariant = 0xFFDDE9F7.toInt(),
            outlineVariant = 0xFFCFE0F3.toInt(),
            onSurface = 0xFF0B1526.toInt(),
            secondary = 0xFF64748B.toInt(),
            primary = 0xFF0A84FF.toInt(),
            onPrimary = 0xFFFFFFFF.toInt(),
            kcal = 0xFFE0362C.toInt(),
            protein = 0xFF1F6FD6.toInt(),
            carbs = 0xFF248A3D.toInt(),
            fat = 0xFFD97706.toInt(),
            success = 0xFF1E7A34.toInt(),
            warning = 0xFFB36A00.toInt(),
            danger = 0xFFC7261C.toInt(),
            recovery = 0xFF8036B8.toInt(),
            fasting = 0xFF0083A8.toInt(),
            nutrition = 0xFF1E7A34.toInt(),
        )

        /** Resolves the palette for the app's theme mode and the system night mode. */
        fun load(context: Context): HxWidgetPalette {
            val prefs = CnsWidgetProvider.getPrefs(context)
            val look = HxWidgetLook(
                transparency = prefs.getInt(KEY_TRANSPARENCY, HxWidgetLook.DEFAULT_TRANSPARENCY),
                shape = HxCornerShape.parse(prefs.getString(KEY_SHAPE, null)),
            )
            val systemDark = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            val dark = when (prefs.getString(KEY_THEME_MODE, "system")) {
                "dark" -> true
                "light" -> false
                else -> systemDark
            }
            val json = prefs.getString(if (dark) KEY_THEME_DARK else KEY_THEME_LIGHT, null)
            val fallback = if (dark) CLASSIC_BLUE_DARK else CLASSIC_BLUE_LIGHT
            return (json?.let { fromJson(it, dark, fallback) } ?: fallback).copy(look = look)
        }

        /**
         * Resolves the palettes for the app's theme mode. A widget is a bitmap,
         * and the system sends providers nothing when the phone flips between
         * light and dark, so with `system` both palettes are returned and the
         * layout picks one by night mode (see `widget_canvas_dark`).
         */
        fun loadThemes(context: Context): HxWidgetThemes {
            val prefs = CnsWidgetProvider.getPrefs(context)
            val look = HxWidgetLook(
                transparency = prefs.getInt(KEY_TRANSPARENCY, HxWidgetLook.DEFAULT_TRANSPARENCY),
                shape = HxCornerShape.parse(prefs.getString(KEY_SHAPE, null)),
            )
            fun palette(dark: Boolean): HxWidgetPalette {
                val json = prefs.getString(if (dark) KEY_THEME_DARK else KEY_THEME_LIGHT, null)
                val fallback = if (dark) CLASSIC_BLUE_DARK else CLASSIC_BLUE_LIGHT
                return (json?.let { fromJson(it, dark, fallback) } ?: fallback).copy(look = look)
            }
            return when (prefs.getString(KEY_THEME_MODE, "system")) {
                "dark" -> palette(true).let { HxWidgetThemes(it, it, followsSystem = false) }
                "light" -> palette(false).let { HxWidgetThemes(it, it, followsSystem = false) }
                else -> HxWidgetThemes(palette(false), palette(true), followsSystem = true)
            }
        }

        private fun fromJson(json: String, dark: Boolean, fallback: HxWidgetPalette): HxWidgetPalette? =
            try {
                val o = JSONObject(json)
                fun c(key: String, def: Int) = if (o.has(key)) o.getLong(key).toInt() else def
                HxWidgetPalette(
                    isDark = dark,
                    surface = c("surface", fallback.surface),
                    surfaceVariant = c("surfaceVariant", fallback.surfaceVariant),
                    outlineVariant = c("outlineVariant", fallback.outlineVariant),
                    onSurface = c("onSurface", fallback.onSurface),
                    secondary = c("secondary", fallback.secondary),
                    primary = c("primary", fallback.primary),
                    onPrimary = c("onPrimary", fallback.onPrimary),
                    kcal = c("kcal", fallback.kcal),
                    protein = c("protein", fallback.protein),
                    carbs = c("carbs", fallback.carbs),
                    fat = c("fat", fallback.fat),
                    success = c("success", fallback.success),
                    warning = c("warning", fallback.warning),
                    danger = c("danger", fallback.danger),
                    recovery = c("recovery", fallback.recovery),
                    fasting = c("fasting", fallback.fasting),
                    nutrition = c("nutrition", fallback.nutrition),
                )
            } catch (_: Exception) {
                null
            }
    }
}
