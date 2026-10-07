package com.ams.herculex

import android.content.Context
import android.content.res.Configuration
import org.json.JSONObject

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
) {
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
            val systemDark = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            val dark = when (prefs.getString(KEY_THEME_MODE, "system")) {
                "dark" -> true
                "light" -> false
                else -> systemDark
            }
            val json = prefs.getString(if (dark) KEY_THEME_DARK else KEY_THEME_LIGHT, null)
            val fallback = if (dark) CLASSIC_BLUE_DARK else CLASSIC_BLUE_LIGHT
            return json?.let { fromJson(it, dark, fallback) } ?: fallback
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
