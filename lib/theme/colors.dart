import 'package:flutter/material.dart';

/// iOS-inspired palette with Light and Dark mode support.
class AppColors {
  static Brightness brightness = Brightness.dark;
  static bool get _isDark => brightness == Brightness.dark;

  // ── Light Blue Background Gradient ──
  static LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _isDark
            ? const [
                Color(0xFF0D1B2A), // Deep light-blue dark glow top-left
                Color(0xFF091322), // Midnight deep ice blue
                Color(0xFF040913), // Base dark bottom-right
              ]
            : const [
                Color(0xFFE2F0FD), // Soft light sky blue top-left
                Color(0xFFEBF4FE), // Gentle ice light blue
                Color(0xFFF2F7FC), // Subtle soft blue-gray bottom-right
              ],
      );

  // ── Core iOS palette ──
  static Color get background => _isDark ? const Color(0xFF091322) : const Color(0xFFEBF4FE);
  static Color get primary => const Color(0xFF0A84FF);
  static Color get primaryContainer => _isDark ? const Color(0xFF1C4A7E) : const Color(0xFFD0E3FF);
  static Color get onSurface => _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color get secondary => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color get tertiary => _isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  static Color get onSurfaceVariant => _isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);

  // ── Elevated surfaces (Pills / Cards) ──
  static Color get surfaceContainer => _isDark ? const Color(0xFF161E2E) : const Color(0xFFFFFFFF);
  static Color get surfaceContainerLowest => _isDark ? const Color(0xFF111824) : const Color(0xFFFFFFFF);
  static Color get surfaceVariant => _isDark ? const Color(0xFF202A3C) : const Color(0xFFE8F1FA);

  // ── Lines / borders ──
  static Color get outlineVariant => _isDark ? const Color(0xFF2B374E) : const Color(0xFFD6E3F2);
  static Color get outline => _isDark ? const Color(0xFF3B4C69) : const Color(0xFFCBD5E1);

  // ── Legacy aliases ──
  static Color get earthBrown => primary;

  // ── Macronutrients ──
  // One source of truth so rings, grids, chips and charts never disagree.
  // Calories blue, protein yellow, carbs dark grey, fats white — the fats
  // swatch flips to near-black in light mode so it stays legible on white.
  static Color get macroKcal => const Color(0xFF0A84FF);
  static Color get macroProtein => _isDark ? const Color(0xFFFFD60A) : const Color(0xFFE0A800);
  static Color get macroCarbs => _isDark ? const Color(0xFF6E7787) : const Color(0xFF4A5261);
  static Color get macroFat => _isDark ? const Color(0xFFF2F5F9) : const Color(0xFF1C1C1E);

  // ── Dark-mode aliases ──
  static Color get darkBackground => const Color(0xFF091322);
  static Color get darkOnSurface => const Color(0xFFFFFFFF);
  static Color get darkSurfaceContainer => const Color(0xFF161E2E);
  static Color get darkSurfaceContainerLowest => const Color(0xFF111824);
  static Color get darkSurfaceVariant => const Color(0xFF202A3C);
  static Color get darkOutlineVariant => const Color(0xFF2B374E);
  static Color get darkPrimary => const Color(0xFF0A84FF);
}

